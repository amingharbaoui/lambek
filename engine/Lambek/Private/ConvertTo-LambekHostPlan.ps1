function ConvertTo-LambekHostPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Id,

        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    $steps = foreach ($step in $Plan.Steps) {
        # Parameters in human and exact form
        $units = (Get-LambekLexicon -Language $step.Language).Answer.Units
        $human = [ordered]@{}
        $exact = [ordered]@{}
        foreach ($name in $step.Parameters.Keys) {
            $human[$name] = Format-LambekHumanValue -Name $name -Value $step.Parameters[$name] -Units $units
            $exact[$name] = Format-LambekValue -Value $step.Parameters[$name]
        }

        $violations = @()
        if ($step.Check) {
            $violations = @($step.Check.Violations | ForEach-Object { [ordered]@{ rule = $_.Rule; line = $_.Line; text = $_.Text } })
        }

        [ordered]@{
            step       = $step.Step
            clause     = $step.Clause
            language   = $step.Language
            status     = $step.Status
            action     = $step.Action
            risk       = $step.Risk
            confidence = $step.Confidence
            types      = $step.Types
            parameters = $human
            exact      = $exact
            output     = $step.Output
            script     = $step.Script
            safe       = ($null -ne $step.Check -and $step.Check.IsValid)
            violations = $violations
        }
    }

    return [ordered]@{
        id        = $Id
        status    = $Plan.Status
        risk      = $Plan.Risk
        answer    = ConvertTo-LambekAnswer -Plan $Plan
        questions = @($Plan.Questions)
        steps     = @($steps)
        edges     = @($Plan.Edges | ForEach-Object { [ordered]@{ from = $_.From; to = $_.To; reason = $_.Reason } })
        order     = @($Plan.Order)
        levels    = @($Plan.Levels | ForEach-Object { , @($_) })
        cycles    = @($Plan.Cycles | ForEach-Object { , @($_) })
        planHash  = $Plan.PlanHash
    }
}
