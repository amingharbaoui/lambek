function Connect-LambekMcpServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Server,

        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 10
    )

    # Command: npx and other .cmd files need cmd.exe on Windows
    $command = Get-Command -Name $Server.Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        throw "Command '$($Server.Command)' was not found."
    }

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $command.Source
    if ($IsWindows -and $command.Source -match '\.(cmd|bat)$') {
        $info.FileName = $env:ComSpec
        foreach ($item in '/d', '/c', $command.Source) { $info.ArgumentList.Add($item) }
    }
    foreach ($item in $Server.Arguments) { $info.ArgumentList.Add($item) }
    foreach ($key in $Server.Env.Keys) { $info.Environment[$key] = $Server.Env[$key] }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardInputEncoding = $utf8
    $info.StandardOutputEncoding = $utf8

    $process = [System.Diagnostics.Process]::Start($info)
    # Logs on stderr are read and ignored so the server never blocks
    $process.BeginErrorReadLine()

    $connection = @{
        Name    = $Server.Name
        Process = $process
        Reader  = $null
        NextId  = 1
        Era     = 'modern'
        Version = $script:McpVersion
        Server  = $null
    }

    try {
        # Probe: modern servers answer server/discover, legacy servers need initialize
        $probe = Invoke-LambekMcpRequest -Connection $connection -Method 'server/discover' -TimeoutMs ($TimeoutSeconds * 1000)
        $supported = @()
        if ($probe.Result) {
            $supported = @($probe.Result.supportedVersions)
            if ($probe.Result.Contains('_meta') -and $probe.Result._meta.Contains('io.modelcontextprotocol/serverInfo')) {
                $connection.Server = $probe.Result._meta['io.modelcontextprotocol/serverInfo']
            }
        }
        elseif ($probe.Error -and $probe.Error.code -eq -32022 -and $probe.Error.Contains('data')) {
            $supported = @($probe.Error.data.supported)
        }

        if ($probe.Result -or ($probe.Error -and $probe.Error.code -eq -32022)) {
            if ($script:McpVersion -notin $supported) {
                throw "The server only supports MCP $($supported -join ', ')."
            }
        }
        else {
            $connection.Era = 'legacy'
            $connection.Version = $script:McpLegacyVersion
            $initialize = Invoke-LambekMcpRequest -Connection $connection -Method 'initialize' -TimeoutMs ($TimeoutSeconds * 1000) -Params ([ordered]@{
                    protocolVersion = $script:McpLegacyVersion
                    capabilities    = @{}
                    clientInfo      = $script:McpClientInfo
                })
            if ($initialize.TimedOut) { throw 'The server did not answer.' }
            if ($initialize.Error) { throw "The server refused to start: $($initialize.Error.message)" }

            $connection.Version = [string] $initialize.Result.protocolVersion
            if ($initialize.Result.Contains('serverInfo')) { $connection.Server = $initialize.Result.serverInfo }
            Send-LambekMcpMessage -Connection $connection -Message ([ordered]@{ jsonrpc = '2.0'; method = 'notifications/initialized' })
        }

        # Tools, page by page
        $tools = [System.Collections.Generic.List[object]]::new()
        $cursor = $null
        do {
            $params = [ordered]@{}
            if ($cursor) { $params.cursor = $cursor }
            $page = Invoke-LambekMcpRequest -Connection $connection -Method 'tools/list' -Params $params -TimeoutMs ($TimeoutSeconds * 1000)
            if ($page.TimedOut) { throw 'The server did not list its tools.' }
            if ($page.Error) { throw "The server could not list its tools: $($page.Error.message)" }

            foreach ($tool in @($page.Result.tools)) { $tools.Add($tool) }
            $cursor = $null
            if ($page.Result.Contains('nextCursor')) { $cursor = $page.Result.nextCursor }
        } while ($cursor -and $tools.Count -lt 1000)

        $connection.Tools = $tools.ToArray()
        return $connection
    }
    catch {
        Disconnect-LambekMcpServer -Connection $connection
        throw
    }
}

function Disconnect-LambekMcpServer {
    param([hashtable] $Connection)

    # Close stdin, wait, then stop the process
    $process = $Connection.Process
    if ($null -eq $process -or $process.HasExited) { return }
    try { $process.StandardInput.Close() } catch { Write-Verbose $_.Exception.Message }
    if (-not $process.WaitForExit(2000)) {
        try { $process.Kill($true) } catch { Write-Verbose $_.Exception.Message }
    }
}
