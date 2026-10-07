function Get-LambekIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Evidence,

        [Parameter(Mandatory)]
        [pscustomobject] $Scoring
    )

    # GPS-style integrity: each scorer is a satellite. The choice is trusted when no single satellite,
    # and neither family of satellites (the grammar, the words), would have chosen another action alone.
    $weights = $Scoring.Weights
    $lexical = @('Cosine', 'WordJaccard', 'NGramJaccard', 'Edit')
    $full = @(Get-LambekRanking -Evidence $Evidence -Weights $weights -Without @())
    if ($full.Count -eq 0) {
        return [pscustomobject]@{ Winner = $null; Margin = 0.0; Faults = @(); Signals = 0; Independent = 0.0 }
    }
    $winner = $full[0]
    $margin = 1.0
    if ($full.Count -gt 1) { $margin = $full[0].Score - $full[1].Score }

    # Solution separation: leave out one scorer, then each family, and see who wins
    $faults = [System.Collections.Generic.List[object]]::new()
    # (leaving out the grammar is already leaving out the whole structural family)
    $subsets = @(@($weights.Keys | ForEach-Object { , @($_) })) + @(, $lexical)
    foreach ($without in $subsets) {
        $ranking = @(Get-LambekRanking -Evidence $Evidence -Weights $weights -Without $without)
        if ($ranking.Count -lt 2) { continue }
        $mine = @($ranking | Where-Object { $_.Id -eq $winner.Id })[0]
        $other = $ranking[0]
        # Only a strict preference for another action is a fault; a tie means this family cannot tell them apart
        if ($other.Id -ne $winner.Id -and $other.Score -gt $mine.Score + 0.000001) {
            $faults.Add([pscustomobject]@{ Without = @($without); Action = $other.Id })
        }
    }

    # Effective number of independent signals: (sum w)^2 / (w' R w), R the correlation measured on the benchmark
    $independent = [double] $weights.Count
    if ($Scoring.PSObject.Properties['Correlation'] -and $Scoring.Correlation) {
        $names = @($weights.Keys)
        $sum = 0.0
        $spread = 0.0
        foreach ($a in $names) {
            $sum += $weights[$a]
            foreach ($b in $names) { $spread += $weights[$a] * $weights[$b] * $Scoring.Correlation[$a][$b] }
        }
        if ($spread -gt 0) { $independent = $sum * $sum / $spread }
    }

    # The vote of each scorer: how much it prefers the winner to the best other action (negative: it preferred another)
    $votes = [ordered]@{}
    $fields = @{ Cosine = 'Cosine'; WordJaccard = 'WordJaccard'; NGramJaccard = 'NGramJaccard'; Edit = 'EditSimilarity' }
    $values = @{}
    foreach ($candidate in $Evidence.Candidates) {
        $best = $null
        $bestText = -1.0
        foreach ($example in $candidate.Examples) {
            $text = 0.0
            foreach ($name in $fields.Keys) { if ($weights.Contains($name)) { $text += $weights[$name] * $example.($fields[$name]) } }
            if ($text -gt $bestText) { $bestText = $text; $best = $example }
        }
        $row = @{ Grammar = [double] $candidate.GrammarScore }
        foreach ($name in $fields.Keys) { $row[$name] = 0.0; if ($best) { $row[$name] = [double] $best.($fields[$name]) } }
        $values[$candidate.Action.Id] = $row
    }
    foreach ($name in $weights.Keys) {
        $other = 0.0
        foreach ($id in $values.Keys) { if ($id -ne $winner.Id -and $values[$id][$name] -gt $other) { $other = $values[$id][$name] } }
        $votes[$name] = [math]::Round($values[$winner.Id][$name] - $other, 4)
    }

    return [pscustomobject]@{
        Winner      = $winner.Id
        Margin      = [math]::Round($margin, 4)
        Faults      = $faults.ToArray()
        Signals     = $weights.Count
        Independent = [math]::Round($independent, 2)
        Votes       = $votes
    }
}

function Get-LambekRanking {
    param(
        [pscustomobject] $Evidence,
        [System.Collections.IDictionary] $Weights,
        [string[]] $Without
    )

    # Weights without the left-out scorers, scaled back to a sum of 1
    $kept = @{}
    $total = 0.0
    foreach ($name in $Weights.Keys) {
        if ($name -in $Without) { continue }
        $kept[$name] = [double] $Weights[$name]
        $total += $kept[$name]
    }
    if ($total -le 0) { return @() }
    foreach ($name in @($kept.Keys)) { $kept[$name] = $kept[$name] / $total }

    $fields = @{ Cosine = 'Cosine'; WordJaccard = 'WordJaccard'; NGramJaccard = 'NGramJaccard'; Edit = 'EditSimilarity' }
    $scored = foreach ($candidate in $Evidence.Candidates) {
        $bestText = 0.0
        foreach ($example in $candidate.Examples) {
            $text = 0.0
            foreach ($name in $fields.Keys) {
                if ($kept.ContainsKey($name)) { $text += $kept[$name] * $example.($fields[$name]) }
            }
            if ($text -gt $bestText) { $bestText = $text }
        }
        $score = $bestText
        if ($kept.ContainsKey('Grammar')) { $score += $kept['Grammar'] * $candidate.GrammarScore }
        [pscustomobject]@{ Id = $candidate.Action.Id; Score = $score }
    }
    return @($scored | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Id' })
}
