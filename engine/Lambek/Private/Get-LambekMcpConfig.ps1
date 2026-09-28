function Get-LambekMcpConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    # Same format as claude_desktop_config.json: { "mcpServers": { "name": { "command", "args", "env" } } }
    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "The MCP config is not valid JSON: $Path"
    }
    if ($data -isnot [System.Collections.IDictionary] -or -not $data.Contains('mcpServers')) {
        throw "The MCP config needs an mcpServers object: $Path"
    }

    foreach ($name in $data.mcpServers.Keys) {
        $server = $data.mcpServers[$name]
        if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,40}$') {
            throw "MCP server name '$name' must use letters, digits, dots, dashes, or underscores."
        }
        if ($server -isnot [System.Collections.IDictionary] -or -not $server.Contains('command') -or [string]::IsNullOrWhiteSpace($server.command)) {
            throw "MCP server '$name' needs a command."
        }

        $arguments = @()
        if ($server.Contains('args')) { $arguments = @($server.args | ForEach-Object { [string] $_ }) }
        $environment = [ordered]@{}
        if ($server.Contains('env') -and $server.env -is [System.Collections.IDictionary]) {
            foreach ($key in $server.env.Keys) { $environment[$key] = [string] $server.env[$key] }
        }
        $disabled = $server.Contains('disabled') -and $server.disabled -eq $true

        # The hash tells when the cached tool list is out of date
        $hash = Get-LambekHash -Text (([ordered]@{ command = $server.command; args = $arguments; env = $environment }) | ConvertTo-Json -Depth 5 -Compress)

        [pscustomobject]@{
            Name      = $name
            Command   = [string] $server.command
            Arguments = $arguments
            Env       = $environment
            Disabled  = $disabled
            Hash      = $hash
        }
    }
}
