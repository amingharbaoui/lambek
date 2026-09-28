function Resolve-LambekFollowUp {
    <#
    .SYNOPSIS
        Reads a message about an existing plan: edit its nodes, explain it, run it, or start a new plan.
    .EXAMPLE
        Resolve-LambekFollowUp -Plan $plan -Text 'use .tmp instead'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Lambek.Plan')]
        [pscustomobject] $Plan,

        [Parameter(Mandatory)]
        [ValidateLength(1, 4000)]
        [string] $Text,

        # The node selected in the app, used when the text names no step
        [ValidateRange(0, 1000)]
        [int] $Step = 0
    )

    # A complete new command is always a new plan
    $fresh = New-LambekPlan -Text $Text
    $isNewCommand = $fresh.Status -eq 'Ready' -or @($fresh.Steps | Where-Object { $_.Action -and $_.Types -match '(^|\s)s(\s|$)' -and $_.Status -eq 'Ready' }).Count -gt 0
    if ($isNewCommand) {
        return [pscustomobject]@{ Kind = 'new'; Plan = $fresh; Answer = (ConvertTo-LambekAnswer -Plan $fresh) }
    }

    # Follow-ups use the language of the plan
    $language = 'auto'
    $first = @($Plan.Steps | Where-Object Language | Select-Object -First 1)
    if ($first.Count -gt 0) { $language = $first[0].Language }
    $request = ConvertTo-LambekRequest -Text $Text -Language $language
    $lexicon = Get-LambekLexicon -Language $request.Language
    $words = @($request.Words)
    $followUp = $lexicon.FollowUp
    $answer = $lexicon.Answer

    # Step number: "step 2", "etape 2"
    $target = $null
    if ($Step -gt 0 -and $Step -le $Plan.Steps.Count) { $target = $Step }
    $numbers = @($request.Entities | Where-Object Type -EQ 'number' | ForEach-Object { [int] $_.Value })
    if (@($words | Where-Object { $_ -in $followUp.Step }).Count -gt 0 -and $numbers.Count -gt 0) {
        $target = $numbers[0]
    }

    # Only small words and command words: run or explain
    $meaningful = @($words | Where-Object {
            -not $lexicon.StopWords.Contains($_) -and $_ -notin $followUp.Filler -and $_ -notin $followUp.Step -and $_ -ne '_number_'
        })
    $runWords = @($meaningful | Where-Object { $_ -in $followUp.Run })
    $explainWords = @($meaningful | Where-Object { $_ -in $followUp.Explain })

    if ($runWords.Count -gt 0 -and $runWords.Count -eq $meaningful.Count -and $Plan.Status -eq 'Ready') {
        return [pscustomobject]@{ Kind = 'run'; Plan = $Plan; Answer = $null }
    }
    if ($explainWords.Count -gt 0) {
        $text = Get-LambekExplanation -Plan $Plan -Step $target -Language $request.Language
        return [pscustomobject]@{ Kind = 'explain'; Plan = $Plan; Answer = $text }
    }

    # A reply to the open question of a step: "exemple.txt", "a folder"
    $open = @($Plan.Steps | Where-Object { $_.Action -and $_.Status -eq 'NeedsInput' })
    if ($target) { $open = @($open | Where-Object Step -EQ $target) }
    if ($open.Count -gt 0) {
        $pending = $open[0]
        $action = (Get-LambekAction -Id $pending.Action).Action
        $name = Get-LambekOpenParameter -Action $action -Parameters $pending.Parameters -Language $request.Language
        if ($name) {
            $definition = $action.Parameters | Where-Object Name -EQ $name | Select-Object -First 1
            $filled = Get-LambekParameter -Action $action -Request $request -Grammar (Resolve-LambekGrammar -Request $request)
            $value = $null
            $accepted = @()
            if ($definition.ContainsKey('Entities')) { $accepted = @($definition.Entities) }
            $only = @($request.Entities)
            if ($filled.Values.Contains($name)) {
                $value = Format-LambekValue -Value $filled.Values[$name]
            }
            elseif ($only.Count -eq 1 -and $only[0].Type -in $accepted) {
                # The reply is just the value: a path, a name, a size
                $value = Format-LambekValue -Value $only[0].Value
            }
            elseif (-not $definition.ContainsKey('Words') -and (Test-LambekPlainValue -Text $Text)) {
                $value = $Text.Trim().Trim([char[]] '"''.!:; ')
                # A folder name like Downloads or Bureau becomes the folder of the user
                if ('path' -in $accepted) { $value = Expand-LambekPath -Text $value }
            }
            if ($value) {
                try {
                    $edited = Set-LambekPlanParameter -Plan $Plan -Step $pending.Step -Name $name -Value $value
                    return [pscustomobject]@{ Kind = 'edit'; Plan = $edited; Answer = ($answer.Edited -f (ConvertTo-LambekAnswer -Plan $edited)) }
                }
                catch {
                    Write-Verbose "The reply does not fit $($name): $($_.Exception.Message)"
                }
            }
        }
    }

    # Values for the nodes of the plan: same action, new parameters
    $candidates = @($Plan.Steps | Where-Object { $_.Action })
    if ($target) { $candidates = @($candidates | Where-Object Step -EQ $target) }
    if ($candidates.Count -gt 0) {
        $grammar = Resolve-LambekGrammar -Request $request

        foreach ($candidate in @($candidates | Sort-Object Step -Descending)) {
            $action = (Get-LambekAction -Id $candidate.Action).Action
            $filled = Get-LambekParameter -Action $action -Request $request -Grammar $grammar
            $changes = @($filled.Values.Keys | Where-Object {
                    $old = $null
                    if ($candidate.Parameters.Contains($_)) { $old = Format-LambekValue -Value $candidate.Parameters[$_] }
                    $old -ne (Format-LambekValue -Value $filled.Values[$_]) -and ($action.Parameters | Where-Object Name -EQ $_).ContainsKey('Entities')
                })
            if ($changes.Count -eq 0) { continue }

            $edited = $Plan
            foreach ($name in $changes) {
                $edited = Set-LambekPlanParameter -Plan $edited -Step $candidate.Step -Name $name -Value (Format-LambekValue -Value $filled.Values[$name])
            }
            $text = $answer.Edited -f (ConvertTo-LambekAnswer -Plan $edited)
            return [pscustomobject]@{ Kind = 'edit'; Plan = $edited; Answer = $text }
        }
    }

    # Nothing new understood: answer in the language of the plan unless the text says otherwise
    $answerLanguage = ''
    if (-not (Test-LambekLanguageSignal -Text $Text)) { $answerLanguage = $language }
    return [pscustomobject]@{ Kind = 'new'; Plan = $fresh; Answer = (ConvertTo-LambekAnswer -Plan $fresh -AnswerLanguage $answerLanguage) }
}

function Get-LambekOpenParameter {
    param(
        [hashtable] $Action,
        [System.Collections.IDictionary] $Parameters,
        [string] $Language
    )

    # A required parameter first, then the one value that completes a set
    $check = Get-LambekMissingParameter -Action $Action -Parameters $Parameters -Language $Language
    $required = @($check.Missing | Where-Object { $_ -ne 'RequireOneOf' })
    if ($required.Count -gt 0) { return $required[0] }
    if ($check.Missing -notcontains 'RequireOneOf') { return $null }

    foreach ($set in $Action.RequireOneOf.Sets) {
        $absent = @($set | Where-Object { -not $Parameters.Contains($_) })
        if ($absent.Count -eq 1 -and $set.Count -gt 1) { return $absent[0] }
    }
    return $null
}

function Test-LambekPlainValue {
    param([string] $Text)

    # A short name like "exemple" or "rapport final", not a question or a sentence in any language
    if ($Text.Contains('?')) { return $false }
    $parts = @((ConvertTo-LambekNormalizedText -Text $Text) -split '[^\p{L}\p{N}.\-_]+' | Where-Object { $_ })
    if ($parts.Count -eq 0 -or $parts.Count -gt 3) { return $false }
    foreach ($language in Get-LambekAvailableLanguage) {
        $lexicon = Get-LambekLexicon -Language $language
        foreach ($part in $parts) {
            if ($lexicon.StopWords.Contains($part) -or $lexicon.TalkWords.Contains($part)) { return $false }

            # An action word starts a new request: its type holds the sentence type s
            $word = $part
            if ($lexicon.BaseForms.ContainsKey($part)) { $word = $lexicon.BaseForms[$part] }
            foreach ($pack in $script:Packs.Values) {
                if (-not $pack.Words.ContainsKey($language) -or -not $pack.Words[$language].ContainsKey($word)) { continue }
                if (@($pack.Words[$language][$word]) -match '(^|\s)s(\s|$)') { return $false }
            }
        }
    }
    return $true
}

function Get-LambekExplanation {
    param(
        [pscustomobject] $Plan,
        [object] $Step,
        [string] $Language
    )

    $answer = (Get-LambekLexicon -Language $Language).Answer
    $lines = [System.Collections.Generic.List[string]]::new()
    $steps = @($Plan.Steps)
    if ($Step) { $steps = @($steps | Where-Object Step -EQ $Step) }

    foreach ($item in $steps) {
        if (-not $item.Action) {
            $lines.Add(($answer.ExplainStep -f $item.Step, $item.Clause))
            continue
        }
        $sentence = Get-LambekStepSentence -Step $item -Language $Language -Units $answer.Units
        $lines.Add(($answer.ExplainStep -f $item.Step, $sentence))
        $lines.Add(($answer.ExplainAction -f $item.Action, $item.Risk))

        $parameters = @($item.Parameters.Keys | ForEach-Object {
                "$_ $(Format-LambekHumanValue -Name $_ -Value $item.Parameters[$_] -Units $answer.Units)"
            })
        if ($parameters.Count -gt 0) { $lines.Add(($answer.ExplainParams -f ($parameters -join ', '))) }

        if ($item.Types) {
            if ($item.Status -eq 'Ready') { $lines.Add(($answer.ExplainGrammar -f $item.Types)) }
            else { $lines.Add(($answer.ExplainGrammarOpen -f $item.Types)) }
        }
        if ($item.Check -and $item.Output -eq 'mcp') {
            if ($item.Check.IsValid) { $lines.Add($answer.ExplainMcp) }
            else { $lines.Add(($answer.ExplainMcpBlocked -f (($item.Check.Violations | ForEach-Object Text) -join ' '))) }
        }
        elseif ($item.Check) {
            if ($item.Check.IsValid) { $lines.Add($answer.ExplainSafe) }
            else { $lines.Add(($answer.ExplainBlocked -f (($item.Check.Violations | ForEach-Object Rule | Select-Object -Unique) -join ', '))) }
        }
    }

    if (-not $Step -and $Plan.Steps.Count -gt 1) {
        $lines.Add(($answer.ExplainOrder -f ($Plan.Order -join ', ')))
    }
    return $lines -join "`n"
}
