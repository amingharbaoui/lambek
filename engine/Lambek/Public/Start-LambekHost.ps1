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

        [string] $AuditPath = $script:AuditPath
    )

    # Packs
    foreach ($path in $PackPath) {
        Import-LambekPack -Path $path | Out-Null
    }

    # Ready message
    $ready = [ordered]@{ event = 'ready'; version = (Get-Module Lambek).Version.ToString(); packs = @(Get-LambekPack | ForEach-Object { $_.Name }) }
    [Console]::Out.WriteLine(($ready | ConvertTo-Json -Compress))
    [Console]::Out.Flush()

    # One request per line until standard input closes
    while ($true) {
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $response = Invoke-LambekHostRequest -Line $line -AuditPath $AuditPath
        [Console]::Out.WriteLine($response)
        [Console]::Out.Flush()
    }
}
