function Measure-LambekSignal {
    <#
    .SYNOPSIS
        Measures how the scorers of Lambek move together on the benchmark: their correlation, and how many independent signals they really are.
    .EXAMPLE
        Measure-LambekSignal -Path ./bench/requests.json -Split calibration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('all', 'calibration', 'test', 'hard')]
        [string] $Split = 'calibration'
    )

    $scoring = Get-LambekScoring
    $names = @($scoring.Weights.Keys)
    $fields = @{ Grammar = 'GrammarScore'; Cosine = 'Cosine'; WordJaccard = 'WordJaccard'; NGramJaccard = 'NGramJaccard'; Edit = 'EditSimilarity' }

    # One row per request and action: what each scorer says, with the best example of the action
    $rows = [System.Collections.Generic.List[double[]]]::new()
    foreach ($case in Get-LambekBenchmarkCase -Path $Path -Split $Split) {
        $evidence = Get-LambekIntentEvidence -Request (ConvertTo-LambekRequest -Text $case.Text)
        foreach ($candidate in $evidence.Candidates) {
            $best = $null
            $bestText = -1.0
            foreach ($example in $candidate.Examples) {
                $text = 0.0
                foreach ($name in $names) { if ($name -ne 'Grammar') { $text += $scoring.Weights[$name] * $example.($fields[$name]) } }
                if ($text -gt $bestText) { $bestText = $text; $best = $example }
            }
            $row = foreach ($name in $names) {
                if ($name -eq 'Grammar') { [double] $candidate.GrammarScore } else { [double] $best.($fields[$name]) }
            }
            $rows.Add([double[]] $row)
        }
    }

    # Pearson correlation of each pair of scorers
    $count = $rows.Count
    $mean = @{}
    $deviation = @{}
    for ($a = 0; $a -lt $names.Count; $a++) {
        $sum = 0.0
        foreach ($row in $rows) { $sum += $row[$a] }
        $mean[$names[$a]] = $sum / [math]::Max($count, 1)
        $square = 0.0
        foreach ($row in $rows) { $square += [math]::Pow($row[$a] - $mean[$names[$a]], 2) }
        $deviation[$names[$a]] = [math]::Sqrt($square / [math]::Max($count - 1, 1))
    }
    $correlation = [ordered]@{}
    for ($a = 0; $a -lt $names.Count; $a++) {
        $correlation[$names[$a]] = [ordered]@{}
        for ($b = 0; $b -lt $names.Count; $b++) {
            $product = 0.0
            foreach ($row in $rows) { $product += ($row[$a] - $mean[$names[$a]]) * ($row[$b] - $mean[$names[$b]]) }
            $scale = $deviation[$names[$a]] * $deviation[$names[$b]] * [math]::Max($count - 1, 1)
            $value = 0.0
            if ($scale -gt 0) { $value = $product / $scale }
            if ($a -eq $b) { $value = 1.0 }
            $correlation[$names[$a]][$names[$b]] = [math]::Round($value, 3)
        }
    }

    # Effective number of independent signals (Kish): (sum w)^2 / (w' R w)
    $sumWeights = 0.0
    $spread = 0.0
    foreach ($a in $names) {
        $sumWeights += $scoring.Weights[$a]
        foreach ($b in $names) { $spread += $scoring.Weights[$a] * $scoring.Weights[$b] * $correlation[$a][$b] }
    }

    [pscustomobject]@{
        Rows        = $count
        Signals     = $names.Count
        Independent = [math]::Round($sumWeights * $sumWeights / $spread, 2)
        Correlation = $correlation
    }
}
