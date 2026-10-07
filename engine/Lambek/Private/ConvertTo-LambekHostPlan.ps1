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

        # Every parameter of the action, so the app can show and edit them
        $schema = @()
        if ($step.Action) {
            $action = (Get-LambekAction -Id $step.Action).Action
            $schema = @(foreach ($parameter in $action.Parameters) {
                    $kind = 'text'
                    $choices = @()
                    if ($parameter.ContainsKey('Words')) {
                        $kind = 'choice'
                        $choices = @($parameter.Words.Values | Select-Object -Unique)
                    }
                    elseif (@($parameter.Entities) -contains 'size') { $kind = 'size' }
                    elseif (@($parameter.Entities) -contains 'duration') { $kind = 'duration' }

                    [ordered]@{
                        name     = $parameter.Name
                        kind     = $kind
                        choices  = $choices
                        required = ($parameter.ContainsKey('Required') -and $parameter.Required)
                    }
                })
        }

        $violations = @()
        if ($step.Check) {
            $violations = @($step.Check.Violations | ForEach-Object { [ordered]@{ rule = $_.Rule; line = $_.Line; text = $_.Text } })
        }

        $title = $null
        if ($step.Action) { $title = Get-LambekTitle -Action (Get-LambekAction -Id $step.Action).Action -Language $step.Language }

        # The GPS panel of the choice: signals, margin and its protection level, residuals, probability, and the verdict
        $integrity = $null
        $gps = $null
        if ($step.PSObject.Properties['Reading'] -and $step.Reading -and $step.Reading.Integrity -and $step.Reading.Integrity.PSObject.Properties['Gps']) { $gps = $step.Reading.Integrity.Gps }
        if ($gps) {
            $integrity = [ordered]@{
                signals = $gps.Signals; independent = $gps.Independent; margin = $gps.Margin; sigma = $gps.Sigma
                protection = $gps.Protection; chiSquare = $gps.ChiSquare; limit = $gps.Limit; probability = $gps.Probability
                needed = $gps.Needed; conflict = $gps.Conflict; available = $gps.Available; reasons = @($gps.Reasons)
            }
        }

        [ordered]@{
            step       = $step.Step
            title      = $title
            clause     = $step.Clause
            language   = $step.Language
            status     = $step.Status
            action     = $step.Action
            risk       = $step.Risk
            confidence = $step.Confidence
            types      = Format-LambekShownType -Step $step
            parameters = $human
            exact      = $exact
            schema     = $schema
            questions  = @($step.Questions)
            output     = $step.Output
            script     = $step.Script
            safe       = ($null -ne $step.Check -and $step.Check.IsValid)
            violations = $violations
            integrity  = $integrity
        }
    }

    return [ordered]@{
        id        = $Id
        status    = $Plan.Status
        risk      = $Plan.Risk
        answer    = ConvertTo-LambekAnswer -Plan $Plan -Brief
        sentences = @(foreach ($number in $Plan.Order) {
                $item = $Plan.Steps[$number - 1]
                if ($item.Action) { Get-LambekStepSentence -Step $item -Language $item.Language -Units (Get-LambekLexicon -Language $item.Language).Answer.Units }
            })
        questions = @($Plan.Questions)
        steps     = @($steps)
        edges     = @($Plan.Edges | ForEach-Object { [ordered]@{ from = $_.From; to = $_.To; reason = $_.Reason } })
        order     = @($Plan.Order)
        levels    = @($Plan.Levels | ForEach-Object { , @($_) })
        cycles    = @($Plan.Cycles | ForEach-Object { , @($_) })
        planHash  = $Plan.PlanHash
        trace     = @(Get-LambekTraceItem -Plan $Plan)
    }
}

function Get-LambekTraceItem {
    param([pscustomobject] $Plan)

    if (-not $Plan.PSObject.Properties['Trace']) { return }
    foreach ($item in $Plan.Trace) {
        [ordered]@{ stage = $item.Stage; step = $item.Step; detail = $item.Detail; ms = $item.Milliseconds }
    }
}
