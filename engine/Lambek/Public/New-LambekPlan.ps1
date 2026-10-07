function New-LambekPlan {
    <#
    .SYNOPSIS
        Compiles a request into a validated plan: Action Cards, dependency graph, order, and checked scripts.
    .EXAMPLE
        New-LambekPlan 'create the folder D:\Archive then move the .log files in C:\Temp to D:\Archive'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a plan in memory and changes nothing on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateLength(1, 4000)]
        [string] $Text,

        [AllowEmptyCollection()]
        [ValidatePattern('^\d+->\d+$')]
        [string[]] $Dependency = @(),

        # The parameters of the files a conversation is about, for a pronoun in the first step
        [System.Collections.IDictionary] $Referent,

        # Read the text alone, without the memory: no "like last time", no "did you mean"
        [switch] $NoRecall
    )

    process {
        # "comme la derniere fois": the plan comes from the memory
        if (-not $NoRecall) {
            $recalled = Resolve-LambekRecall -Text $Text
            if ($recalled) { return $recalled }
        }

        # "que veut dire purge ?", "combien font 3/7 + 2/5": the dictionaries or the calculation answer, nothing is planned
        if (-not $NoRecall) {
            $definition = Resolve-LambekDefinition -Text $Text
            if ($definition) { return ConvertTo-LambekReplyPlan -Text $Text -Language $definition.Language -Reply (Format-LambekDefinition -Definition $definition) }
            $calculation = Resolve-LambekCalculation -Text $Text
            if ($calculation) { return ConvertTo-LambekReplyPlan -Text $Text -Language $calculation.Language -Reply $calculation.Answer }
        }

        $steps = [System.Collections.Generic.List[object]]::new()
        $proposal = $null
        $trace = [System.Collections.Generic.List[object]]::new()
        $clock = [System.Diagnostics.Stopwatch]::StartNew()

        # One Action Card per clause
        Send-LambekProgress -Stage 'Split'
        # A compound task of a pack ("nettoie C:\Temp") is its steps; anything else is split into its clauses
        $method = Expand-LambekMethod -Text $Text
        if ($method) { $clauses = @($method.Steps) }
        else { $clauses = @(Split-LambekClause -Text $Text) }
        Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Split' -Detail "$($clauses.Count) step(s)"

        for ($i = 0; $i -lt $clauses.Count; $i++) {
            $units = 3 * $clauses.Count + 2
            Send-LambekProgress -Stage 'Read' -Step ($i + 1) -Percent (100 * (1 + 3 * $i) / $units)
            # A vague word read with its threshold makes the clause read again, once, with the threshold said
            $read = $clauses[$i]
            $vague = $null
            for ($pass = 0; $pass -lt 2; $pass++) {
                $request = ConvertTo-LambekRequest -Text $read
                $words = @($request.Entities | ForEach-Object { $_.Type }) -join ', '
                $detail = "$($request.Language), $($request.Terms.Count) term(s)"
                if ($words) { $detail += ", entities: $words" }
                if ($request.Corrections.Count -gt 0) { $detail += ", corrected: $(($request.Corrections | ForEach-Object { "$($_.From)->$($_.To)" }) -join ' ')" }
                Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Read' -Detail $detail -Step ($i + 1)

                Send-LambekProgress -Stage 'Match' -Step ($i + 1) -Percent (100 * (2 + 3 * $i) / $units)
                $card = $request | Resolve-LambekIntent -Referent $Referent
                $grammar = 'does not reduce to s'
                if ($card.IsSentence) { $grammar = 'reduces to s' }
                Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Type' -Detail "$($card.Types) $grammar" -Step ($i + 1)
                $match = 'no action'
                if ($card.Action) { $match = "$($card.Action) ($($card.Confidence))" }
                Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Match' -Detail "$match, $($card.Status)" -Step ($i + 1)

                $step = [pscustomobject]@{
                    Step       = $i + 1
                    Clause     = $clauses[$i]
                    Language   = $card.Language
                    Status     = $card.Status
                    Act        = $card.Act
                    Statement  = $card.Statement
                    Asked      = $card.Asked
                    Confidence = $card.Confidence
                    Types      = $card.Types
                    Implied    = @($card.Implied)
                    Guess      = $card.Guess
                    Senses     = @($request.Corrections | Where-Object { $_.PSObject.Properties['Sense'] -and $_.Sense -in 'abbreviation', 'dictionary', 'form' })
                    Pending    = @($card.Pending)
                    FromHabit  = @($card.FromHabit)
                    Votes      = $(if ($card.Integrity) { $card.Integrity.Votes })
                    # How the step was read: the verb, the number of readings, the actions scored, the meaning computed
                    Reading    = [pscustomobject]@{ Head = $card.Head; Readings = $card.Readings; Candidates = @($card.Candidates); Integrity = $card.Integrity; Meaning = @($card.Meaning); Corrections = @($request.Corrections); Rows = @($card.Rows); Borrowed = $request.Borrowed }
                    Action     = $card.Action
                    Risk       = $card.Risk
                    Parameters = $card.Parameters
                    Questions  = @($card.Questions)
                    Reads      = @()
                    Writes     = @()
                    Output     = $null
                    Script     = $null
                    Check      = $null
                    CardHash   = $card.CardHash
                }

                Send-LambekProgress -Stage 'Check' -Step ($i + 1) -Percent (100 * (3 + 3 * $i) / $units) -Types (Format-LambekShownType -Step $step)
                $step = Complete-LambekStep -Step $step

                # "les gros fichiers": a reading takes the threshold at once and says it; a change asks first
                if ($pass -gt 0 -or $vague -or ($request.PSObject.Properties['Proposal'] -and $request.Proposal)) { break }
                $vague = Get-LambekVagueMeaning -Step $step -Clause $clauses[$i]
                if (-not $vague -or $vague.Core) { break }
                $read = $vague.Sentence
            }
            if ($vague) {
                $step | Add-Member -NotePropertyName Vague -NotePropertyValue $vague -Force
                $step.Clause = $clauses[$i]
                if ($vague.Core -and $step.Status -ne 'Ready') {
                    $said = (Get-LambekLexicon -Language $step.Language).Answer
                    $step.Questions = @($said.VaguePropose -f $vague.Word, $vague.Shown)
                    if ($clauses.Count -eq 1 -and -not $proposal) { $proposal = [pscustomobject]@{ Word = "$($vague.Word) *"; From = $vague.Word; To = $vague.Shown; Text = $vague.Sentence } }
                }
            }

            # A word the dictionary finds next to a known one (not its synonym) is only proposed: "By relocate, do you mean move?"
            if ($request.PSObject.Properties['Proposal'] -and $request.Proposal -and $step.Status -ne 'Ready') {
                $step.Status = 'NeedsInput'
                $step.Questions = @((Get-LambekLexicon -Language $step.Language).Answer.DictionaryPropose -f $request.Proposal.From, $request.Proposal.To)
                if ($clauses.Count -eq 1) { $proposal = $request.Proposal }
            }
            $steps.Add($step)
            # The files this step is about are the referent of a pronoun in the next one
            if ($step.Action -and ($step.Parameters.Contains('Path') -or $step.Parameters.Contains('Source'))) { $Referent = $step.Parameters }
            if ($step.Script) {
                $check = 'passed'
                if (-not $step.Check.IsValid) { $check = 'blocked' }
                $detail = "script written, AST firewall $check"
                if ($step.Output -eq 'mcp') { $detail = "MCP call written, input schema $check" }
                Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Check' -Detail $detail -Step ($i + 1)
            }
        }

        Send-LambekProgress -Stage 'Order' -Percent (100 * (3 * $clauses.Count + 1) / (3 * $clauses.Count + 2))
        $plan = ConvertTo-LambekPlan -Text $Text -Steps $steps.ToArray() -Dependency $Dependency
        Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Order' -Detail "$($plan.Edges.Count) dependency(ies), order $($plan.Order -join ', ')"
        $plan | Add-Member -NotePropertyName Trace -NotePropertyValue $trace.ToArray()
        if ($method) { $plan | Add-Member -NotePropertyName Method -NotePropertyValue $method }
        if ($proposal) {
            $plan | Add-Member -NotePropertyName Suggestion -NotePropertyValue $proposal.Text
            $plan | Add-Member -NotePropertyName Proposal -NotePropertyValue $proposal
        }

        # What the user told stays with the conversation
        if (-not $NoRecall) { Add-LambekTold -Plan $plan }

        # Nothing understood and not small talk: the closest request remembered, or the closest example
        if (-not $NoRecall -and $plan.Steps.Count -gt 0 -and @($plan.Steps | Where-Object { $_.Action -or $_.Guess }).Count -eq 0) {
            $language = $plan.Steps[0].Language
            # What is told or asked is not a request badly said: nothing is proposed in its place
            $told = @($plan.Steps | Where-Object { $_.Act -ne 'Order' }).Count -gt 0
            if (-not $told -and -not (Get-LambekTalk -Text $Text -Language $language)) {
                $suggestion = Find-LambekSuggestion -Text $Text -Language $language
                if ($suggestion) {
                    # A typo can hide the language: the request it looks like tells it better
                    $plan | Add-Member -NotePropertyName Suggestion -NotePropertyValue $suggestion.Text
                    foreach ($step in $plan.Steps) { $step.Language = $suggestion.Language }
                }
                else {
                    # Still nothing: the optional proposer (a small transformer) may name an example of the action
                    # the request looks like. It is only a "did you mean": the user has to say it for it to be read
                    $proposed = Get-LambekProposal -Text $Text -Language $language
                    # Never towards an action that changes files: a "yes" said too fast must stay harmless
                    $harmless = $proposed -and (Get-LambekAction -Id $proposed.Action).Action.Risk -eq 'low'
                    if ($harmless -and $proposed.Example) {
                        $plan | Add-Member -NotePropertyName Suggestion -NotePropertyValue $proposed.Example
                        $plan | Add-Member -NotePropertyName Proposer -NotePropertyValue $proposed
                    }
                }
            }
        }
        $plan
    }
}

function ConvertTo-LambekReplyPlan {
    param([string] $Text, [string] $Language, [string] $Reply)

    # A plan with one step that asks for no action: the answer is the reply
    $step = [pscustomobject]@{
        Step = 1; Clause = $Text; Language = $Language; Status = 'Unknown'; Act = 'Question'; Statement = $null; Asked = $null; Confidence = 0.0; Types = ''
        Implied = @(); Guess = $null; Senses = @(); Pending = @(); FromHabit = @(); Votes = $null; Reading = $null
        Action = $null; Risk = $null; Parameters = [ordered]@{}; Questions = @(); Reads = @(); Writes = @()
        Output = $null; Script = $null; Check = $null; CardHash = $null
    }
    $plan = ConvertTo-LambekPlan -Text $Text -Steps @($step)
    $plan | Add-Member -NotePropertyName Trace -NotePropertyValue @()
    $plan | Add-Member -NotePropertyName Reply -NotePropertyValue $Reply
    return $plan
}

function Add-LambekTrace {
    param(
        [System.Collections.Generic.List[object]] $Trace,
        [System.Diagnostics.Stopwatch] $Clock,
        [string] $Stage,
        [string] $Detail,
        [int] $Step = 0
    )

    $Trace.Add([pscustomobject]@{
            Stage        = $Stage
            Step         = $Step
            Detail       = $Detail
            Milliseconds = [math]::Round($Clock.Elapsed.TotalMilliseconds, 1)
        })
    $Clock.Restart()
}
