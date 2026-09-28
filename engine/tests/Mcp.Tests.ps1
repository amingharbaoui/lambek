BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    $pwsh = (Get-Process -Id $PID).Path
    $fixture = Join-Path $PSScriptRoot 'Fixtures/NotesServer.ps1'

    function New-McpConfig {
        param([string] $Folder, [switch] $Legacy, [string] $Command = $pwsh)

        $arguments = @('-NoProfile', '-NonInteractive', '-File', $fixture, '-Log', (Join-Path $Folder 'server.log'))
        if ($Legacy) { $arguments += '-Legacy' }
        $path = Join-Path $Folder 'mcp.json'
        @{ mcpServers = @{ notes = @{ command = $Command; args = $arguments } } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
        return $path
    }

    function Get-ServerLog {
        param([string] $Folder)
        $path = Join-Path $Folder 'server.log'
        if (-not (Test-Path -LiteralPath $path)) { return @() }
        return @(Get-Content -LiteralPath $path | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
    }
}

AfterAll {
    Disconnect-LambekMcp
}

Describe 'Connect-LambekMcp' {

    BeforeEach {
        Disconnect-LambekMcp
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $folder -ItemType Directory | Out-Null
        $cache = Join-Path $folder 'cache.json'
    }

    It 'connects to a modern server and turns its tools into actions' {
        $server = Connect-LambekMcp -Path (New-McpConfig $folder) -CachePath $cache -Refresh

        $server.Status | Should -Be 'Connected'
        $server.Era | Should -Be 'modern'
        $server.Version | Should -Be '2026-07-28'
        $server.Tools.Name | Should -Be @('search_notes', 'create_note', 'delete_note')
        $server.Tools.Risk | Should -Be @('low', 'medium', 'high')
        $server.Skipped.Tool | Should -Be 'upload_blob'
    }

    It 'sends the protocol version and client on every modern request' {
        Connect-LambekMcp -Path (New-McpConfig $folder) -CachePath $cache -Refresh | Out-Null

        $log = Get-ServerLog $folder
        $log.method | Should -Be @('server/discover', 'tools/list', 'tools/list')
        foreach ($message in $log) {
            $message.params._meta['io.modelcontextprotocol/protocolVersion'] | Should -Be '2026-07-28'
            $message.params._meta['io.modelcontextprotocol/clientInfo'].name | Should -Be 'Lambek'
        }
    }

    It 'falls back to the initialize handshake for a legacy server' {
        $server = Connect-LambekMcp -Path (New-McpConfig $folder -Legacy) -CachePath $cache -Refresh

        $server.Era | Should -Be 'legacy'
        $server.Version | Should -Be '2025-11-25'
        (Get-ServerLog $folder).method | Should -Contain 'notifications/initialized'
    }

    It 'uses the cached tool list without starting the server' {
        $config = New-McpConfig $folder
        Connect-LambekMcp -Path $config -CachePath $cache -Refresh | Out-Null
        Disconnect-LambekMcp
        Remove-Item -LiteralPath (Join-Path $folder 'server.log')

        $server = Connect-LambekMcp -Path $config -CachePath $cache
        $server.Status | Should -Be 'Ready'
        $server.Running | Should -BeFalse
        $server.Tools.Count | Should -Be 3
        Test-Path (Join-Path $folder 'server.log') | Should -BeFalse
    }

    It 'reports a server that cannot start' {
        $server = Connect-LambekMcp -Path (New-McpConfig $folder -Command 'lambek-no-such-command') -CachePath $cache -Refresh

        $server.Status | Should -Be 'Failed'
        $server.Error | Should -BeLike "*'lambek-no-such-command' was not found*"
        Get-LambekPack | Where-Object Name -EQ 'mcp-notes' | Should -BeNullOrEmpty
    }

    It 'rejects a config without mcpServers' {
        $path = Join-Path $folder 'bad.json'
        Set-Content -LiteralPath $path -Value '{ "servers": {} }'
        { Connect-LambekMcp -Path $path -CachePath $cache } | Should -Throw '*mcpServers*'
    }
}

Describe 'MCP tools in plans' {

    BeforeAll {
        $folder = Join-Path $TestDrive 'plans'
        New-Item -Path $folder -ItemType Directory | Out-Null
        $audit = Join-Path $folder 'audit.jsonl'
        Connect-LambekMcp -Path (New-McpConfig $folder) -CachePath (Join-Path $folder 'cache.json') -Refresh | Out-Null
    }

    It 'plans a tool call from plain language' {
        $plan = New-LambekPlan 'search notes query "budget"'

        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Action | Should -Be 'mcp-notes.search-notes'
        $plan.Steps[0].Output | Should -Be 'mcp'
        ($plan.Steps[0].Script | ConvertFrom-Json).arguments.query | Should -Be 'budget'
        ($plan | ConvertTo-LambekAnswer) | Should -Be ("I'll search notes, query ""budget"".", 'The notes server marks this tool as read-only.' -join "`n")
    }

    It 'fills numbers and choices from the input schema' {
        $plan = New-LambekPlan 'create note title "groceries" priority high'

        $plan.Steps[0].Action | Should -Be 'mcp-notes.create-note'
        $plan.Steps[0].Parameters.Priority | Should -Be 'high'
        (New-LambekPlan 'search notes query "budget" limit 5').Steps[0].Script | Should -BeLike '*"limit":5*'
    }

    It 'reads values without quotes: <Text>' -ForEach @(
        @{ Text = 'search notes for Budget'; Name = 'Query'; Value = 'Budget' }
        @{ Text = 'search notes query trip plan'; Name = 'Query'; Value = 'trip plan' }
        @{ Text = 'create note title Groceries for Sunday priority high'; Name = 'Title'; Value = 'Groceries for Sunday' }
    ) {
        $plan = New-LambekPlan $Text
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Parameters[$Name] | Should -Be $Value
    }

    It 'asks for a missing required argument' {
        New-LambekPlan 'search notes' | ConvertTo-LambekAnswer | Should -Be 'I need one more detail. What should query be?'
    }

    It 'stops arguments that break the input schema' {
        $plan = New-LambekPlan 'search notes query "budget" limit 50'
        $plan.Status | Should -Not -Be 'Ready'
        $plan.Questions | Should -Contain 'Step 1: limit must be at most 20.'
    }

    It 'runs a read-only tool without approval and shows the reply' {
        $plan = New-LambekPlan 'search notes query "budget"'
        $execution = Invoke-LambekPlan -Plan $plan -AuditPath $audit

        $execution.Status | Should -Be 'Completed'
        $execution.Steps[0].Output | Should -Be 'Found 1 note(s): budget 2026'
        ConvertTo-LambekAnswer -Plan $plan -Execution $execution | Should -BeLike '*notes replied:*Found 1 note(s): budget 2026'
    }

    It 'simulates by showing the exact call and sends nothing' {
        $plan = New-LambekPlan 'create note title "groceries"'
        $before = @(Get-ServerLog $folder | Where-Object method -EQ 'tools/call').Count

        $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
        $simulation.Steps[0].Message | Should -Be 'Would call create_note on notes. Nothing was sent.'
        @(Get-ServerLog $folder | Where-Object method -EQ 'tools/call').Count | Should -Be $before
        ConvertTo-LambekAnswer -Plan $plan -Simulation $simulation | Should -BeLike '*Lambek will call create_note on notes with {"title":"groceries"}.*'
    }

    It 'needs an approval code for a destructive tool' {
        $plan = New-LambekPlan 'delete note title "trip plan"'
        $plan.Risk | Should -Be 'high'
        (Invoke-LambekPlan -Plan $plan -AuditPath $audit).Status | Should -Be 'Refused'

        $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
        $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit
        $execution = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
        $execution.Status | Should -Be 'Completed'
        $execution.Steps[0].Output | Should -Be "Deleted note 'trip plan'."
    }

    It 'reports a tool error as a failed step' {
        $plan = New-LambekPlan 'delete note title "missing"'
        $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
        $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit

        $execution = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
        $execution.Status | Should -Be 'Failed'
        $execution.Steps[0].Error | Should -Be 'No note named missing.'
    }

    It 'refuses a plan when the tool changed after it was built' {
        $plan = New-LambekPlan 'search notes query "budget"'
        InModuleScope Lambek {
            $entry = $script:Mcp.Servers['notes']
            $tools = $entry.Tools | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
            $tools[0].inputSchema.properties.limit.maximum = 10
            Register-LambekMcpTool -Entry $entry -Tools $tools
        }

        $execution = Invoke-LambekPlan -Plan $plan -AuditPath $audit
        $execution.Status | Should -Be 'Refused'
        $execution.Reason | Should -Be 'Step 1: the MCP tool changed since the plan was built.'
    }

    It 'explains an MCP step' {
        Connect-LambekMcp -Path (Join-Path $folder 'mcp.json') -CachePath (Join-Path $folder 'cache.json') -Refresh | Out-Null
        $plan = New-LambekPlan 'search notes query "budget"'
        (Resolve-LambekFollowUp -Plan $plan -Text 'why').Answer | Should -BeLike '*The call matches the input schema of the tool.*'
    }

    It 'creates a starter config through the host' {
        $starter = Join-Path $folder 'starter/mcp.json'
        $json = InModuleScope Lambek -Parameters @{ AuditPath = $audit; Starter = $starter } {
            $previous = $script:Mcp.ConfigPath
            $script:Mcp.ConfigPath = $Starter
            try { Invoke-LambekHostRequest -Line '{"id":1,"method":"mcp","params":{"create":true}}' -AuditPath $AuditPath }
            finally { $script:Mcp.ConfigPath = $previous }
        }
        ($json | ConvertFrom-Json -AsHashtable).result.exists | Should -BeTrue
        (Get-Content -LiteralPath $starter -Raw | ConvertFrom-Json -AsHashtable).mcpServers.Count | Should -Be 0
    }

    It 'lists the servers through the host' {
        $json = InModuleScope Lambek -Parameters @{ AuditPath = $audit } {
            Invoke-LambekHostRequest -Line '{"id":1,"method":"mcp"}' -AuditPath $AuditPath
        }
        $response = $json | ConvertFrom-Json -AsHashtable
        $response.result.servers[0].name | Should -Be 'notes'
        $response.result.servers[0].tools.name | Should -Contain 'search_notes'
        $response.result.servers[0].skipped[0].tool | Should -Be 'upload_blob'
    }
}

Describe 'ConvertTo-LambekMcpPack' {

    It 'splits tool names into words: <Name>' -ForEach @(
        @{ Name = 'getUser'; Expected = 'get user' }
        @{ Name = 'read_text_file'; Expected = 'read text file' }
        @{ Name = 'admin.tools.list'; Expected = 'admin tools list' }
        @{ Name = 'DATA_EXPORT_v2'; Expected = 'data export v2' }
    ) {
        InModuleScope Lambek -Parameters @{ Name = $Name } { (Split-LambekMcpName -Name $Name) -join ' ' } | Should -Be $Expected
    }

    It 'maps the JSON types of the schema' {
        $tool = [ordered]@{
            name        = 'list_items'
            inputSchema = [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    folder    = [ordered]@{ type = 'string' }
                    max_count = [ordered]@{ type = 'integer' }
                    recursive = [ordered]@{ type = 'boolean' }
                    mode      = [ordered]@{ type = 'string'; enum = @('Fast', 'Full') }
                }
                required   = @('folder')
            }
            annotations = [ordered]@{ readOnlyHint = $true }
        }
        $pack = InModuleScope Lambek -Parameters @{ Tool = $tool } { ConvertTo-LambekMcpPack -Server 'My Server' -Tools @($Tool) }

        $pack.Data.Name | Should -Be 'mcp-my-server'
        $action = $pack.Data.Actions[0]
        $action.Id | Should -Be 'mcp-my-server.list-items'
        $action.Risk | Should -Be 'low'
        $action.Parameters.Name | Should -Be @('Folder', 'MaxCount', 'Recursive', 'Mode')
        $action.Parameters[0].Required | Should -BeTrue
        $action.Parameters[1].Entities | Should -Be 'number'
        $action.Parameters[2].Words.recursive | Should -Be 'true'
        $action.Parameters[3].Words.full | Should -Be 'Full'
    }
}
