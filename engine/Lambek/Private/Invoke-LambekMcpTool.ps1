function Invoke-LambekMcpTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Script,

        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 60
    )

    $call = $Script | ConvertFrom-Json -AsHashtable
    $entry = $null
    if ($script:Mcp.Servers.Contains($call.server)) { $entry = $script:Mcp.Servers[$call.server] }
    if ($null -eq $entry -or $entry.Status -in 'Failed', 'Disabled') {
        return New-LambekMcpResult -ErrorText "The MCP server '$($call.server)' is not available."
    }

    # The server starts on first use, with a fresh tool list
    try {
        if ($null -eq $entry.Connection -or $entry.Connection.Process.HasExited) {
            $entry.Connection = Connect-LambekMcpServer -Server $entry.Config
            $entry.Era = $entry.Connection.Era
            $entry.Version = $entry.Connection.Version
            $entry.Status = 'Connected'
            Register-LambekMcpTool -Entry $entry -Tools $entry.Connection.Tools
            Save-LambekMcpCache -Path $script:Mcp.CachePath
        }
    }
    catch {
        return New-LambekMcpResult -ErrorText "The MCP server '$($call.server)' did not start: $($_.Exception.Message)"
    }

    # The tool must be exactly the one the plan was built for
    $tool = $entry.Tools | Where-Object { $_.name -ceq $call.tool } | Select-Object -First 1
    if ($null -eq $tool) {
        return New-LambekMcpResult -ErrorText "The tool '$($call.tool)' is no longer offered by '$($call.server)'."
    }
    if ((Get-LambekMcpToolHash -Tool $tool) -ne $call.hash) {
        return New-LambekMcpResult -ErrorText "The tool '$($call.tool)' changed since the plan was built. Ask again."
    }

    try {
        $response = Invoke-LambekMcpRequest -Connection $entry.Connection -Method 'tools/call' -TimeoutMs ($TimeoutSeconds * 1000) -Params ([ordered]@{
                name      = $call.tool
                arguments = $call.arguments
            })
    }
    catch {
        return New-LambekMcpResult -ErrorText $_.Exception.Message
    }
    if ($response.TimedOut) {
        $cancel = [ordered]@{ jsonrpc = '2.0'; method = 'notifications/cancelled'; params = [ordered]@{ requestId = $response.Id; reason = 'timeout' } }
        try { Send-LambekMcpMessage -Connection $entry.Connection -Message $cancel } catch { Write-Verbose $_.Exception.Message }
        return New-LambekMcpResult -ErrorText "The server did not answer within $TimeoutSeconds s."
    }
    if ($response.Error) {
        return New-LambekMcpResult -ErrorText $response.Error.message
    }

    $result = $response.Result
    if ($result.Contains('resultType') -and $result.resultType -notin 'complete', $null) {
        return New-LambekMcpResult -ErrorText 'The tool asked for more input, which Lambek cannot give yet.'
    }

    # Content as plain text lines
    $output = [System.Collections.Generic.List[string]]::new()
    $content = @()
    if ($result.Contains('content')) { $content = @($result.content) }
    foreach ($item in $content) {
        switch ($item.type) {
            'text' { $output.Add([string] $item.text) }
            'resource_link' { $output.Add("[link] $($item.uri)") }
            'resource' { $output.Add("[resource] $($item.resource.uri)") }
            default { $output.Add("[$($item.type)]") }
        }
    }
    if ($output.Count -eq 0 -and $result.Contains('structuredContent')) {
        $output.Add(($result.structuredContent | ConvertTo-Json -Depth 20 -Compress))
    }

    if ($result.Contains('isError') -and $result.isError -eq $true) {
        return New-LambekMcpResult -ErrorText ($output -join ' ') -Output $output.ToArray()
    }
    return New-LambekMcpResult -Output $output.ToArray()
}

function New-LambekMcpResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an object in memory.')]
    param(
        [string] $ErrorText,
        [string[]] $Output = @()
    )

    [pscustomobject]@{
        Succeeded = -not $ErrorText
        Output    = $Output
        Error     = $ErrorText
        Items     = @($Output)
    }
}
