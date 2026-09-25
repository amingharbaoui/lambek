function Get-LambekBenchmarkCase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('all', 'calibration', 'test')]
        [string] $Split = 'all'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Benchmark file not found: $Path"
    }

    $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $cases = @($data.Cases | Where-Object { $Split -eq 'all' -or $_.Split -eq $Split })

    if ($cases.Count -eq 0) {
        throw "No benchmark case for split '$Split'."
    }
    return $cases
}
