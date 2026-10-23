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
        [switch] $NoRecall,

        # Read the text as it is, without looking for the request inside the words said around it
        [switch] $Bare
    )

    process {
        # A new message: what the one before read is forgotten (a plan made inside this one keeps what it read)
        if ($script:PlanDepth -eq 0) { Clear-LambekReadCache }
        $script:PlanDepth++
        try {
            # "slt", "cmt tu vas", "la capitalle": what was typed fast is read as it was meant, and the plan says so
            $typing = Repair-LambekTyping -Text $Text -Language $script:LanguageHint
            $Text = $typing.Text

            # "euh, efface les fichiers .tmp stp", "could you delete the .log files, thanks": when the sentence as it
            # was written makes no plan, the request without the words said around it is read too, and its plan is
            # kept only when it is ready to act (what was understood before stays as it was: "salut, tu vas bien ?")
            if ($script:PlanDepth -eq 1 -and -not $Bare) {
                $spoken = ConvertTo-LambekBareRequest -Text $Text
                if ($spoken -cne $Text) {
                    $plan = New-LambekPlan -Text $Text -Dependency $Dependency -Referent $Referent -NoRecall:$NoRecall -Bare
                    if ($plan.Status -ne 'Ready') {
                        $barePlan = New-LambekPlan -Text $spoken -Dependency $Dependency -Referent $Referent -NoRecall:$NoRecall -Bare
                        if ($barePlan.Status -eq 'Ready' -and @($barePlan.Steps | Where-Object { $_.Action }).Count -gt 0) { return $barePlan }
                    }
                    return $plan
                }
            }

            # "ma soeur en a 2", "je fais quoi ?": read as "ma soeur a 2 chats", "qu'est-ce que je fais ?"
            if (-not $NoRecall) { $Text = ConvertTo-LambekPlainSentence -Text $Text }

            # "comme la derniere fois": the plan comes from the memory
            if (-not $NoRecall) {
                $recalled = Resolve-LambekRecall -Text $Text
                if ($recalled) { return $recalled }
            }

            # What the message is (an order, a fact, a question about the world, a story asked...), before any reader
            # reads it: the router of acts only proposes, the readers still decide
            $route = $null
            if (-not $NoRecall) { $route = Get-LambekRoute -Text $Text }

            # "que veut dire purge ?", "combien font 3/7 + 2/5": the dictionaries or the calculation answer, nothing is planned
            if (-not $NoRecall) {
                # "combien de chats avons-nous ?", "pourquoi ?" (after an answer from what was told): answered from what was told.
                # Anything else said, a "pourquoi ?" after it is no longer about that answer
                $told = Resolve-LambekToldQuestion -Text $Text
                if (-not $told) { Set-LambekLastProof }
                # "quelle est la capitale du Nigeria ?", "who wrote Hamlet?": what Lambek read in Wikidata, with where it read it
                # ("combien d'habitants a la Belgique ?" reads as a count of what was told, too: Wikidata answers it first,
                # and says what was told about it)
                if (-not $told -or ($told.Asked.PSObject.Properties['Kind'] -and $told.Asked.Kind -eq 'count')) {
                    $fact = Resolve-LambekFact -Text $Text
                    if ($fact) { return ConvertTo-LambekReplyPlan -Text $Text -Language $fact.Language -Reply $fact.Reply -Spoken }
                }
                # "Marie a 2 ans de plus que Paul... quel age a Marie ?", "qui est au milieu ?": solved and checked
                $problem = Resolve-LambekProblem -Text $Text
                if ($problem) { return ConvertTo-LambekReplyPlan -Text $Text -Language $problem.Language -Reply $problem.Reply -Spoken }
                # "tous les chats de ma soeur sont noirs... Minou est-il noir ?": kept as told, and answered yes, no, or that it
                # cannot be known, with what the answer rests on
                $category = Resolve-LambekCategory -Text $Text
                if ($category) {
                    if (@($category.Facts).Count -gt 0) { Add-LambekTold -Plan ([pscustomobject]@{ Steps = @($category.Facts | ForEach-Object { [pscustomobject]@{ Statement = $_ } }) }) }
                    return ConvertTo-LambekReplyPlan -Text $Text -Language $category.Language -Reply $category.Reply -Spoken
                }
                # "et si Tweety etait un pingouin ?": a world imagined, where what would change is said; nothing told changes
                $imagined = Resolve-LambekImagine -Text $Text
                if ($imagined) { return ConvertTo-LambekReplyPlan -Text $Text -Language $imagined.Language -Reply $imagined.Reply -Spoken }
                # "pourquoi la route est mouillee ?": what it follows from, else what may explain it, and how to tell
                $why = Resolve-LambekWhy -Text $Text
                if ($why) { return ConvertTo-LambekReplyPlan -Text $Text -Language $why.Language -Reply $why.Reply -Spoken }
                $definition = Resolve-LambekDefinition -Text $Text
                if ($definition) { return ConvertTo-LambekReplyPlan -Text $Text -Language $definition.Language -Reply (Format-LambekDefinition -Definition $definition) }
                $calculation = Resolve-LambekCalculation -Text $Text
                if ($calculation) { return ConvertTo-LambekReplyPlan -Text $Text -Language $calculation.Language -Reply $calculation.Answer }
                if ($told) { return ConvertTo-LambekReplyPlan -Text $Text -Language $told.Language -Asked $told.Asked }
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
            if (@($typing.Changes).Count -gt 0) {
                Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Read' -Detail "typed: $((@($typing.Changes) | ForEach-Object { "$($_.From)->$($_.To)" }) -join ' ')"
            }
            # (what the router proposed is said with the reading of the first step)
            $routeDetail = ''
            if ($route) {
                $act = 'none'
                if ($route.Act) { $act = $route.Act }
                $routeDetail = ", act: $act (proposed $($route.Proposed), margin $($route.Margin))"
            }

            # "s'il pleut, ...": the condition read, kept for the clause after it, never told on its own
            $condition = $null
            for ($i = 0; $i -lt $clauses.Count; $i++) {
                $units = 3 * $clauses.Count + 2
                Send-LambekProgress -Stage 'Read' -Step ($i + 1) -Percent (100 * (1 + 3 * $i) / $units)
                # "...because...": this clause is the reason of the one before it
                # (compared as a character: a culture-aware comparison ignores control characters and would say yes to anything)
                $reason = $clauses[$i].Length -gt 0 -and $clauses[$i][0] -eq [char] 1
                if ($reason) { $clauses[$i] = $clauses[$i].Substring(1) }
                $conditional = $clauses[$i].Length -gt 0 -and $clauses[$i][0] -eq [char] 2
                if ($conditional) { $clauses[$i] = $clauses[$i].Substring(1) }
                # A vague word read with its threshold makes the clause read again, once, with the threshold said
                $read = $clauses[$i]
                $vague = $null
                for ($pass = 0; $pass -lt 2; $pass++) {
                    $request = ConvertTo-LambekRequest -Text $read
                    # (what the user wrote, before a vague word was read again with its threshold)
                    if ($pass -eq 0) { $written = $request }
                    $words = @($request.Entities | ForEach-Object { $_.Type }) -join ', '
                    $detail = "$($request.Language), $($request.Terms.Count) term(s)"
                    if ($words) { $detail += ", entities: $words" }
                    if ($request.Corrections.Count -gt 0) { $detail += ", corrected: $(($request.Corrections | ForEach-Object { "$($_.From)->$($_.To)" }) -join ' ')" }
                    if ($i -eq 0 -and $pass -eq 0) { $detail += $routeDetail }
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
                        ActSay     = $card.ActSay
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
                    # An action on files needs files (Test-LambekFileObject): "c'est quelle chanson celle-ci", "where is New
                    # Zealand located on a map" plan nothing
                    if ($step.Status -eq 'Ready' -and $step.Action -and -not (Test-LambekFileObject -Step $step -Request $written -Route $route)) {
                        Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Match' -Detail "$($step.Action) set aside: no file named" -Step ($i + 1)
                        $step.Action = $null
                        $step.Status = 'Unknown'
                        $step.Confidence = 0.0
                        $step.Parameters = [ordered]@{}
                        $step.Questions = @((Get-LambekLexicon -Language $step.Language).SentenceQuestion)
                    }
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
                # The reason is kept with the thing it is the reason of: because(E, R) in the logic
                if ($reason -and $steps.Count -gt 0 -and $step.Statement -and $steps[$steps.Count - 1].Statement) {
                    $step.Statement | Add-Member -NotePropertyName ReasonFor -NotePropertyValue $steps[$steps.Count - 1].Statement.Core -Force
                }
                # The condition is not a step: it waits for the clause it is the condition of
                # (a condition that could not be read leaves what follows it unread too: it is never told as if it always held)
                if ($conditional) { $condition = $(if ($step.Statement) { $step.Statement } else { $false }); continue }
                if ($condition -eq $false) { $step.Statement = $null; $condition = $null }
                if ($condition) {
                    if ($step.Statement) { Set-LambekCondition -Statement $step.Statement -Condition $condition }
                    else {
                        # An order on a condition is never planned to run: it is asked when the condition holds
                        $step.Status = 'NeedsInput'
                        $step.Questions = @((Get-LambekLexicon -Language $step.Language).Dialogue.Say['ConditionalOrder'])
                    }
                    $condition = $null
                }
                # (numbered as the steps kept: a condition is none)
                $step.Step = $steps.Count + 1
                $steps.Add($step)
                # What this clause told is known to the next one ("...mais elle travaille a Paris")
                if (-not $NoRecall) { Add-LambekTold -Plan ([pscustomobject]@{ Steps = @($step) }) }
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

            if ($route) { $plan | Add-Member -NotePropertyName Route -NotePropertyValue $route }

            # Nothing the readers can act on, and the router knows what it is: "raconte-moi une blague", "envoie un mail
            # a Paul", "estoy cansado", a fact said in German. Said as such, rather than "I did not understand"
            $routed = Get-LambekRouteReply -Route $route -Plan $plan -Text $Text
            if ($routed) {
                $reply = ConvertTo-LambekReplyPlan -Text $Text -Language $plan.Steps[0].Language
                $reply.Trace = $trace.ToArray()
                $reply | Add-Member -NotePropertyName Route -NotePropertyValue $route
                $reply | Add-Member -NotePropertyName RouteReply -NotePropertyValue $routed
                return $reply
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
                        # the request looks like. It is only a "did you mean": the user has to say it for it to be read.
                        # Only for what the router takes for an order: "when i came back from this place" asks for nothing
                        $proposed = $null
                        if (-not $route -or $route.Proposed -eq 'Order') { $proposed = Get-LambekProposal -Text $Text -Language $language }
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
        finally { $script:PlanDepth-- }
    }
}

function ConvertTo-LambekReplyPlan {
    param([string] $Text, [string] $Language, [string] $Reply, [pscustomobject] $Asked, [switch] $Spoken)

    # A plan with one step that asks for no action: the answer is the reply, or the answer to what is asked about what was told
    $step = [pscustomobject]@{
        Step = 1; Clause = $Text; Language = $Language; Status = 'Unknown'; Act = 'Question'; ActSay = $null; Statement = $null; Asked = $Asked; Confidence = 0.0; Types = ''
        Implied = @(); Guess = $null; Senses = @(); Pending = @(); FromHabit = @(); Votes = $null; Reading = $null
        Action = $null; Risk = $null; Parameters = [ordered]@{}; Questions = @(); Reads = @(); Writes = @()
        Output = $null; Script = $null; Check = $null; CardHash = $null
    }
    $plan = ConvertTo-LambekPlan -Text $Text -Steps @($step)
    $plan | Add-Member -NotePropertyName Trace -NotePropertyValue @()
    if ($Reply) { $plan | Add-Member -NotePropertyName Reply -NotePropertyValue $Reply }
    if ($Spoken) { $plan | Add-Member -NotePropertyName Spoken -NotePropertyValue $true }
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

function Test-LambekFileObject {
    param([pscustomobject] $Step, [pscustomobject] $Request, [pscustomobject] $Route)

    # An action of the files pack needs files to act on. A folder, a path, a file name, an extension or a pronoun for
    # files named before is enough;
    # else the message must read as an order (the router proposes no other act for it), and name files with a word of
    # the pack ("fichiers", "photos", "chansons") or a kind of file
    if (-not "$($Step.Action)".StartsWith('files.')) { return $true }
    $parameters = $Step.Parameters
    foreach ($name in 'Path', 'Source', 'Destination', 'Parent', 'Name', 'NewName', 'Extension', 'ExceptExtension', 'ExceptName') {
        if ($parameters.Contains($name) -and $parameters[$name]) { return $true }
    }
    # ("restaure-les": files named before, by a pronoun)
    $tokens = @($Request.Tokens) + @($Request.Words)
    # (a pronoun, not an article: joined to its verb, "restaure-les", or last, "show them")
    $pronouns = @((Get-LambekLexicon -Language $Step.Language).FollowUp['Pronouns'])
    $said = @($Request.Tokens)
    if ($said.Count -gt 0 -and $said[-1] -in $pronouns) { return $true }
    foreach ($pronoun in $pronouns) { if ("$($Request.Original)" -match "(?i)\p{L}-$([regex]::Escape($pronoun))(?!\p{L})") { return $true } }
    if ($Route -and $Route.Proposed -and $Route.Proposed -ne 'Order') { return $false }
    if ($parameters.Contains('Kind') -and $parameters['Kind']) { return $true }
    foreach ($pack in $script:Packs.Values) {
        if (-not $pack.Words.ContainsKey($Step.Language)) { continue }
        $words = $pack.Words[$Step.Language]
        foreach ($token in $tokens) {
            if ($words.ContainsKey("$token") -and @($words["$token"] | Where-Object { $_ -eq 'o' }).Count -gt 0) { return $true }
        }
    }
    return $false
}
