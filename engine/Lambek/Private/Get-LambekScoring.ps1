function Get-LambekScoring {
    [CmdletBinding()]
    param()

    $path = Join-Path $PSScriptRoot '../Data/scoring.json'
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable

    # Weights must add up to 1
    $total = 0.0
    foreach ($weight in $data.Weights.Values) {
        $total += $weight
    }
    if ([math]::Abs($total - 1.0) -gt 0.0001) {
        throw "Scoring weights must add up to 1 (found $total)."
    }

    return [pscustomobject]@{
        Weights     = $data.Weights
        Threshold   = [double] $data.Threshold
        Margin      = [double] $data.Margin
        Margins     = $data['Margins']
        Correlation = $data['Correlation']
    }
}
