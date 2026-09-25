BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Send-HostRequest {
        param([hashtable] $Request, [string] $AuditPath)
        $line = $Request | ConvertTo-Json -Depth 5 -Compress
        $json = InModuleScope Lambek -Parameters @{ Line = $line; AuditPath = $AuditPath } {
            Invoke-LambekHostRequest -Line $Line -AuditPath $AuditPath
        }
        return $json | ConvertFrom-Json -AsHashtable
    }
}

Describe 'Invoke-LambekHostRequest' {

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $source = Join-Path $root 'src'
        $audit = Join-Path $root 'audit.jsonl'
        New-Item -Path $source -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.log') -Value 'a'
        Set-Content -Path (Join-Path $source 'b.tmp') -Value 'b'
    }

    It 'answers ping with the version' {
        $response = Send-HostRequest @{ id = 1; method = 'ping' } $audit
        $response.id | Should -Be 1
        $response.result.name | Should -Be 'Lambek'
    }

    It 'lists the packs' {
        $response = Send-HostRequest @{ id = 1; method = 'packs' } $audit
        $response.result.name | Should -Contain 'files'
    }

    It 'returns a plan with a plain answer' {
        $response = Send-HostRequest @{ id = 2; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $response.result.status | Should -Be 'Ready'
        $response.result.answer | Should -Be "I will delete the .log files in $source."
        $response.result.steps[0].parameters.Extension | Should -Be '.log'
        $response.result.steps[0].safe | Should -BeTrue
    }

    It 'runs the whole flow: ask, simulate, approve, run' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $planId = $ask.result.id

        $simulation = Send-HostRequest @{ id = 2; method = 'simulate'; params = @{ id = $planId } } $audit
        $simulation.result.steps[0].count | Should -Be 1
        $simulation.result.confirmationCode | Should -Match '^[0-9A-F]{6}$'
        Test-Path (Join-Path $source 'a.log') | Should -BeTrue

        $approve = Send-HostRequest @{ id = 3; method = 'approve'; params = @{ id = $planId; confirmation = $simulation.result.confirmationCode } } $audit
        $approve.result.approved | Should -BeTrue

        $run = Send-HostRequest @{ id = 4; method = 'run'; params = @{ id = $planId } } $audit
        $run.result.status | Should -Be 'Completed'
        $run.result.answer | Should -BeLike '*Done.'
        Test-Path (Join-Path $source 'a.log') | Should -BeFalse
        Test-Path (Join-Path $source 'b.tmp') | Should -BeTrue
    }

    It 'refuses to approve without the confirmation code' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        Send-HostRequest @{ id = 2; method = 'simulate'; params = @{ id = $ask.result.id } } $audit | Out-Null

        $approve = Send-HostRequest @{ id = 3; method = 'approve'; params = @{ id = $ask.result.id } } $audit
        $approve.error.message | Should -BeLike '*confirmation code*'
    }

    It 'refuses to run a high-risk plan without approval' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $run = Send-HostRequest @{ id = 2; method = 'run'; params = @{ id = $ask.result.id } } $audit
        $run.result.status | Should -Be 'Refused'
        Test-Path (Join-Path $source 'a.log') | Should -BeTrue
    }

    It 'returns the audit entries' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "list the files in ""$source""" } } $audit
        Send-HostRequest @{ id = 2; method = 'simulate'; params = @{ id = $ask.result.id } } $audit | Out-Null

        $response = Send-HostRequest @{ id = 3; method = 'audit' } $audit
        $response.result.valid | Should -BeTrue
        $response.result.entries[0].Event | Should -Be 'Simulated'
    }

    It 'reports errors as JSON' -ForEach @(
        @{ Line = 'not json'; Message = '*not valid JSON*' }
        @{ Line = '{"id":1}'; Message = '*needs a method*' }
        @{ Line = '{"id":1,"method":"nope"}'; Message = "*Unknown method*" }
        @{ Line = '{"id":1,"method":"ask","params":{}}'; Message = '*needs a text*' }
        @{ Line = '{"id":1,"method":"run","params":{"id":"missing"}}'; Message = '*Unknown plan id*' }
    ) {
        $json = InModuleScope Lambek -Parameters @{ Line = $Line; AuditPath = $audit } {
            Invoke-LambekHostRequest -Line $Line -AuditPath $AuditPath
        }
        ($json | ConvertFrom-Json).error.message | Should -BeLike $Message
    }
}

Describe 'Start-LambekHost through a real process' {

    It 'reads requests on standard input and writes one JSON line per answer' {
        $module = (Resolve-Path "$PSScriptRoot/../Lambek/Lambek.psd1").Path
        $files = (Resolve-Path "$PSScriptRoot/../../dsl/files").Path
        $audit = Join-Path $TestDrive 'host-audit.jsonl'

        $info = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        $info.ArgumentList.Add('-NoProfile')
        $info.ArgumentList.Add('-NoLogo')
        $info.ArgumentList.Add('-Command')
        $info.ArgumentList.Add("Import-Module '$module'; Start-LambekHost -PackPath '$files' -AuditPath '$audit'")
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.UseShellExecute = $false

        $process = [System.Diagnostics.Process]::Start($info)
        try {
            $process.StandardInput.WriteLine('{"id":1,"method":"ping"}')
            $process.StandardInput.WriteLine('{"id":2,"method":"ask","params":{"text":"list the files in C:\\Temp"}}')
            $process.StandardInput.Close()

            $lines = @()
            while ($null -ne ($line = $process.StandardOutput.ReadLine())) { $lines += $line }
            $process.WaitForExit(30000) | Out-Null
        }
        finally {
            if (-not $process.HasExited) { $process.Kill() }
        }

        $lines.Count | Should -Be 3
        ($lines[0] | ConvertFrom-Json).event | Should -Be 'ready'
        ($lines[1] | ConvertFrom-Json).result.name | Should -Be 'Lambek'
        ($lines[2] | ConvertFrom-Json).result.answer | Should -Be 'I will list the files in C:\Temp.'
    }
}
