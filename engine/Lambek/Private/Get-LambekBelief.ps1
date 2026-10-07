function Get-LambekBelief {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # What the conversation believed before this turn: action -> probability
        [hashtable] $Belief,

        # The scores of this turn, one row per action (Get-LambekSignalRow)
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Rows,

        # Turns since the user last confirmed a plan
        [int] $Turns = 0
    )

    # A discrete Bayes filter (the forward step of an HMM), the analogue of Kalman for a state that is a category:
    # predict with a transition that mostly stays on the same action, then weigh by the calibrated likelihood of this turn.
    # A surprise (the turn's best action was nearly impossible before) is a new subject: the prior starts again.
    # Confidence fades with the turns since the last confirmation, like dead reckoning drifts
    $fusion = Get-LambekFusion
    $rows = @($Rows)
    if (-not $fusion -or $rows.Count -eq 0) { return $Belief }
    $actions = @($rows | ForEach-Object Action)
    $stay = 0.7 * [math]::Pow(0.8, [math]::Max(0, $Turns))
    $prior = @{}
    foreach ($action in $actions) {
        $before = 1.0 / $actions.Count
        if ($Belief -and $Belief.ContainsKey($action)) { $before = $Belief[$action] }
        $prior[$action] = $stay * $before + (1 - $stay) / $actions.Count
    }
    $likelihood = @{}
    foreach ($row in $rows) { $likelihood[$row.Action] = $fusion.Probability($fusion.Fuse($row.Values, $fusion.Weights, $true)) }

    # Innovation: the likeliest action of this turn had almost no prior belief
    $likeliest = @($likelihood.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Name | Select-Object -First 1)[0].Name
    if ($prior[$likeliest] -lt 0.05) { foreach ($action in $actions) { $prior[$action] = 1.0 / $actions.Count } }

    $posterior = @{}
    $total = 0.0
    foreach ($action in $actions) { $posterior[$action] = $prior[$action] * $likelihood[$action]; $total += $posterior[$action] }
    if ($total -le 0) { return $Belief }
    foreach ($action in $actions) { $posterior[$action] = $posterior[$action] / $total }
    return $posterior
}

function Select-LambekByBelief {
    param([object[]] $Ranked, [hashtable] $Belief, [pscustomobject] $Evidence)

    # Between the first two actions, the one the conversation makes nine times more likely than the other
    $first = $Ranked[0].Action.Id
    $second = $Ranked[1].Action.Id
    if (-not $Belief.ContainsKey($first) -or -not $Belief.ContainsKey($second)) { return $null }
    $fusion = Get-LambekFusion
    $rows = @(Get-LambekSignalRow -Evidence $Evidence)
    $weight = @{}
    foreach ($row in $rows) { $weight[$row.Action] = $fusion.Probability($fusion.Fuse($row.Values, $fusion.Weights, $true)) }
    $a = $Belief[$first] * $weight[$first]
    $b = $Belief[$second] * $weight[$second]
    if ($a -ge 9 * $b -and $a -gt 0) { return $Ranked[0] }
    if ($b -ge 9 * $a -and $b -gt 0) { return $Ranked[1] }
    return $null
}

function Add-LambekDrift {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Step
    )

    # Kalman on each scorer's bias, from a plan the user ran: the action that ran was the right one
    if ($script:Incognito -or -not $Step.PSObject.Properties['Reading'] -or -not $Step.Reading -or -not $Step.Reading.PSObject.Properties['Rows']) { return }
    $fusion = Get-LambekFusion
    $rows = @($Step.Reading.Rows)
    if (-not $fusion -or $rows.Count -eq 0) { return }
    $fusion.Observe([double[][]] @($rows | ForEach-Object { , [double[]] $_.Values }), [bool[]] @($rows | ForEach-Object { $_.Action -eq $Step.Action }), 0.0001)
    try {
        $folder = Split-Path -Path $script:DriftPath -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
        $data = [ordered]@{ Names = @($fusion.Names); Drift = @($fusion.Drift); DriftVariance = @($fusion.DriftVariance) }
        Set-Content -LiteralPath $script:DriftPath -Value ($data | ConvertTo-Json) -Encoding utf8NoBOM
    }
    catch { Write-Warning "The drift of the scorers could not be written: $($_.Exception.Message)" }
}
