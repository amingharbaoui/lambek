function Get-LambekScoring {
    [CmdletBinding()]
    param()

    # Read once, and again only when the file changes: every request asks for it
    $path = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../Data/scoring.json'))
    $file = [IO.FileInfo]::new($path)
    $stamp = "$($file.LastWriteTimeUtc.Ticks)/$($file.Length)"
    if ($script:ScoringCache -and $script:ScoringCache.Stamp -eq $stamp) {
        return $script:ScoringCache.Scoring
    }
    $data = [IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable

    # Weights must add up to 1
    $total = 0.0
    foreach ($weight in $data.Weights.Values) {
        $total += $weight
    }
    if ([math]::Abs($total - 1.0) -gt 0.0001) {
        throw "Scoring weights must add up to 1 (found $total)."
    }

    $scoring = [pscustomobject]@{
        Weights     = $data.Weights
        Threshold   = [double] $data.Threshold
        Margin      = [double] $data.Margin
        Margins     = $data['Margins']
        Correlation = $data['Correlation']
    }
    $script:ScoringCache = @{ Stamp = $stamp; Scoring = $scoring }
    return $scoring
}
