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

    # The turn itself, then what the conversation is about now: the plan carries its referents to the next turn
    $turn = Resolve-LambekTurn -Plan $Plan -Text $Text -Step $Step
    if ($turn.Plan -and -not [object]::ReferenceEquals($turn.Plan, $Plan)) {
        $turn.Plan = Add-LambekConversation -Plan $turn.Plan -Previous $Plan
        # A request understood right after one that was not may be the same request said another way
        if ($turn.Kind -eq 'new') { Add-LambekRephrased -Plan $turn.Plan -Previous $Plan }
        # The words not understood before stay with the conversation: the plan that runs may say what they meant
        $unresolved = @(Get-LambekUnresolved -Plan $Plan)
        if ($unresolved.Count -gt 0 -and -not $turn.Plan.PSObject.Properties['Unresolved']) {
            $turn.Plan | Add-Member -NotePropertyName Unresolved -NotePropertyValue $unresolved
        }
    }
    return $turn
}

function Resolve-LambekTurn {
    param(
        [pscustomobject] $Plan,
        [string] $Text,
        [int] $Step
    )

    # "in python", "show me this in bash": the plan as a program in that language (it is shown, never run)
    $export = Resolve-LambekCodeRequest -Text $Text -Plan $Plan
    if ($export) { return $export }

    # A complete new command is always a new plan
    $fresh = New-LambekPlan -Text $Text
    $isNewCommand = $fresh.Status -eq 'Ready' -or @($fresh.Steps | Where-Object { $_.Action -and $_.Types -match '(^|\s)s(\s|$)' -and $_.Status -eq 'Ready' }).Count -gt 0
    if ($isNewCommand) {
        return [pscustomobject]@{ Kind = 'new'; Plan = $fresh; Answer = (ConvertTo-LambekAnswer -Plan $fresh) }
    }

    # Something told, or a question about what was told: it is answered, and the plan in progress stays as it is
    if (@($fresh.Steps | Where-Object { ($_.PSObject.Properties['Statement'] -and $_.Statement) -or ($_.PSObject.Properties['Asked'] -and $_.Asked) }).Count -gt 0) {
        return [pscustomobject]@{ Kind = 'explain'; Plan = $Plan; Answer = (ConvertTo-LambekAnswer -Plan $fresh) }
    }

    # "oui" to "did you mean ...?": the request suggested becomes the plan
    if ($Plan.PSObject.Properties['Suggestion'] -and $Plan.Suggestion) {
        # "yes" in any language: the question may have been asked in another one than the reply
        $yes = @(Get-LambekAvailableLanguage | ForEach-Object { $lexicon = Get-LambekLexicon -Language $_; $lexicon.FollowUp.Run; $lexicon.FollowUp.Filler })
        $words = @((ConvertTo-LambekNormalizedText -Text $Text) -split '[^\p{L}\p{N}]+' | Where-Object { $_ })
        if ($words.Count -gt 0 -and @($words | Where-Object { $_ -notin $yes }).Count -eq 0) {
            # A word the dictionary proposed is learned once the user said yes (a phrase is only used this time)
            $learned = ''
            if ($Plan.PSObject.Properties['Proposal'] -and $Plan.Proposal -and $Plan.Proposal.Word -notmatch '\s') {
                $proposal = $Plan.Proposal
                $language = @($Plan.Steps)[0].Language
                try {
                    Add-LambekWord -Word $proposal.Word -Meaning $proposal.To -Language $language | Out-Null
                    $learned = ((Get-LambekLexicon -Language $language).Answer.Learned -f $proposal.From, $proposal.To) + "`n"
                }
                catch { Write-Verbose "'$($proposal.Word)' could not be learned: $($_.Exception.Message)" }
            }
            $suggested = New-LambekPlan -Text $Plan.Suggestion
            return [pscustomobject]@{ Kind = 'new'; Plan = $suggested; Answer = "$learned$(ConvertTo-LambekAnswer -Plan $suggested)" }
        }
    }

    # A reply to "what does X mean?": the word it names is learned when its type is a solution of the equation,
    # then the request is read again with it
    $guessed = @($Plan.Steps | Where-Object { $_.PSObject.Properties['Guess'] -and $_.Guess -and $_.Status -ne 'Ready' })
    if ($guessed.Count -gt 0) {
        $guess = $guessed[0].Guess
        $reply = ConvertTo-LambekRequest -Text $Text -Language $guess.Language
        $grammarWords = (Get-LambekGrammarLexicon -Language $guess.Language).Words
        $meaning = @($reply.Words | Where-Object {
                $_ -ne $guess.Word -and $grammarWords.ContainsKey($_) -and @($grammarWords[$_] | Where-Object { $_ -in $guess.Types }).Count -gt 0
            }) | Select-Object -First 1
        if ($meaning) {
            foreach ($word in @($guess.Token, $guess.Word | Select-Object -Unique)) {
                Add-LambekWord -Word $word -Meaning $meaning -Language $guess.Language | Out-Null
            }
            $again = New-LambekPlan -Text $Plan.Original
            $said = $meaning
            if (@($reply.Tokens).Count -eq 1) { $said = $Text.Trim().Trim([char[]] '"''.!:; ') }
            $learned = (Get-LambekLexicon -Language $guess.Language).Answer.Learned -f $guess.Token, $said
            return [pscustomobject]@{ Kind = 'edit'; Plan = $again; Answer = "$learned`n$(ConvertTo-LambekAnswer -Plan $again)"; Learned = $guess.Token }
        }
    }

    # "delete them", "supprime-les": a new action on the files the plan was about (the referent of the pronoun)
    $said = ConvertTo-LambekRequest -Text $Text
    $pronouns = @((Get-LambekLexicon -Language $said.Language).FollowUp['Pronouns'])
    $referent = Select-LambekReferent -Plan $Plan -Tokens @($said.Tokens) -Language $said.Language
    $newStep = @($fresh.Steps | Where-Object Action | Select-Object -First 1)
    if ($referent -and $newStep.Count -eq 1 -and $fresh.Steps.Count -eq 1 -and $newStep[0].Status -ne 'Ready' -and @($said.Tokens | Where-Object { $_ -in $pronouns }).Count -gt 0) {
        $edited = New-LambekPlan -Text $Text -Referent $referent.Parameters
        return [pscustomobject]@{ Kind = 'new'; Plan = $edited; Answer = (ConvertTo-LambekAnswer -Plan $edited) }
    }

    # A reply to "which file exactly?": a name, an order ("the newest"), a count, or all of them ("toutes")
    if ($Plan.Steps.Count -eq 1 -and $Plan.Steps[0].Action -and $Plan.Steps[0].Status -eq 'NeedsInput') {
        $only = $Plan.Steps[0]
        $action = (Get-LambekAction -Id $only.Action).Action
        if ($action.ContainsKey('Which') -and @($only.Questions | Where-Object { $_ -in @($action.Which.Question.Values) }).Count -gt 0) {
            $reply = ConvertTo-LambekRequest -Text $Text
            $every = @($reply.Tokens | Where-Object { $_ -in @($action.Which.All) }).Count -gt 0
            $filled = Get-LambekParameter -Action $action -Request $reply -Grammar (Resolve-LambekGrammar -Request $reply)
            $picked = @($action.Which.By | Where-Object { $filled.Values.Contains($_) })
            if ($every -or $picked.Count -gt 0) {
                $values = [ordered]@{}
                foreach ($name in $picked) { $values[$name] = Format-LambekValue -Value $filled.Values[$name] }
                # The request named one file: "the newest" of "my image" is one image
                foreach ($parameter in $action.Parameters) {
                    if (-not $every -and $parameter.ContainsKey('Singular') -and $parameter.RequiredWith -in $picked -and -not $values.Contains($parameter.Name)) {
                        $values[$parameter.Name] = [string] $parameter.Singular
                    }
                }
                # All of them: the step as it is, now without the question
                if ($values.Count -eq 0) {
                    $first = @($only.Parameters.Keys)[0]
                    $values[$first] = Format-LambekValue -Value $only.Parameters[$first]
                }
                $edited = $Plan
                foreach ($name in $values.Keys) { $edited = Set-LambekPlanParameter -Plan $edited -Step 1 -Name $name -Value $values[$name] }
                $answer = (Get-LambekLexicon -Language $only.Language).Answer
                return [pscustomobject]@{ Kind = 'edit'; Plan = $edited; Answer = ($answer.Edited -f (ConvertTo-LambekAnswer -Plan $edited)) }
            }
        }
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

    # "How many are there?": the plan is simulated, nothing changes, and the count is the answer
    $normalizedText = " $((ConvertTo-LambekNormalizedText -Text $Text) -replace '[^\p{L}\p{N}]+', ' ') "
    $asksCount = @($lexicon.HowMany | Where-Object { $_ -and $normalizedText.Contains(" $_ ") }).Count -gt 0
    $ownVerbs = @($request.Words | Where-Object { (Get-LambekActionIndex -Language $request.Language).Known.Contains($_) -and (Test-LambekActionVerb -Word $_) })
    if ($asksCount -and $ownVerbs.Count -eq 0 -and $Plan.Status -eq 'Ready') {
        $simulation = Invoke-LambekPlan -Plan $Plan -Simulate
        $counted = @($simulation.Steps | Where-Object { $null -ne $_.Count } | Select-Object -Last 1)
        if ($counted.Count -gt 0) {
            return [pscustomobject]@{ Kind = 'explain'; Plan = $Plan; Answer = ($answer.Count -f $counted[0].Count) }
        }
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
        # A value asked for a word of the request ("old": older than what?)
        if (-not $name -and $pending.PSObject.Properties['Pending']) {
            $name = @($pending.Pending | Where-Object { -not $pending.Parameters.Contains($_) }) | Select-Object -First 1
        }
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

    # Values for the nodes of the plan: same action, new parameters.
    # A message without a verb of its own is a fragment of the plan ("and the videos?"): its words count too
    $candidates = @($Plan.Steps | Where-Object { $_.Action })
    if ($target) { $candidates = @($candidates | Where-Object Step -EQ $target) }
    $isFragment = $ownVerbs.Count -eq 0
    $adds = @($words | Where-Object { $_ -in @($followUp['Also']) }).Count -gt 0
    if ($candidates.Count -gt 0) {
        $grammar = Resolve-LambekGrammar -Request $request

        foreach ($candidate in @($candidates | Sort-Object Step -Descending)) {
            $action = (Get-LambekAction -Id $candidate.Action).Action
            $filled = Get-LambekParameter -Action $action -Request $request -Grammar $grammar
            $changes = @($filled.Values.Keys | Where-Object {
                    $old = $null
                    if ($candidate.Parameters.Contains($_)) { $old = Format-LambekValue -Value $candidate.Parameters[$_] }
                    $definition = $action.Parameters | Where-Object Name -EQ $_ | Select-Object -First 1
                    $old -ne (Format-LambekValue -Value $filled.Values[$_]) -and ($definition.ContainsKey('Entities') -or ($isFragment -and $definition.ContainsKey('Words')))
                })
            if ($changes.Count -eq 0) { continue }

            $edited = $Plan
            foreach ($name in $changes) {
                $value = $filled.Values[$name]
                # "the videos too": added to what the plan already keeps, when the parameter holds several values
                $definition = $action.Parameters | Where-Object Name -EQ $name | Select-Object -First 1
                if ($adds -and $definition['Many'] -and $candidate.Parameters.Contains($name)) {
                    $value = @(@($candidate.Parameters[$name]) + @($value) | Select-Object -Unique)
                }
                $edited = Set-LambekPlanParameter -Plan $edited -Step $candidate.Step -Name $name -Value (Format-LambekValue -Value $value)
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
        # A step still missing something is said as the user wrote it
        $sentence = $item.Clause
        if ($item.Status -eq 'Ready') { $sentence = Get-LambekStepSentence -Step $item -Language $Language -Units $answer.Units }
        $lines.Add(($answer.ExplainStep -f $item.Step, $sentence))
        foreach ($line in Get-LambekDerivation -Step $item -Language $Language) { $lines.Add($line) }
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

function Get-LambekDerivation {
    param([pscustomobject] $Step, [string] $Language)

    # The reading said in words, from what the engine kept: the verb, the words read another way,
    # the choice between actions and its margin, the meaning on the reduction, the logical form, the reading back
    $explain = (Get-LambekLexicon -Language $Language).Answer.Explain
    $decimal = (Get-LambekLexicon -Language $Language).Answer.Units['Decimal']
    if (-not $Step.PSObject.Properties['Reading'] -or -not $Step.Reading) { return }
    $reading = $Step.Reading

    # A verb taken from another language is said in the language of the sentence, and the borrowing is told
    $borrowed = @{}
    if ($reading.PSObject.Properties['Borrowed'] -and $reading.Borrowed) { $borrowed = $reading.Borrowed }
    if ($reading.Head) {
        $verb = $reading.Head.Word
        if ($borrowed.Contains($verb)) { $verb = ConvertTo-LambekMatrixWord -Word $verb -From $borrowed[$verb] -To $Language }
        Format-LambekPlural -Template $explain.Verb -Language $Language -Values @($verb, [int] $reading.Readings)
    }
    $names = (Get-LambekLexicon -Language $Language).Answer.LanguageNames
    foreach ($word in @($borrowed.Keys)) {
        $explain.Borrowed -f $word, $names[$borrowed[$word]], (ConvertTo-LambekMatrixWord -Word $word -From $borrowed[$word] -To $Language)
    }
    foreach ($correction in @($reading.Corrections)) {
        if ($correction.PSObject.Properties['Sense'] -and $correction.Sense) { continue }
        $explain.Spelling -f $correction.From, $correction.To
    }

    # The choice: the best action, the next one, and the margin between them
    $candidates = @($reading.Candidates)
    if ($candidates.Count -gt 0) {
        $first = Get-LambekTitle -Action (Get-LambekAction -Id $candidates[0].Action).Action -Language $Language
        if ($candidates.Count -gt 1) {
            $second = Get-LambekTitle -Action (Get-LambekAction -Id $candidates[1].Action).Action -Language $Language
            $margin = [math]::Round($candidates[0].Score - $candidates[1].Score, 2)
            $explain.Choice -f $first, $second, $margin.ToString([cultureinfo]::InvariantCulture).Replace('.', $decimal)
        }
        else { $explain.Only -f $first }
    }
    if ($reading.Integrity) {
        # The constellation of the GPS fusion when there is one (six satellites, weighed by BLUE), else the scoring
        $seen = $reading.Integrity
        if ($seen.PSObject.Properties['Gps'] -and $seen.Gps) { $seen = $seen.Gps }
        $independent = ([double] $seen.Independent).ToString([cultureinfo]::InvariantCulture).Replace('.', $decimal)
        if (@($seen.Faults).Count -eq 0) { $explain.Signals -f $seen.Signals, $independent }
        else { $explain.Disagree -f $seen.Signals, $independent }
    }

    # The GPS verdict: the fused margin against its protection level, the residuals, the calibrated probability
    if ($reading.Integrity -and $reading.Integrity.PSObject.Properties['Gps'] -and $reading.Integrity.Gps) {
        $gps = $reading.Integrity.Gps
        $number = { param($value) ([double] $value).ToString('0.##', [cultureinfo]::InvariantCulture).Replace('.', $decimal) }
        $verdict = $explain.Available
        if (-not $gps.Available) { $verdict = $explain.Unavailable -f (@($gps.Reasons | ForEach-Object { $explain.Reasons[$_] }) -join ', ') }
        $explain.Gps -f (& $number $gps.Margin), (& $number $gps.Protection), (& $number $gps.ChiSquare), (& $number $gps.Limit), (& $number $gps.Probability), (& $number $gps.Needed), $verdict
    }

    # DisCoCat: the actions the reduction itself allows
    if (@($reading.Meaning).Count -gt 0) {
        $titles = @($reading.Meaning | ForEach-Object { Get-LambekTitle -Action (Get-LambekAction -Id $_).Action -Language $Language })
        $explain.Meaning -f ($titles -join ', ')
    }
    $form = Get-LambekLogicalForm -Step $Step
    if ($form) { $explain.Form -f $form }

    # The sentence said back was read again by the same grammar
    if ($Step.Output -ne 'mcp' -and $Step.Status -eq 'Ready') {
        $units = (Get-LambekLexicon -Language $Language).Answer.Units
        $said = Get-LambekStepSentence -Step $Step -Language $Language -Units $units
        if ($said -notmatch '\)$') { $explain.ReadBack }
    }
}

function Test-LambekActionVerb {
    param([string] $Word)

    # A word that is the verb of some action of a pack
    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) { if ($Word -in $action.Verbs) { return $true } }
    }
    return $false
}
