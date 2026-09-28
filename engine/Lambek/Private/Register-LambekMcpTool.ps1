function Register-LambekMcpTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Entry,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Tools
    )

    # One pack per server, rebuilt from its tool list
    $converted = ConvertTo-LambekMcpPack -Server $Entry.Name -Tools $Tools
    $Entry.Tools = $Tools
    $Entry.Skipped = $converted.Skipped
    $Entry.Pack = $converted.Data.Name

    if ($converted.Data.Actions.Count -gt 0) {
        Register-LambekPack -Data $converted.Data -Source "mcp:$($Entry.Name)" | Out-Null
    }
    else {
        Clear-LambekMcpPack -Name $converted.Data.Name
    }
}

function Clear-LambekMcpPack {
    param([string] $Name)

    if ($Name -and $script:Packs.Contains($Name)) {
        $script:Packs.Remove($Name)
        $script:LexiconCache.Clear()
        $script:ActionIndexCache.Clear()
    }
}

function Save-LambekMcpCache {
    param([string] $Path)

    $cache = [ordered]@{}
    foreach ($entry in $script:Mcp.Servers.Values) {
        if ($entry.Status -notin 'Connected', 'Ready') { continue }
        $cache[$entry.Name] = [ordered]@{ Hash = $entry.Config.Hash; Era = $entry.Era; Version = $entry.Version; Tools = @($entry.Tools) }
    }

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value ($cache | ConvertTo-Json -Depth 60 -Compress) -Encoding utf8NoBOM
}
