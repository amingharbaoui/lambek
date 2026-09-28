# Small MCP server over stdio for the tests: modern by default, legacy with -Legacy
param(
    [switch] $Legacy,
    [string] $Log
)

$ErrorActionPreference = 'Stop'
$notes = [System.Collections.Generic.List[string]]::new()
$notes.Add('budget 2026')
$notes.Add('trip plan')

$tools = @(
    [ordered]@{
        name        = 'search_notes'
        title       = 'Search notes'
        description = 'Find notes that contain a text.'
        inputSchema = [ordered]@{
            type       = 'object'
            properties = [ordered]@{
                query = [ordered]@{ type = 'string'; description = 'Text to find' }
                limit = [ordered]@{ type = 'integer'; minimum = 1; maximum = 20 }
            }
            required   = @('query')
        }
        annotations = [ordered]@{ readOnlyHint = $true }
    }
    [ordered]@{
        name        = 'create_note'
        description = 'Create a note.'
        inputSchema = [ordered]@{
            type                 = 'object'
            properties           = [ordered]@{
                title    = [ordered]@{ type = 'string'; minLength = 1 }
                priority = [ordered]@{ type = 'string'; enum = @('low', 'normal', 'high') }
            }
            required             = @('title')
            additionalProperties = $false
        }
        annotations = [ordered]@{ readOnlyHint = $false; destructiveHint = $false }
    }
    [ordered]@{
        name        = 'delete_note'
        description = 'Delete a note.'
        inputSchema = [ordered]@{
            type       = 'object'
            properties = [ordered]@{ title = [ordered]@{ type = 'string' } }
            required   = @('title')
        }
    }
    [ordered]@{
        name        = 'upload_blob'
        description = 'Upload structured data.'
        inputSchema = [ordered]@{
            type       = 'object'
            properties = [ordered]@{ data = [ordered]@{ type = 'object' } }
            required   = @('data')
        }
    }
)

function Send-Message {
    param([System.Collections.IDictionary] $Message)
    [Console]::Out.WriteLine(($Message | ConvertTo-Json -Depth 20 -Compress))
    [Console]::Out.Flush()
}

function Send-Result {
    param($Id, [System.Collections.IDictionary] $Result)
    if (-not $Legacy) { $Result.resultType = 'complete' }
    Send-Message ([ordered]@{ jsonrpc = '2.0'; id = $Id; result = $Result })
}

function Send-Error {
    param($Id, [int] $Code, [string] $Text)
    Send-Message ([ordered]@{ jsonrpc = '2.0'; id = $Id; error = [ordered]@{ code = $Code; message = $Text } })
}

function Get-Text {
    param([string] $Text, [bool] $IsError = $false)
    [ordered]@{ content = @([ordered]@{ type = 'text'; text = $Text }); isError = $IsError }
}

[Console]::Error.WriteLine('notes server started')

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    if ($Log) { Add-Content -LiteralPath $Log -Value $line }

    $message = $line | ConvertFrom-Json -AsHashtable
    if (-not $message.Contains('id')) { continue }
    $id = $message.id
    $params = @{}
    if ($message.Contains('params')) { $params = $message.params }

    # Modern requests carry their version in _meta
    if (-not $Legacy -and $message.method -ne 'initialize') {
        $meta = $null
        if ($params.Contains('_meta')) { $meta = $params._meta }
        if ($null -eq $meta -or -not $meta.Contains('io.modelcontextprotocol/protocolVersion')) {
            Send-Error $id -32602 'Missing _meta'
            continue
        }
        if ($meta['io.modelcontextprotocol/protocolVersion'] -ne '2026-07-28') {
            Send-Message ([ordered]@{ jsonrpc = '2.0'; id = $id; error = [ordered]@{ code = -32022; message = 'Unsupported protocol version'; data = [ordered]@{ supported = @('2026-07-28') } } })
            continue
        }
    }

    switch ($message.method) {
        'server/discover' {
            if ($Legacy) { Send-Error $id -32601 'Method not found'; break }
            Send-Result $id ([ordered]@{
                    supportedVersions = @('2026-07-28')
                    capabilities      = [ordered]@{ tools = @{} }
                    _meta             = [ordered]@{ 'io.modelcontextprotocol/serverInfo' = [ordered]@{ name = 'notes'; version = '1.0.0' } }
                })
        }
        'initialize' {
            if (-not $Legacy) { Send-Error $id -32601 'Method not found'; break }
            Send-Result $id ([ordered]@{
                    protocolVersion = '2025-11-25'
                    capabilities    = [ordered]@{ tools = @{} }
                    serverInfo      = [ordered]@{ name = 'notes'; version = '1.0.0' }
                })
        }
        'tools/list' {
            # A log notification first, then two pages
            Send-Message ([ordered]@{ jsonrpc = '2.0'; method = 'notifications/message'; params = [ordered]@{ level = 'info'; data = 'listing' } })
            if ($params.Contains('cursor') -and $params.cursor -eq 'page-2') {
                Send-Result $id ([ordered]@{ tools = @($tools[2], $tools[3]) })
            }
            else {
                Send-Result $id ([ordered]@{ tools = @($tools[0], $tools[1]); nextCursor = 'page-2' })
            }
        }
        'tools/call' {
            $arguments = @{}
            if ($params.Contains('arguments')) { $arguments = $params.arguments }
            switch ($params.name) {
                'search_notes' {
                    $found = @($notes | Where-Object { $_ -like "*$($arguments.query)*" })
                    Send-Result $id (Get-Text "Found $($found.Count) note(s): $($found -join ', ')")
                }
                'create_note' {
                    $notes.Add($arguments.title)
                    Send-Result $id (Get-Text "Created note '$($arguments.title)'.")
                }
                'delete_note' {
                    if ($notes.Remove($arguments.title)) { Send-Result $id (Get-Text "Deleted note '$($arguments.title)'.") }
                    else { Send-Result $id (Get-Text "No note named $($arguments.title)." $true) }
                }
                default { Send-Error $id -32602 "Unknown tool: $($params.name)" }
            }
        }
        default {
            Send-Error $id -32601 'Method not found'
        }
    }
}
