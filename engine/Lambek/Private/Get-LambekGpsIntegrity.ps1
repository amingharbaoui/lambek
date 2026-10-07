function Get-LambekGpsIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Evidence,

        # The action chosen, and what it can break
        [Parameter(Mandatory)]
        [string] $Winner,

        [ValidateSet('low', 'medium', 'high')]
        [string] $Risk = 'low'
    )

    # The fusion fitted on the benchmark (Optimize-LambekFusion); without it, nothing to say
    $fusion = Get-LambekFusion
    if (-not $fusion) { return $null }
    # Only an action the fusion was fitted on can be judged by it (a tool of an MCP server was never measured)
    if ($Winner -notin $fusion.Actions) { return $null }
    $names = [string[]] $fusion.Names
    $rows = @(Get-LambekSignalRow -Evidence $Evidence)
    $mine = @($rows | Where-Object Action -EQ $Winner)[0]
    if (-not $mine -or $rows.Count -eq 0) { return $null }
    $all = [bool[]] @($names | ForEach-Object { $true })

    # Missed-detection factor for each risk class: 10%, 1%, 0.1% (the precision approach of aviation for a deletion)
    $factor = @{ low = 1.2816; medium = 2.3263; high = 3.0902 }[$Risk]

    # Full solution: fused score of each action, margin of the winner over the best other one, and its sigma
    $margin = Get-LambekFusedMargin -Fusion $fusion -Rows $rows -Winner $Winner -Keep $all
    $sigma = [math]::Sqrt(2 * $fusion.Spread($fusion.Blue($all)))

    # Solution separation: leave each satellite out, then each family; a fault there would move the margin this much.
    # A reduction with exactly one reading is a proof: the structural satellites are only left out when the grammar
    # itself is unsure (no sentence, or several readings), as nothing else could see their fault
    $proven = $Evidence.PSObject.Properties['Grammar'] -and $Evidence.Grammar -and $Evidence.Grammar.IsSentence -and $Evidence.Grammar.PSObject.Properties['Readings'] -and $Evidence.Grammar.Readings -eq 1
    $structural = @('Grammar', 'Structure')
    $subsets = [System.Collections.Generic.List[object]]::new()
    for ($k = 0; $k -lt $names.Count; $k++) {
        if ($proven -and $names[$k] -in $structural) { continue }
        $keep = [bool[]] $all.Clone()
        $keep[$k] = $false
        $subsets.Add([pscustomobject]@{ Without = @($names[$k]); Keep = $keep })
    }
    foreach ($family in $fusion.Families) {
        if ($proven -and @($family | Where-Object { $_ -in $structural }).Count -gt 0) { continue }
        $keep = [bool[]] @($names | ForEach-Object { $_ -notin $family })
        $subsets.Add([pscustomobject]@{ Without = @($family); Keep = $keep })
    }
    $protection = $factor * $sigma
    $worst = $null
    $faults = [System.Collections.Generic.List[object]]::new()
    foreach ($subset in $subsets) {
        $weights = $fusion.Blue($subset.Keep)
        if (@($weights | Where-Object { $_ -ne 0 }).Count -eq 0) { continue }
        $without = Get-LambekFusedMargin -Fusion $fusion -Rows $rows -Winner $Winner -Keep $subset.Keep
        $level = [math]::Abs($margin.Margin - $without.Margin) + $factor * [math]::Sqrt(2 * $fusion.Spread($weights))
        if ($level -gt $protection) { $protection = $level; $worst = $subset.Without }
        if ($without.Best -ne $Winner) { $faults.Add([pscustomobject]@{ Without = @($subset.Without); Action = $without.Best }) }
    }

    # Chi-square on the residuals of the winner; calibrated probability; conformal set; Dempster-Shafer conflict
    $fused = $fusion.Fuse($mine.Values, $fusion.Weights)
    $chi = $fusion.ChiSquare($mine.Values, $fused)
    $probability = $fusion.Probability($fused)
    $set = @($rows | Where-Object { $fusion.Fuse($_.Values, $fusion.Weights) -ge $fusion.ConformalScore } | ForEach-Object Action)
    $conflict = Measure-LambekBeliefConflict -Rows $rows -Names $names

    # Chow's rule: propose when P >= 1 - (cost of asking / cost of a wrong proposal). A proposal is not a run: every change
    # is simulated and confirmed, a deletion with a typed code. And 184 requests cannot certify more than (n + 1) / (n + 2):
    # 0.999 would need about 3000. So 1/2 to read, 1/5 to change, 1/20 to delete
    $needed = @{ low = 0.5; medium = 0.8; high = 0.95 }[$Risk]

    # Available: the margin is above its protection level, the scorers agree with each other, and the probability is high enough
    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($margin.Margin -le $protection) { $reasons.Add('protection') }
    # The fuzzy scorers propose, the grammar disposes: when the sentence is proven (it reduces to s in exactly one way),
    # their disagreement or a low calibrated probability is only a warning; the protection level still has to hold
    $warnings = [System.Collections.Generic.List[string]]::new()
    $doubts = $reasons
    if ($proven) { $doubts = $warnings }
    if ($chi -gt $fusion.ChiSquareLimit) { $doubts.Add('chisquare') }
    if ($probability -lt $needed) { $doubts.Add('probability') }

    [pscustomobject]@{
        Winner      = $Winner
        Risk        = $Risk
        Fused       = [math]::Round($fused, 4)
        Margin      = [math]::Round($margin.Margin, 4)
        Sigma       = [math]::Round($sigma, 4)
        Protection  = [math]::Round($protection, 4)
        Worst       = @($worst)
        ChiSquare   = [math]::Round($chi, 3)
        Limit       = [math]::Round($fusion.ChiSquareLimit, 3)
        Probability = [math]::Round($probability, 4)
        Needed      = $needed
        Set         = @($set)
        Conflict    = [math]::Round($conflict, 4)
        Faults      = $faults.ToArray()
        Signals     = $names.Count
        Independent = [math]::Round($fusion.Independent($fusion.Weights), 2)
        Available   = $reasons.Count -eq 0
        Reasons     = $reasons.ToArray()
        Proven      = [bool] $proven
        Warnings    = $warnings.ToArray()
    }
}

function Get-LambekFusedMargin {
    param([LambekFusion] $Fusion, [object[]] $Rows, [string] $Winner, [bool[]] $Keep)

    # Fused scores with the satellites kept: the winner's lead over the best other action (negative when another wins)
    $weights = $Fusion.Blue($Keep)
    $scores = @($Rows | ForEach-Object { [pscustomobject]@{ Action = $_.Action; Score = $Fusion.Fuse($_.Values, $weights) } } | Sort-Object @{ Expression = 'Score'; Descending = $true }, Action)
    $mine = @($scores | Where-Object Action -EQ $Winner)[0].Score
    $other = @($scores | Where-Object Action -NE $Winner | Select-Object -First 1)
    $lead = 1.0
    if ($other.Count -gt 0) { $lead = $mine - $other[0].Score }
    return [pscustomobject]@{ Margin = $lead; Best = $scores[0].Action }
}

function Measure-LambekBeliefConflict {
    param([object[]] $Rows, [string[]] $Names)

    # Dempster-Shafer: the grammar and the words as two experts; their masses on each action, the rest on ignorance.
    # The mass they put on different actions (K) is the conflict; the rule itself is never used (Zadeh's paradox)
    $grammar = $Names.IndexOf('Grammar')
    $words = @('Cosine', 'WordJaccard', 'NGramJaccard', 'Edit' | ForEach-Object { $Names.IndexOf($_) } | Where-Object { $_ -ge 0 })
    $first = @{}
    $second = @{}
    $sumFirst = 1.0
    $sumSecond = 1.0
    foreach ($row in $Rows) {
        $first[$row.Action] = [math]::Max(0, $row.Values[$grammar])
        $lexical = 0.0
        foreach ($k in $words) { $lexical += $row.Values[$k] / $words.Count }
        $second[$row.Action] = [math]::Max(0, $lexical)
        $sumFirst += $first[$row.Action]
        $sumSecond += $second[$row.Action]
    }
    $conflict = 0.0
    foreach ($a in $first.Keys) {
        foreach ($b in $second.Keys) {
            if ($a -ne $b) { $conflict += ($first[$a] / $sumFirst) * ($second[$b] / $sumSecond) }
        }
    }
    return $conflict
}

function Get-LambekFusion {
    # Read once from the data folder of the module; the user's own drift (Kalman) is kept apart, in the data folder
    if ($null -ne $script:Fusion) { return $script:Fusion }
    $path = Join-Path $PSScriptRoot '../Data/fusion.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $fusion = [LambekFusion]::Load((Get-Content -LiteralPath $path -Raw))
    if (Test-Path -LiteralPath $script:DriftPath -PathType Leaf) {
        try {
            $drift = Get-Content -LiteralPath $script:DriftPath -Raw | ConvertFrom-Json
            if ((@($drift.Names) -join ',') -eq (@($fusion.Names) -join ',')) {
                $fusion.Drift = [double[]] @($drift.Drift)
                $fusion.DriftVariance = [double[]] @($drift.DriftVariance)
            }
        }
        catch { Write-Verbose "The drift of the scorers could not be read: $($_.Exception.Message)" }
    }
    $script:Fusion = $fusion
    return $fusion
}

function Get-LambekQuestionOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Evidence,

        [Parameter(Mandatory)]
        [object[]] $Ranked
    )

    # The actions to offer when Lambek asks: the two it hesitates between, and a third one only when it is worth
    # reading. Each action gets its calibrated probability, normalized over the candidates (q). Asking "A, B, or
    # something else?" gains IG = H(q) - r H(q | other), r the mass of the rest; a third option is added when it gains
    # at least 0.1 bit more. Shannon entropy in bits
    $ids = @($Ranked | ForEach-Object { $_.Action.Id } | Select-Object -Unique)
    $chosen = @($ids | Select-Object -First 2)
    $fusion = Get-LambekFusion
    if (-not $fusion -or $ids.Count -lt 3) { return [pscustomobject]@{ Actions = $chosen; Gain = $null } }
    $rows = @(Get-LambekSignalRow -Evidence $Evidence)
    $mass = [ordered]@{}
    foreach ($id in $ids) {
        $row = @($rows | Where-Object Action -EQ $id)[0]
        if (-not $row) { continue }
        $mass[$id] = [math]::Max(1e-6, $fusion.Probability($fusion.Fuse($row.Values, $fusion.Weights)))
    }
    $total = 0.0
    foreach ($value in $mass.Values) { $total += $value }
    if ($total -le 0 -or @($chosen | Where-Object { -not $mass.Contains($_) }).Count -gt 0) { return [pscustomobject]@{ Actions = $chosen; Gain = $null } }
    $q = [ordered]@{}
    foreach ($id in $mass.Keys) { $q[$id] = $mass[$id] / $total }

    $gain = Measure-LambekQuestionGain -Probability $q -Offered $chosen
    $third = @($q.Keys | Where-Object { $_ -notin $chosen } | Sort-Object { - $q[$_] }, { $_ } | Select-Object -First 1)
    if ($third.Count -gt 0) {
        $more = Measure-LambekQuestionGain -Probability $q -Offered (@($chosen) + $third)
        if ($more - $gain -ge 0.1) { $chosen = @($chosen) + $third; $gain = $more }
    }
    return [pscustomobject]@{ Actions = $chosen; Gain = [math]::Round($gain, 3) }
}

function Measure-LambekQuestionGain {
    param([System.Collections.IDictionary] $Probability, [string[]] $Offered)

    # H(q) minus what is left when the answer is "something else": r H(rest / r)
    $entropy = 0.0
    foreach ($p in $Probability.Values) { if ($p -gt 0) { $entropy -= $p * [math]::Log($p, 2) } }
    $rest = @($Probability.Keys | Where-Object { $_ -notin $Offered } | ForEach-Object { $Probability[$_] })
    $r = 0.0
    foreach ($p in $rest) { $r += $p }
    $left = 0.0
    if ($r -gt 0) { foreach ($p in $rest) { if ($p -gt 0) { $left -= ($p / $r) * [math]::Log($p / $r, 2) } } }
    return $entropy - $r * $left
}
