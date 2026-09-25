function ConvertTo-LambekAnswer {
    <#
    .SYNOPSIS
        Writes a short plain-language answer for a plan, its simulation, or its execution.
    .EXAMPLE
        New-LambekPlan 'delete the .log files in C:\Temp' | ConvertTo-LambekAnswer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Lambek.Plan')]
        [pscustomobject] $Plan,

        [PSTypeName('Lambek.Simulation')]
        [pscustomobject] $Simulation,

        [PSTypeName('Lambek.Execution')]
        [pscustomobject] $Execution
    )

    process {
        $language = 'en'
        if ($Plan.Steps.Count -gt 0) { $language = $Plan.Steps[0].Language }
        $answer = (Get-LambekLexicon -Language $language).Answer
        $lines = [System.Collections.Generic.List[string]]::new()

        # Questions first when the plan is not ready
        if ($Plan.Status -ne 'Ready') {
            foreach ($question in $Plan.Questions) {
                $lines.Add(($question -replace '^Step \d+: ', ''))
            }
            return ($lines | Select-Object -Unique) -join [Environment]::NewLine
        }

        # One sentence per step
        $sentences = foreach ($number in $Plan.Order) {
            $step = $Plan.Steps[$number - 1]
            $action = (Get-LambekAction -Id $step.Action).Action
            $template = @()
            if ($action.ContainsKey('Say')) {
                if ($action.Say.ContainsKey($language)) { $template = $action.Say[$language] }
                else { $template = $action.Say['en'] }
            }
            $sentence = ConvertTo-LambekSentence -Template $template -Parameters $step.Parameters -Units $answer.Units

            if ($Simulation) {
                $result = $Simulation.Steps | Where-Object Step -EQ $number
                if ($result -and $step.Output -ne 'code') {
                    $sentence += ' (' + ($answer.Affected -f $result.Count).TrimEnd('.') + ')'
                }
            }
            $sentence
        }

        if (@($sentences).Count -eq 1) {
            $lines.Add(($answer.Single -f @($sentences)[0]))
        }
        else {
            $lines.Add(($answer.Steps -f @($sentences).Count))
            $index = 1
            foreach ($sentence in $sentences) {
                $lines.Add("$index. $($sentence.Substring(0, 1).ToUpperInvariant())$($sentence.Substring(1)).")
                $index++
            }
        }

        # Confirmation code
        if ($Simulation -and $Simulation.ConfirmationCode -and -not $Execution) {
            $lines.Add(($answer.Approval -f $Simulation.ConfirmationCode))
        }

        # Result of the execution
        if ($Execution) {
            if ($Execution.Status -eq 'Completed') {
                $lines.Add($answer.Done)
                if (@($Plan.Steps | Where-Object Output -EQ 'code').Count -gt 0) {
                    $lines.Add($answer.Code)
                }
            }
            elseif ($Execution.Status -eq 'Refused') {
                $lines.Add(($answer.Refused -f $Execution.Reason))
            }
            else {
                $failed = $Execution.Steps | Where-Object Status -EQ 'Failed' | Select-Object -First 1
                $lines.Add(($answer.Failed -f $failed.Step, $failed.Error))
            }
        }

        return $lines -join [Environment]::NewLine
    }
}
