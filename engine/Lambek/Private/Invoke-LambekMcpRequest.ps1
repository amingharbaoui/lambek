function Invoke-LambekMcpRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Connection,

        [Parameter(Mandatory)]
        [string] $Method,

        [System.Collections.IDictionary] $Params = @{},

        [ValidateRange(100, 3600000)]
        [int] $TimeoutMs = 60000
    )

    $id = $Connection.NextId
    $Connection.NextId++

    # Modern servers read the version and capabilities from every request
    $body = [ordered]@{}
    foreach ($key in $Params.Keys) { $body[$key] = $Params[$key] }
    if ($Connection.Era -eq 'modern') {
        $body['_meta'] = [ordered]@{
            'io.modelcontextprotocol/protocolVersion'    = $Connection.Version
            'io.modelcontextprotocol/clientInfo'         = $script:McpClientInfo
            'io.modelcontextprotocol/clientCapabilities' = @{}
        }
    }
    Send-LambekMcpMessage -Connection $Connection -Message ([ordered]@{ jsonrpc = '2.0'; id = $id; method = $Method; params = $body })

    # Read until the response with the same id
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.ElapsedMilliseconds -lt $TimeoutMs) {
        $line = Receive-LambekMcpLine -Connection $Connection -TimeoutMs ([int] ($TimeoutMs - $clock.ElapsedMilliseconds))
        if ($null -eq $line) { break }

        try { $message = $line | ConvertFrom-Json -AsHashtable }
        catch { continue }
        if ($message -isnot [System.Collections.IDictionary]) { continue }

        # Legacy servers can ask the client something (ping, roots)
        if ($message.Contains('method') -and $message.Contains('id')) {
            if ($Connection.Era -eq 'legacy') {
                $reply = [ordered]@{ jsonrpc = '2.0'; id = $message.id; error = [ordered]@{ code = -32601; message = 'Not supported by Lambek.' } }
                if ($message.method -eq 'ping') { $reply = [ordered]@{ jsonrpc = '2.0'; id = $message.id; result = @{} } }
                Send-LambekMcpMessage -Connection $Connection -Message $reply
            }
            continue
        }

        # Notifications and other responses are skipped
        if (-not $message.Contains('id') -or $message.id -ne $id) { continue }

        $result = $null
        $errorItem = $null
        if ($message.Contains('error')) { $errorItem = $message.error }
        elseif ($message.Contains('result')) { $result = $message.result }
        return [pscustomobject]@{ Id = $id; Result = $result; Error = $errorItem; TimedOut = $false }
    }

    return [pscustomobject]@{ Id = $id; Result = $null; Error = $null; TimedOut = $true }
}

function Send-LambekMcpMessage {
    param(
        [hashtable] $Connection,
        [System.Collections.IDictionary] $Message
    )

    if ($Connection.Process.HasExited) {
        throw "The MCP server '$($Connection.Name)' has stopped."
    }
    $Connection.Process.StandardInput.WriteLine(($Message | ConvertTo-Json -Depth 30 -Compress))
    $Connection.Process.StandardInput.Flush()
}

function Receive-LambekMcpLine {
    param(
        [hashtable] $Connection,
        [int] $TimeoutMs
    )

    # A pending read is kept when it times out, so no line is lost
    if ($null -eq $Connection.Reader) {
        $Connection.Reader = $Connection.Process.StandardOutput.ReadLineAsync()
    }
    if (-not $Connection.Reader.Wait([math]::Max(0, $TimeoutMs))) {
        return $null
    }

    $line = $Connection.Reader.Result
    $Connection.Reader = $null
    if ($null -eq $line) {
        throw "The MCP server '$($Connection.Name)' closed its output."
    }
    return $line
}
