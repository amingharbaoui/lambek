function Disconnect-LambekMcp {
    <#
    .SYNOPSIS
        Stops the running MCP servers. Their tools stay available and the servers start again when needed.
    .EXAMPLE
        Disconnect-LambekMcp
    #>
    [CmdletBinding()]
    param()

    foreach ($entry in $script:Mcp.Servers.Values) {
        if ($null -eq $entry.Connection) { continue }
        Disconnect-LambekMcpServer -Connection $entry.Connection
        $entry.Connection = $null
        if ($entry.Status -eq 'Connected') { $entry.Status = 'Ready' }
    }
}
