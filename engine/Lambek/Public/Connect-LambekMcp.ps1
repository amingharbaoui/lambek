function Connect-LambekMcp {
    <#
    .SYNOPSIS
        Reads the MCP config and turns the tools of every server into Lambek actions.
    .DESCRIPTION
        The config uses the standard "mcpServers" format. Tool lists are cached, so servers
        only start when one of their tools runs, or when -Refresh is used.
    .EXAMPLE
        Connect-LambekMcp -Path ./mcp.json -Refresh
    #>
    [CmdletBinding()]
    param(
        [string] $Path = $script:Mcp.ConfigPath,

        [switch] $Refresh,

        [string] $CachePath = $script:Mcp.CachePath,

        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 10
    )

    $servers = @(Get-LambekMcpConfig -Path $Path)
    $script:Mcp.ConfigPath = $Path
    $script:Mcp.CachePath = $CachePath

    # Cached tool lists
    $cache = @{}
    if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
        try { $cache = Get-Content -LiteralPath $CachePath -Raw | ConvertFrom-Json -AsHashtable }
        catch { $cache = @{} }
        if ($cache -isnot [System.Collections.IDictionary]) { $cache = @{} }
    }

    # Servers removed from the config
    foreach ($name in @($script:Mcp.Servers.Keys)) {
        if ($name -in $servers.Name) { continue }
        $old = $script:Mcp.Servers[$name]
        if ($old.Connection) { Disconnect-LambekMcpServer -Connection $old.Connection }
        Clear-LambekMcpPack -Name $old.Pack
        $script:Mcp.Servers.Remove($name)
    }

    foreach ($server in $servers) {
        # A running server with the same config stays as it is
        $old = $null
        if ($script:Mcp.Servers.Contains($server.Name)) { $old = $script:Mcp.Servers[$server.Name] }
        if ($old -and -not $Refresh -and $old.Config.Hash -eq $server.Hash -and $old.Status -in 'Connected', 'Ready') { continue }
        if ($old -and $old.Connection) { Disconnect-LambekMcpServer -Connection $old.Connection }

        $entry = [ordered]@{
            Name       = $server.Name
            Config     = $server
            Pack       = 'mcp-' + (($server.Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
            Connection = $null
            Status     = 'Disabled'
            Era        = $null
            Version    = $null
            Tools      = @()
            Skipped    = @()
            Error      = $null
        }
        $script:Mcp.Servers[$server.Name] = $entry

        if ($server.Disabled) {
            Clear-LambekMcpPack -Name $entry.Pack
            continue
        }

        try {
            $cached = $null
            if ($cache.Contains($server.Name)) { $cached = $cache[$server.Name] }
            if (-not $Refresh -and $cached -and $cached.Hash -eq $server.Hash) {
                $entry.Status = 'Ready'
                $entry.Era = $cached.Era
                $entry.Version = $cached.Version
                Register-LambekMcpTool -Entry $entry -Tools @($cached.Tools)
            }
            else {
                $connection = Connect-LambekMcpServer -Server $server -TimeoutSeconds $TimeoutSeconds
                $entry.Connection = $connection
                $entry.Status = 'Connected'
                $entry.Era = $connection.Era
                $entry.Version = $connection.Version
                Register-LambekMcpTool -Entry $entry -Tools @($connection.Tools)
            }
        }
        catch {
            $entry.Status = 'Failed'
            $entry.Error = $_.Exception.Message
            Clear-LambekMcpPack -Name $entry.Pack
        }
    }

    Save-LambekMcpCache -Path $CachePath
    Get-LambekMcpServer
}
