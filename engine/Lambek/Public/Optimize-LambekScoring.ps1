function Optimize-LambekScoring {
    <#
    .SYNOPSIS
        Finds the scoring weights, threshold, and margin that make no wrong action and recognize the most requests (grid search on the calibration split).
    .EXAMPLE
        Optimize-LambekScoring -Path ./bench/requests.json -OutFile ./scoring.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [double[]] $GrammarWeight = @(0.30, 0.35, 0.40),

        [double[]] $CosineShare = @(0.3, 0.4, 0.5),

        [double[]] $Threshold = @(0.35, 0.40, 0.45, 0.50, 0.55),

        [double[]] $Margin = @(0.03, 0.05, 0.08),

        [string] $OutFile
    )

    # Evidence is computed once per case, only the weights change
    $cases = Get-LambekBenchmarkCase -Path $Path -Split 'calibration'
    $prepared = foreach ($case in $cases) {
        [pscustomobject]@{
            Case     = $case
            Evidence = Get-LambekIntentEvidence -Request (ConvertTo-LambekRequest -Text $case.Text)
            Cache    = @{}
        }
    }

    $best = $null
    $tried = 0

    # Grid search in a fixed order, so the result is always the same
    foreach ($grammar in $GrammarWeight) {
        foreach ($share in $CosineShare) {
            $text = 1.0 - $grammar
            $cosine = [math]::Round($text * $share, 4)
            $other = [math]::Round(($text - $cosine) / 3, 4)
            $edit = [math]::Round(1.0 - $grammar - $cosine - 2 * $other, 4)

            foreach ($limit in $Threshold) {
                foreach ($gap in $Margin) {
                    $tried++
                    $scoring = [pscustomobject]@{
                        Weights   = @{ Grammar = $grammar; Cosine = $cosine; WordJaccard = $other; NGramJaccard = $other; Edit = $edit }
                        Threshold = $limit
                        Margin    = $gap
                    }

                    $results = foreach ($item in $prepared) {
                        $card = New-LambekIntentCard -Evidence $item.Evidence -Scoring $scoring -ParameterCache $item.Cache
                        [pscustomobject]@{
                            Expected = $item.Case.Expected
                            Outcome  = Get-LambekBenchmarkOutcome -Expected $item.Case.Expected -Card $card
                        }
                    }
                    $metrics = Measure-LambekOutcome -Results @($results)

                    # Fewest wrong actions, then most correct, then the most cautious threshold and margin
                    $isBetter = $false
                    if ($null -eq $best) {
                        $isBetter = $true
                    }
                    elseif ($metrics.Wrong -ne $best.Metrics.Wrong) {
                        $isBetter = $metrics.Wrong -lt $best.Metrics.Wrong
                    }
                    elseif ($metrics.Correct -ne $best.Metrics.Correct) {
                        $isBetter = $metrics.Correct -gt $best.Metrics.Correct
                    }
                    elseif ($limit -ne $best.Scoring.Threshold) {
                        $isBetter = $limit -gt $best.Scoring.Threshold
                    }
                    else {
                        $isBetter = $gap -gt $best.Scoring.Margin
                    }

                    if ($isBetter) {
                        $best = [pscustomobject]@{ Scoring = $scoring; Metrics = $metrics }
                    }
                }
            }
        }
    }

    # Save in the format of Data/scoring.json
    if ($OutFile) {
        $json = [ordered]@{
            Weights   = [ordered]@{
                Grammar      = $best.Scoring.Weights.Grammar
                Cosine       = $best.Scoring.Weights.Cosine
                WordJaccard  = $best.Scoring.Weights.WordJaccard
                NGramJaccard = $best.Scoring.Weights.NGramJaccard
                Edit         = $best.Scoring.Weights.Edit
            }
            Threshold = $best.Scoring.Threshold
            Margin    = $best.Scoring.Margin
        }
        $json | ConvertTo-Json | Set-Content -LiteralPath $OutFile
    }

    [pscustomobject]@{
        PSTypeName = 'Lambek.Calibration'
        Tried      = $tried
        Scoring    = $best.Scoring
        Metrics    = $best.Metrics
    }
}
