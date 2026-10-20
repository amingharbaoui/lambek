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
        [switch] $Brief,

        # Tu or vous: by default the one the user's own words use, else vous
        [ValidateSet('', 'vous', 'tu')]
        [string] $Register = ''
    )

    process {
        $language = 'en'
        if ($Plan.Steps.Count -gt 0) { $language = $Plan.Steps[0].Language }
        if ($AnswerLanguage) { $language = $AnswerLanguage }
        $answer = (Get-LambekLexicon -Language $language).Answer
        $lines = [System.Collections.Generic.List[string]]::new()
        # Lines said as they came (a server's reply), never changed by the rules of the language
        $raw = [System.Collections.Generic.HashSet[int]]::new()
        if (-not $Register) { $Register = Get-LambekRegister -Text "$($Plan.Original)" -Language $language }
        if (-not $Register) { $Register = 'vous' }
        # What the memory gave: "like on 12 March: ..." or that nothing was remembered
        if (-not $Simulation -and -not $Execution -and $Plan.PSObject.Properties['Remark'] -and $Plan.Remark) { $lines.Add($Plan.Remark) }

        # Nothing to do: answer small talk, or say what Lambek can help with (a word to explain is something to do)
        $understood = @($Plan.Steps | Where-Object { $_.Action -or ($_.PSObject.Properties['Guess'] -and $_.Guess) })
        if ($understood.Count -eq 0) {
            $categories = @(Get-LambekCategory -Language $language)
            $titles = @($categories | ForEach-Object { $_.Title.ToLowerInvariant() })
            $topics = $titles -join ', '
            if ($titles.Count -gt 1) { $topics = ($titles[0..($titles.Count - 2)] -join ', ') + " $($answer.And) " + $titles[-1] }
            $example = "$(@($categories | ForEach-Object { $_.Examples } | Select-Object -First 1))"

            $reply = $null
            # (a reply in words, as an answer from what was told, is said in the register of the user; a calculation is kept as it is)
            if ($Plan.PSObject.Properties['Reply'] -and $Plan.Reply) { $reply = $Plan.Reply; if (-not ($Plan.PSObject.Properties['Spoken'] -and $Plan.Spoken)) { [void] $raw.Add($lines.Count) } }
            if (-not $reply) { $reply = Get-LambekTalk -Text "$($Plan.Original)" -Language $language -Topics $topics -Example $example -Vary }
            # What the router of acts knows of what nothing was read in: a story asked, an order for elsewhere, how the user feels
            if (-not $reply -and $Plan.PSObject.Properties['RouteReply'] -and $Plan.RouteReply -and $answer[$Plan.RouteReply]) { $reply = $answer[$Plan.RouteReply] -f $topics }
            # What the user told or asked, without asking for anything: Lambek says how it read it
            if (-not $reply) {
                $told = @($Plan.Steps | Where-Object { $_.PSObject.Properties['Act'] -and $_.Act -and $_.Act -ne 'Order' }) | Select-Object -First 1
                $said = (Get-LambekLexicon -Language $language).Dialogue
                if ($told -and $said -and $said.Say[$told.Act]) { $reply = $said.Say[$told.Act] }
                # What Lambek has to say about this very sentence ("who is she?") comes first
                if ($told -and $told.PSObject.Properties['ActSay'] -and $told.ActSay) { $reply = $told.ActSay }
                # A sentence whose meaning was read is said back: who, what, when
                if ($told -and $told.PSObject.Properties['Statement'] -and $told.Statement -and $said -and $said.Say['Told']) {
                    # Every thing told in the message, one sentence each
                    $facts = @($Plan.Steps | Where-Object { $_.PSObject.Properties['Statement'] -and $_.Statement } | ForEach-Object { $_.Statement })
                    # About files or code, it is said that nothing is done ("yesterday I deleted..." is no order);
                    # about anything else ("my sister lives in Lyon") there was nothing to do: it is simply noted
                    $shape = 'Told'
                    if (@($facts | Where-Object { -not "$($_.Action)".StartsWith('verb:') }).Count -eq 0 -and $said.Say['Noted']) { $shape = 'Noted' }
                    # In an incognito chat it is kept for the conversation only
                    if ($script:Incognito) { $shape += 'Here' }
                    $reply = $said.Say[$shape] -f ((@($facts | ForEach-Object { Format-LambekFact -Fact $_ -Language $language -Register $Register })) -join ' ')
                    # Told the opposite before: both are kept, and it is said
                    $everything = @((Get-LambekTold).ToArray()) + @((Get-LambekToldJournal).ToArray())
                    foreach ($fact in $facts) {
                        foreach ($other in @(Get-LambekContrary -Fact $fact -Facts $everything)) {
                            $reply += "`n" + ($said.Say['Opposite'] -f (Format-LambekFact -Fact $other -Language $language -Register $Register))
                        }
                    }
                }
                # A question about what was told is answered from the conversation, and only from it
                if ($told -and $told.PSObject.Properties['Asked'] -and $told.Asked -and $said -and $said.Say['Recalled']) {
                    $reply = Get-LambekToldAnswer -Asked $told.Asked -Language $language -Register $Register
                }
            }
            if (-not $reply -and $Plan.PSObject.Properties['Suggestion'] -and $Plan.Suggestion) { $reply = $answer.DidYouMean -f $Plan.Suggestion }
            if (-not $reply) { $reply = $answer.Unknown -f $topics }
            $lines.Add($reply)
            return Complete-LambekAnswer -Lines $lines -Raw $raw -Language $language -Register $Register
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
            return Complete-LambekAnswer -Lines $lines -Raw $raw -Language $language -Register $Register
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
            # A value taken from the user's habits is said, so it can be changed
            $step = @($Plan.Steps)[0]
            if ($step.PSObject.Properties['FromHabit']) {
                foreach ($name in $step.FromHabit) { $lines.Add(($answer.Habit -f (Format-LambekHumanValue -Name $name -Value $step.Parameters[$name] -Units $answer.Units))) }
            }
            # How the action goes about it, when the pack says ("the largest files go first")
            $only = (Get-LambekAction -Id @($Plan.Steps)[0].Action).Action
            foreach ($note in Get-LambekActionNote -Action $only -Parameters @($Plan.Steps)[0].Parameters -Language $language) { $lines.Add($note) }
        }
        else {
            # A compound task says what it breaks down into
            if ($Plan.PSObject.Properties['Method'] -and $Plan.Method) { $lines.Add(($answer.Method -f $Plan.Method.Word, @($sentences).Count)) }
            else { $lines.Add(($answer.Steps -f @($sentences).Count)) }
            $index = 1
            foreach ($sentence in $sentences) {
                $lines.Add("$index. $($sentence.Substring(0, 1).ToUpperInvariant())$($sentence.Substring(1)).")
                $index++
            }
            foreach ($edge in @($Plan.Edges | Select-Object -First 1)) {
                $lines.Add(($answer.Waits -f $edge.To, $edge.From, $edge.Reason))
            }
        }

        # A word read from what it looks like is said, so a wrong reading can be seen before anything runs
        foreach ($step in $Plan.Steps) {
            if (-not $step.PSObject.Properties['Senses']) { continue }
            foreach ($sense in $step.Senses) {
                if ($sense.Sense -ne 'dictionary') { $lines.Add(($answer.Understood -f $sense.From, $sense.To)); continue }
                # A word of the dictionary: how it leads to the known word (synonym, a way to, narrower, close)
                $relation = 'near'
                if ($sense.Relation -in 'form', 'synonym', 'hyper', 'hypo') { $relation = $sense.Relation }
                $lines.Add(($answer.Dictionary[$relation] -f $sense.From, $sense.To))
            }
        }

        # A vague word read with a threshold says the threshold ("gros": more than 50 MB)
        foreach ($step in $Plan.Steps) {
            if ($step.PSObject.Properties['Vague'] -and $step.Vague -and -not $step.Vague.Core) { $lines.Add(($answer.VagueNote -f $step.Vague.Word, $step.Vague.Shown)) }
        }

        $onlyCode = @($Plan.Steps | Where-Object { $_.Output -ne 'code' }).Count -eq 0
        $mcpSteps = @($Plan.Steps | Where-Object { $_.Output -eq 'mcp' })
        $commandSteps = @($Plan.Steps | Where-Object { $_.Output -eq 'command' })

        # What happens next
        if ($Execution) {
            if ($Execution.Status -eq 'Completed') {
                # What each step did, in numbers: "I deleted 3 files (1.2 GB)."
                $reports = @(foreach ($result in $Execution.Steps) {
                        if (-not $result.PSObject.Properties['Summary'] -or -not $result.Summary) { continue }
                        $done = $Plan.Steps[$result.Step - 1]
                        # Rows speak for a reading step in a brief answer
                        if ($Brief -and -not @($done.Writes).Count) { continue }
                        Get-LambekReport -Step $done -Summary $result.Summary -Language $language -Short:$Brief
                    })
                if ($onlyCode) { $lines.Add($answer.DoneCode) }
                elseif ($reports.Count -gt 0) {
                    if ($Brief) { $lines.Add($answer.DoneBrief) }
                    foreach ($report in $reports) { $lines.Add($report) }
                }
                elseif ($Brief) {
                    # Rows speak for a reading step; a change is only said to be done
                    if (@($commandSteps | Where-Object { @($_.Writes).Count -gt 0 }).Count -gt 0) { $lines.Add($answer.DoneBrief) }
                }
                elseif ($commandSteps.Count -gt 0 -or $mcpSteps.Count -eq 0) {
                    $mcpNumbers = @($mcpSteps | ForEach-Object { $_.Step })
                    $count = ($Execution.Steps | Where-Object { $_.Step -notin $mcpNumbers } | Measure-Object -Property Count -Sum).Sum
                    $lines.Add((Format-LambekPlural -Template $answer.Done -Language $language -Values @([int] $count)))
                }
                # The check after the run: only said when something did not change as planned
                $unverified = @($Execution.Steps | ForEach-Object { if ($_.PSObject.Properties['Unverified']) { $_.Unverified } })
                if ($unverified.Count -gt 0) { $lines.Add((Format-LambekPlural -Template $answer.Unverified -Language $language -Values @($unverified.Count))) }
                # Words understood from a rephrasing, learned while the plan ran
                if ($Execution.PSObject.Properties['Learned']) {
                    foreach ($word in $Execution.Learned) { $lines.Add(($answer.LearnedSeen -f $word.Word, $word.Meaning)) }
                }

                # What each MCP server replied
                foreach ($step in $mcpSteps) {
                    $result = $Execution.Steps | Where-Object Step -EQ $step.Step
                    $server = (Get-LambekAction -Id $step.Action).Action.Mcp.Server
                    $reply = (@($result.Output) -join "`n").Trim()
                    if (-not $reply) { $lines.Add(($answer.McpEmpty -f $server)); continue }
                    if ($reply.Length -gt 1200) { $reply = $reply.Substring(0, 1200) + '...' }
                    $lines.Add(($answer.McpReply -f $server))
                    [void] $raw.Add($lines.Count)
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
                    $lines.Add((Format-LambekPlural -Template $answer.Matches -Language $language -Values @($count, $size)))
                }
                else {
                    $lines.Add((Format-LambekPlural -Template $answer.MatchesCount -Language $language -Values @($count)))
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
            # A change that can be undone is not said to be final ("delete" puts the files in Lambek's trash)
            $risk = @{ low = $answer.RiskLow; medium = $answer.RiskMedium; high = $answer.RiskHigh }[$Plan.Risk]
            $final = @($commandSteps | Where-Object {
                    $action = (Get-LambekAction -Id $_.Action).Action
                    $_.Risk -eq 'high' -and -not ($action.ContainsKey('Reversible') -and (Test-LambekCondition -Condition $action.Reversible -Parameters $_.Parameters))
                })
            if ($Plan.Risk -eq 'high' -and $final.Count -eq 0) { $risk = $answer.RiskUndo }
            $lines.Add($risk)
        }

        return Complete-LambekAnswer -Lines $lines -Raw $raw -Language $language -Register $Register
    }
}

function Complete-LambekAnswer {
    param(
        [System.Collections.Generic.List[string]] $Lines,
        [System.Collections.Generic.HashSet[int]] $Raw,
        [string] $Language,
        [string] $Register
    )

    # Every line Lambek wrote follows the rules of its language, in the user's register
    $spoken = for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Raw.Contains($i)) { $Lines[$i]; continue }
        ConvertTo-LambekSpoken -Text $Lines[$i] -Language $Language -Register $Register
    }
    return @($spoken) -join "`n"
}

function Get-LambekStepSentence {
    param(
        [pscustomobject] $Step,
        [string] $Language,
        [hashtable] $Units,

        # Say it without reading it back (the reading back itself uses this)
        [switch] $Unchecked
    )

    $action = (Get-LambekAction -Id $Step.Action).Action
    $template = @()
    if ($action.ContainsKey('Say')) {
        if ($action.Say.ContainsKey($Language)) { $template = $action.Say[$Language] }
        else { $template = $action.Say['en'] }
    }

    # The values that are words of the pack are said in the language of the answer ("Class": "classe")
    $values = [ordered]@{}
    foreach ($name in $Step.Parameters.Keys) {
        $value = $Step.Parameters[$name]
        # A kind the language has its own words for ("temporary": "fichiers temporaires") is said with them
        if ($value -is [string] -and $Units.ContainsKey($value)) { $values[$name] = $value; continue }
        $values[$name] = ConvertTo-LambekLocalValue -Action $action -Name $name -Value $value -Language $Language
    }
    $plain = @($action.Parameters | Where-Object { $_.ContainsKey('Words') } | ForEach-Object { $_.Name })

    # The sentence must say the plan: it is read back with the same grammar, and kept when it gives the same action
    # and the same values. Names and places go between quotes when needed. A value the sentence does not give back
    # is said as it is, after the sentence; when even the action differs, the whole plan is said as it is
    $best = $null
    foreach ($quote in 'None', 'Needed', 'All') {
        $sentence = ConvertTo-LambekSentence -Template $template -Parameters $values -Units $Units -Quote $quote -Plain $plain
        $sentence = ConvertTo-LambekSpoken -Text $sentence -Language $Language
        if ($Unchecked -or $Step.Output -eq 'mcp') { return $sentence }
        $differ = Test-LambekRoundTrip -Step $Step -Sentence $sentence -Language $Language
        if ($null -eq $differ) { continue }
        if (@($differ).Count -eq 0) { return $sentence }
        if (-not $best -or @($differ).Count -lt @($best.Differ).Count) { $best = [pscustomobject]@{ Sentence = $sentence; Differ = @($differ) } }
    }
    if (-not $best) {
        Write-Verbose "Read back, the sentence does not give the action: the plan is said as it is."
        return Format-LambekLiteralStep -Step $Step -Action $action -Language $Language -Units $Units
    }
    $exact = foreach ($name in $best.Differ) {
        if ($Step.Parameters.Contains($name)) { "$name = $(Format-LambekHumanValue -Name $name -Value $Step.Parameters[$name] -Units $Units)" }
        else { "$name = -" }
    }
    return "$($best.Sentence) ($($exact -join ', '))"
}

function ConvertTo-LambekLocalValue {
    param([hashtable] $Action, [string] $Name, [object] $Value, [string] $Language)

    # A value named by the words of a parameter: the first of its words that belongs to this language
    $parameter = @($Action.Parameters | Where-Object { $_.Name -eq $Name })[0]
    if (-not $parameter -or -not $parameter.ContainsKey('Words') -or $Value -isnot [string]) { return $Value }
    $pack = $null
    foreach ($candidate in $script:Packs.Values) { if (@($candidate.Actions | Where-Object { $_.Id -eq $Action.Id }).Count -gt 0) { $pack = $candidate } }
    # A value that is already a word of this language stays as it is
    if ($pack -and $pack.Words.ContainsKey($Language) -and $pack.Words[$Language].ContainsKey($Value.ToLowerInvariant())) { return $Value }
    foreach ($word in @($parameter.Words.Keys | Sort-Object)) {
        if ($parameter.Words[$word] -cne $Value) { continue }
        if ($pack -and $pack.Words.ContainsKey($Language) -and $pack.Words[$Language].ContainsKey($word)) {
            # The word as the pack writes it, unless it is only the value in lower case
            if ($word -ne $Value.ToLowerInvariant()) { return $word }
        }
    }
    return $Value
}

function Test-LambekRoundTrip {
    param([pscustomobject] $Step, [string] $Sentence, [string] $Language)

    # The names of the values the sentence does not give back (none: it says the plan), or nothing when the action differs.
    # Read back once for each sentence and plan
    $key = "$Language|$($Step.Action)|$(Get-LambekStepValueKey -Parameters $Step.Parameters)|$Sentence"
    if ($script:RoundTripCache.ContainsKey($key)) { return , $script:RoundTripCache[$key] }

    $differ = $null
    $handler = $script:ProgressHandler
    try {
        $script:ProgressHandler = $null
        $card = ConvertTo-LambekRequest -Text $Sentence -Language $Language | Resolve-LambekIntent
        if ($card.Action -eq $Step.Action) {
            # Values the user did not say (a habit, what was implied) are not in the sentence either
            $skip = @()
            if ($Step.PSObject.Properties['FromHabit']) { $skip += @($Step.FromHabit) }
            if ($Step.PSObject.Properties['Implied']) { $skip += @($Step.Implied) }
            $names = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($name in @($Step.Parameters.Keys) + @($card.Parameters.Keys)) { if ($name -notin $skip) { [void] $names.Add($name) } }
            $differ = [string[]] @(foreach ($name in $names) {
                    $mine = if ($Step.Parameters.Contains($name)) { Format-LambekValue -Value $Step.Parameters[$name] } else { $null }
                    $theirs = if ($card.Parameters.Contains($name)) { Format-LambekValue -Value $card.Parameters[$name] } else { $null }
                    if ($mine -cne $theirs) { $name }
                })
        }
    }
    catch { Write-Verbose "The sentence could not be read back: $($_.Exception.Message)" }
    finally { $script:ProgressHandler = $handler }

    if ($script:RoundTripCache.Count -gt 500) { $script:RoundTripCache.Clear() }
    $script:RoundTripCache[$key] = $differ
    return , $differ
}

function Get-LambekStepValueKey {
    param([System.Collections.IDictionary] $Parameters)

    # The values in canonical form, sorted by name
    return (@($Parameters.Keys | Sort-Object -CaseSensitive | ForEach-Object { "$_=$(Format-LambekValue -Value $Parameters[$_])" }) -join ';')
}

function Format-LambekLiteralStep {
    param([pscustomobject] $Step, [hashtable] $Action, [string] $Language, [hashtable] $Units)

    # The plan as it is: the title of the action, then each value by name
    $title = $Step.Action
    if ($Action.ContainsKey('Title') -and $Action.Title.ContainsKey($Language)) { $title = $Action.Title[$Language] }
    $pairs = foreach ($name in $Step.Parameters.Keys) {
        "$name = $(Format-LambekHumanValue -Name $name -Value (Add-LambekQuote -Value $Step.Parameters[$name] -Units $Units) -Units $Units)"
    }
    return "$($title.ToLowerInvariant()) ($($pairs -join ', '))"
}
