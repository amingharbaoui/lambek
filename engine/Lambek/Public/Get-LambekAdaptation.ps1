function Get-LambekAdaptation {
    <#
    .SYNOPSIS
        Shows what Lambek learned from the plans you ran: how much it trusts each scorer now, and your habits.
    .EXAMPLE
        Get-LambekAdaptation
    #>
    [CmdletBinding()]
    param()

    $scoring = Get-LambekScoring
    $adapted = Get-LambekAdaptedScoring -Scoring $scoring
    $history = Get-LambekHistory

    # Habits: for each action and place the user gives, the value that has become usual
    $habits = foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            foreach ($parameter in $action.Parameters) {
                if (-not $parameter['Habit']) { continue }
                $value = Get-LambekHabit -ActionId $action.Id -Name $parameter.Name
                if ($value) { [pscustomobject]@{ Action = $action.Id; Parameter = $parameter.Name; Value = $value } }
            }
        }
    }

    $weights = $scoring.Weights
    $evidence = 0.0
    if ($adapted) { $weights = $adapted.Weights; $evidence = $adapted.Evidence }
    # The bias of each scorer as the user's runs corrected it (Kalman), next to the published one
    $drift = [ordered]@{}
    $fusion = Get-LambekFusion
    if ($fusion) { for ($k = 0; $k -lt $fusion.Names.Count; $k++) { $drift[$fusion.Names[$k]] = [math]::Round($fusion.Bias[$k] + $fusion.Drift[$k], 4) } }

    [pscustomobject]@{
        PlansRun       = $history.Count
        Bias           = $drift
        Evidence       = $evidence
        DefaultWeights = $scoring.Weights
        Weights        = $weights
        Habits         = @($habits)
        HistoryPath    = $script:HistoryPath
    }
}
