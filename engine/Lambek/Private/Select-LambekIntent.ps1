function Select-LambekIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Evidence,

        [Parameter(Mandatory)]
        [pscustomobject] $Scoring
    )

    $weights = $Scoring.Weights

    # S = sum of weight x score, with the best example of each action
    $scored = foreach ($candidate in $Evidence.Candidates) {
        $bestText = 0.0
        foreach ($example in $candidate.Examples) {
            $text = $weights.Cosine * $example.Cosine
            $text += $weights.WordJaccard * $example.WordJaccard
            $text += $weights.NGramJaccard * $example.NGramJaccard
            $text += $weights.Edit * $example.EditSimilarity
            if ($text -gt $bestText) { $bestText = $text }
        }

        [pscustomobject]@{
            Action  = $candidate.Action
            Pack    = $candidate.Pack.Name
            Score   = $weights.Grammar * $candidate.GrammarScore + $bestText
            Grammar = $candidate.GrammarScore
            Text    = $bestText
        }
    }

    $ranked = @($scored | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = { $_.Action.Id } })

    # Threshold and ambiguity margin
    $status = 'Unknown'
    $best = $null
    if ($ranked.Count -gt 0 -and $ranked[0].Score -ge $Scoring.Threshold) {
        $best = $ranked[0]
        $status = 'Found'
        if ($ranked.Count -gt 1 -and ($ranked[0].Score - $ranked[1].Score) -lt $Scoring.Margin) {
            $status = 'Ambiguous'
        }
    }

    return [pscustomobject]@{
        Status = $status
        Best   = $best
        Ranked = $ranked
    }
}
