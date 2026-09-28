function Start-LambekHost {
    <#
    .SYNOPSIS
        Serves Lambek to the desktop app: one JSON request per line on standard input, one JSON response per line on standard output.
    .EXAMPLE
        Start-LambekHost -PackPath ./dsl/files, ./dsl/code
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts a read loop and changes nothing by itself.')]
    [CmdletBinding()]
    param(
        [string[]] $PackPath = @(),

        [string] $AuditPath = $script:AuditPath,

        [string] $McpConfig = $script:Mcp.ConfigPath
    )

    # Packs
    foreach ($path in $PackPath) {
        Import-LambekPack -Path $path | Out-Null
    }

    # MCP tools from the cache, servers start when a tool runs
    $mcpError = $null
    try {
        Connect-LambekMcp -Path $McpConfig | Out-Null
    }
    catch {
        $script:Mcp.ConfigPath = $McpConfig
        $mcpError = $_.Exception.Message
    }

    # UTF-8 in both directions, whatever the code page of the console
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), $utf8)
    $writer = [System.IO.StreamWriter]::new([Console]::OpenStandardOutput(), $utf8)
    $writer.AutoFlush = $true
    $script:HostWriter = $writer

    # Ready message, with the user name for the greeting
    $user = [Environment]::UserName
    if ($user) { $user = $user.Substring(0, 1).ToUpperInvariant() + $user.Substring(1) }
    $ready = [ordered]@{ event = 'ready'; version = (Get-Module Lambek).Version.ToString(); user = $user; packs = @(Get-LambekPack | ForEach-Object { $_.Name }); mcpError = $mcpError }
    $writer.WriteLine(($ready | ConvertTo-Json -Compress))

    # Progress lines while a request runs: { "event": "progress", "id": 3, "stage": "Match", "step": 1, "percent": 40 }
    $script:ProgressHandler = {
        param($Stage, $Step, $Percent, $Types)
        $progress = [ordered]@{ event = 'progress'; id = $script:HostRequestId; stage = $Stage; step = $Step; percent = $Percent }
        if ($Types) { $progress.types = $Types }
        $line = $progress | ConvertTo-Json -Compress
        $script:HostWriter.WriteLine($line)
    }

    # One request per line until standard input closes
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $response = Invoke-LambekHostRequest -Line $line -AuditPath $AuditPath
        $writer.WriteLine($response)
    }

    $script:ProgressHandler = $null
    $script:HostWriter = $null
    Disconnect-LambekMcp
}
