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
        [pscustomobject] $Execution,

        # Language of the answer; by default the language of the request
        [string] $AnswerLanguage = '',

        # Only what the user must know or do: no restating of the request, no counts, no risk notes
        [switch] $Brief
    )

    process {
        $language = 'en'
        if ($Plan.Steps.Count -gt 0) { $language = $Plan.Steps[0].Language }
        if ($AnswerLanguage) { $language = $AnswerLanguage }
        $answer = (Get-LambekLexicon -Language $language).Answer
        $lines = [System.Collections.Generic.List[string]]::new()

        # Nothing to do: answer small talk, or say what Lambek can help with
        $understood = @($Plan.Steps | Where-Object { $_.Action })
        if ($understood.Count -eq 0) {
            $categories = @(Get-LambekCategory -Language $language)
            $titles = @($categories | ForEach-Object { $_.Title.ToLowerInvariant() })
            $topics = $titles -join ', '
            if ($titles.Count -gt 1) { $topics = ($titles[0..($titles.Count - 2)] -join ', ') + " $($answer.And) " + $titles[-1] }
            $example = "$(@($categories | ForEach-Object { $_.Examples } | Select-Object -First 1))"

            $reply = Get-LambekTalk -Text "$($Plan.Original)" -Language $language -Topics $topics -Example $example
            if (-not $reply) { $reply = $answer.Unknown -f $topics }
            return $reply
        }

        # Missing details or blocked plan
        if ($Plan.Status -ne 'Ready') {
            $questions = @($Plan.Questions | ForEach-Object { $_ -replace '^Steps? [\d, ]+: ', '' } | Select-Object -Unique)
            if ($Plan.Status -eq 'Invalid') {
                $lines.Add($answer.Stopped)
                foreach ($question in $questions) { $lines.Add($question) }
            }
            elseif ($questions.Count -eq 1) {
                $lines.Add(($answer.NeedOne -f $questions[0]))
            }
            else {
                $lines.Add($answer.NeedMany)
                foreach ($question in $questions) { $lines.Add("- $question") }
            }
            return $lines -join "`n"
        }

        # One sentence per step
        $sentences = foreach ($number in $Plan.Order) {
            $step = $Plan.Steps[$number - 1]
            $sentence = Get-LambekStepSentence -Step $step -Language $language -Units $answer.Units

            if ($Simulation -and $step.Output -notin 'code', 'mcp' -and $Plan.Steps.Count -gt 1) {
                $result = $Simulation.Steps | Where-Object Step -EQ $number
                if ($result) { $sentence += " ($($result.Count))" }
            }
            $sentence
        }

        if ($Brief) {
            # The request is not said back
        }
        elseif (@($sentences).Count -eq 1) {
            $lines.Add(($answer.Single -f @($sentences)[0]))
        }
        else {
            $lines.Add(($answer.Steps -f @($sentences).Count))
            $index = 1
            foreach ($sentence in $sentences) {
                $lines.Add("$index. $($sentence.Substring(0, 1).ToUpperInvariant())$($sentence.Substring(1)).")
                $index++
            }
            foreach ($edge in @($Plan.Edges | Select-Object -First 1)) {
                $lines.Add(($answer.Waits -f $edge.To, $edge.From, $edge.Reason))
            }
        }

        $onlyCode = @($Plan.Steps | Where-Object { $_.Output -ne 'code' }).Count -eq 0
        $mcpSteps = @($Plan.Steps | Where-Object { $_.Output -eq 'mcp' })
        $commandSteps = @($Plan.Steps | Where-Object { $_.Output -eq 'command' })

        # What happens next
        if ($Execution) {
            if ($Execution.Status -eq 'Completed') {
                if ($onlyCode) { $lines.Add($answer.DoneCode) }
                elseif ($Brief) {
                    # Rows speak for a reading step; a change is only said to be done
                    if (@($commandSteps | Where-Object { @($_.Writes).Count -gt 0 }).Count -gt 0) { $lines.Add($answer.DoneBrief) }
                }
                elseif ($commandSteps.Count -gt 0 -or $mcpSteps.Count -eq 0) {
                    $mcpNumbers = @($mcpSteps | ForEach-Object { $_.Step })
                    $count = ($Execution.Steps | Where-Object { $_.Step -notin $mcpNumbers } | Measure-Object -Property Count -Sum).Sum
                    $lines.Add(($answer.Done -f [int] $count))
                }
                # What each MCP server replied
                foreach ($step in $mcpSteps) {
                    $result = $Execution.Steps | Where-Object Step -EQ $step.Step
                    $server = (Get-LambekAction -Id $step.Action).Action.Mcp.Server
                    $reply = (@($result.Output) -join "`n").Trim()
                    if (-not $reply) { $lines.Add(($answer.McpEmpty -f $server)); continue }
                    if ($reply.Length -gt 1200) { $reply = $reply.Substring(0, 1200) + '...' }
                    $lines.Add(($answer.McpReply -f $server))
                    $lines.Add($reply)
                }
            }
            elseif ($Execution.Status -eq 'Refused') {
                $lines.Add(($answer.Refused -f $Execution.Reason))
            }
            else {
                $failed = $Execution.Steps | Where-Object Status -EQ 'Failed' | Select-Object -First 1
                $lines.Add(($answer.Failed -f $failed.Step, $failed.Error))
                $lines.Add($answer.AfterFail)
            }
        }
        elseif ($Simulation) {
            $count = ($Simulation.Steps | Measure-Object -Property Count -Sum).Sum
            $bytes = [long] ($Simulation.Steps | Measure-Object -Property Bytes -Sum).Sum

            # MCP calls are shown exactly as they will be sent
            foreach ($step in $mcpSteps) {
                $call = $step.Script | ConvertFrom-Json -AsHashtable
                $arguments = $answer.McpNoArguments
                if ($call.arguments.Count -gt 0) { $arguments = $call.arguments | ConvertTo-Json -Depth 10 -Compress }
                $lines.Add(($answer.McpCall -f $call.tool, $call.server, $arguments))
            }

            # Files that would be touched
            if ($commandSteps.Count -gt 0 -or $mcpSteps.Count -eq 0) {
                if ($count -eq 0) {
                    $lines.Add($answer.Nothing)
                }
                elseif ($Brief) {
                    # The files are listed with the stages, not counted here
                }
                elseif ($bytes -gt 0) {
                    $size = Format-LambekHumanValue -Name 'Size' -Value $bytes -Units $answer.Units
                    $lines.Add(($answer.Matches -f $count, $size))
                }
                else {
                    $lines.Add(($answer.MatchesCount -f $count))
                }
            }
            # Nothing to change: no confirmation to ask for
            if ($Simulation.ConfirmationCode -and ($count -gt 0 -or $mcpSteps.Count -gt 0)) { $lines.Add(($answer.Approval -f $Simulation.ConfirmationCode)) }
            elseif ($count -gt 0 -or $mcpSteps.Count -gt 0) { $lines.Add($answer.ReadyToRun) }
        }
        elseif ($Brief) {
            # A plan alone needs no words: its reading is in the status
        }
        elseif ($onlyCode) {
            $lines.Add($answer.CodeOnly)
        }
        elseif ($mcpSteps.Count -gt 0 -and $commandSteps.Count -eq 0) {
            $servers = @($mcpSteps | ForEach-Object { (Get-LambekAction -Id $_.Action).Action.Mcp.Server } | Select-Object -Unique) -join ', '
            $lines.Add(@{ low = $answer.McpLow; medium = $answer.McpMedium; high = $answer.McpHigh }[$Plan.Risk] -f $servers)
        }
        elseif ($Plan.Risk -eq 'low' -and @($commandSteps | Where-Object { $_.Writes.Count -gt 0 }).Count -gt 0) {
            $lines.Add($answer.RiskCreate)
        }
        else {
            $lines.Add(@{ low = $answer.RiskLow; medium = $answer.RiskMedium; high = $answer.RiskHigh }[$Plan.Risk])
        }

        return $lines -join "`n"
    }
}

function Get-LambekStepSentence {
    param(
        [pscustomobject] $Step,
        [string] $Language,
        [hashtable] $Units
    )

    $action = (Get-LambekAction -Id $Step.Action).Action
    $template = @()
    if ($action.ContainsKey('Say')) {
        if ($action.Say.ContainsKey($Language)) { $template = $action.Say[$Language] }
        else { $template = $action.Say['en'] }
    }
    return ConvertTo-LambekSentence -Template $template -Parameters $Step.Parameters -Units $Units
}
