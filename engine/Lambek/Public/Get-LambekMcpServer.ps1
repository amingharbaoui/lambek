function Get-LambekMcpServer {
    <#
    .SYNOPSIS
        Lists the MCP servers, their state, and the actions made from their tools.
    .EXAMPLE
        Get-LambekMcpServer | Select-Object Name, Status, Tools
    #>
    [CmdletBinding()]
    param(
        [string] $Name
    )

    foreach ($entry in $script:Mcp.Servers.Values) {
        if ($Name -and $entry.Name -ne $Name) { continue }

        $actions = @()
        if ($script:Packs.Contains($entry.Pack)) { $actions = @($script:Packs[$entry.Pack].Actions) }
        $running = $null -ne $entry.Connection -and -not $entry.Connection.Process.HasExited

        [pscustomobject]@{
            PSTypeName = 'Lambek.McpServer'
            Name       = $entry.Name
            Status     = $entry.Status
            Running    = $running
            Era        = $entry.Era
            Version    = $entry.Version
            Pack       = $entry.Pack
            Tools      = @($actions | ForEach-Object {
                    [pscustomobject]@{ Name = $_.Mcp.Tool; Action = $_.Id; Title = $_.Title.en; Risk = $_.Risk; Description = $_.Description }
                })
            Skipped    = @($entry.Skipped)
            Error      = $entry.Error
        }
    }
}
