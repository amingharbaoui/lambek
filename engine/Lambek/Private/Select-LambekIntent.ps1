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

    # Threshold, then a margin that grows with what the action can break (read, change, delete)
    $status = 'Unknown'
    $best = $null
    $integrity = $null
    if ($ranked.Count -gt 0 -and $ranked[0].Score -ge $Scoring.Threshold) {
        $best = $ranked[0]
        $status = 'Found'
        $risk = $best.Action.Risk
        $margin = $Scoring.Margin
        if ($Scoring.PSObject.Properties['Margins'] -and $Scoring.Margins -and $Scoring.Margins.ContainsKey($risk)) { $margin = $Scoring.Margins[$risk] }
        if ($ranked.Count -gt 1 -and ($ranked[0].Score - $ranked[1].Score) -lt $margin) {
            $status = 'Ambiguous'
        }

        # Integrity: an action that changes things is not chosen on one signal alone.
        # When a scorer or a family of scorers would pick another action, ask between the two.
        $integrity = Get-LambekIntegrity -Evidence $Evidence -Scoring $Scoring
        $conflict = @($integrity.Faults | Where-Object { $_.Action -ne $best.Action.Id }) | Select-Object -First 1
        if ($status -eq 'Found' -and $risk -ne 'low' -and $conflict) {
            $status = 'Ambiguous'
            $other = @($ranked | Where-Object { $_.Action.Id -eq $conflict.Action })
            $rest = @($ranked | Where-Object { $_.Action.Id -ne $best.Action.Id -and $_.Action.Id -ne $conflict.Action })
            $ranked = @($best) + $other + $rest
        }
    }

    # GPS integrity of the choice: the fused margin against its protection level, the chi-square of the residuals,
    # the calibrated probability. What can only be undone from the trash, or not at all, is detection only:
    # when integrity is not available, Lambek asks. A read or a small change may exclude the faulty satellite and go on
    $gps = $null
    if ($best) {
        $gps = Get-LambekGpsIntegrity -Evidence $Evidence -Winner $best.Action.Id -Risk $best.Action.Risk
        if ($gps -and $integrity) { $integrity | Add-Member -NotePropertyName Gps -NotePropertyValue $gps -Force }
        if ($gps -and $status -eq 'Found' -and $best.Action.Risk -eq 'high' -and -not $gps.Available) {
            $status = 'Ambiguous'
            $fault = @($gps.Faults | Where-Object { $_.Action -ne $best.Action.Id }) | Select-Object -First 1
            if ($fault) {
                $other = @($ranked | Where-Object { $_.Action.Id -eq $fault.Action })
                $rest = @($ranked | Where-Object { $_.Action.Id -ne $best.Action.Id -and $_.Action.Id -ne $fault.Action })
                $ranked = @($best) + $other + $rest
            }
        }
    }

    # The conversation so far may settle a close call between two actions that only read or change little, never more
    if ($status -eq 'Ambiguous' -and $script:Belief -and $ranked.Count -gt 1 -and $ranked[0].Action.Risk -eq 'low' -and $ranked[1].Action.Risk -eq 'low') {
        $settled = Select-LambekByBelief -Ranked $ranked -Belief $script:Belief -Evidence $Evidence
        if ($settled) {
            $best = $settled
            $ranked = @($settled) + @($ranked | Where-Object { $_.Action.Id -ne $settled.Action.Id })
            $status = 'Found'
        }
    }

    return [pscustomobject]@{
        Status    = $status
        Best      = $best
        Ranked    = $ranked
        Integrity = $integrity
        Gps       = $gps
    }
}
