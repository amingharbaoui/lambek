function New-LambekIntentCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory only.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Evidence,

        [Parameter(Mandatory)]
        [pscustomobject] $Scoring,

        [hashtable] $ParameterCache,

        # Weights learned from the plans the user ran: they may settle a close call, never make a change easier
        [pscustomobject] $Adapted,

        # The parameters of the step before, for a pronoun ("copy the images to D:\B then delete them")
        [System.Collections.IDictionary] $Referent
    )

    $request = $Evidence.Request
    $grammar = $Evidence.Grammar
    $implied = @()
    $language = $request.Language
    $lexicon = Get-LambekLexicon -Language $language
    $selection = Select-LambekIntent -Evidence $Evidence -Scoring $Scoring
    if ($Adapted) {
        $learned = Select-LambekIntent -Evidence $Evidence -Scoring $Adapted
        $readOnly = $learned.Best -and $learned.Best.Action.Risk -eq 'low' -and (-not $selection.Best -or $selection.Best.Action.Risk -eq 'low')
        if ($readOnly) {
            $selection = $learned
        }
        elseif ($selection.Status -eq 'Found' -and ($learned.Status -ne 'Found' -or $learned.Best.Action.Id -ne $selection.Best.Action.Id)) {
            # The two readings disagree on an action that changes things: ask
            $other = @($learned.Ranked | Where-Object { $_.Action.Id -ne $selection.Best.Action.Id }) | Select-Object -First 1
            $rest = @($selection.Ranked | Where-Object { $_.Action.Id -ne $selection.Best.Action.Id -and (-not $other -or $_.Action.Id -ne $other.Action.Id) })
            $selection = [pscustomobject]@{ Status = 'Ambiguous'; Best = $selection.Best; Ranked = @($selection.Best) + @($other | Where-Object { $_ }) + $rest; Integrity = $selection.Integrity }
        }
    }
    $best = $selection.Best

    # A question word as the verb ("which files...", "quels fichiers...") asks to read files placed or sorted somehow:
    # with nothing to place or sort them ("what time is it", "quelle heure est-il"), it is not a request
    $asking = $grammar.PSObject.Properties['Head'] -and $grammar.Head -and $grammar.Head.Word -in $lexicon.Interrogatives
    if (-not $grammar.IsSentence -and @($request.Words | Where-Object { $_ -in $lexicon.Interrogatives }).Count -gt 0) {
        $verbs = @($grammar.Assignment | Where-Object { $_.Type -match '(^|\s)s(\s|$)' -and $_.Word -notin $lexicon.Interrogatives })
        $asking = $verbs.Count -eq 0
    }
    if ($asking) {
        $readers = @($Evidence.Candidates | ForEach-Object { $_.Action })
        if ($best) { $readers = @($best.Action) }
        $named = @($readers | ForEach-Object { $_.Parameters } | Where-Object { $_.ContainsKey('Words') } | ForEach-Object { $_.Words.Keys })
        $grounded = @($request.Entities).Count -gt 0 -or @($request.Words | Where-Object { $_ -in $named }).Count -gt 0
        if (-not $grammar.IsSentence -or -not $grounded) {
            $selection = [pscustomobject]@{ Status = 'Unknown'; Best = $null; Ranked = @(); Integrity = $null }
            $best = $null
            $Evidence = [pscustomobject]@{ Request = $request; Grammar = $grammar; Candidates = $Evidence.Candidates; Guess = $null }
        }
    }

    # Only an order may become an action: what the user tells, asks about the world, or says about something else
    # is recognised as such, and nothing is chosen for it
    $act = Get-LambekDialogueAct -Request $request -Grammar $grammar
    # A tool of a server takes words no pack knows as its arguments (the title of a note): that is still an order
    if ($act.Rule -eq 'nothing known' -and $best -and $best.Action['Output'] -eq 'mcp') { $act = [pscustomobject]@{ Kind = 'Order'; Rule = $null; Say = $null; Subject = $null } }
    $statement = $null
    $recall = $null
    if ($act.Kind -ne 'Order') {
        # A question about what was told is answered from the conversation
        if ($act.Kind -eq 'Question') { $recall = Get-LambekAsked -Request $request -Grammar $grammar -Act $act -Candidates @($Evidence.Candidates) }
        # What is told keeps its meaning, read with the action its verb names: it is understood, never carried out
        if ($act.Kind -eq 'Report' -and $selection.Status -eq 'Found' -and $best) {
            $statement = Get-LambekStatement -Request $request -Grammar $grammar -Act $act -Action $best.Action
        }
        $selection = [pscustomobject]@{ Status = 'Unknown'; Best = $null; Ranked = @(); Integrity = $null }
        $best = $null
        $Evidence = [pscustomobject]@{ Request = $request; Grammar = $grammar; Candidates = $Evidence.Candidates; Guess = $null }
    }

    $status = 'Unknown'
    $guess = $null
    $pending = [System.Collections.Generic.List[string]]::new()
    $fromHabit = [System.Collections.Generic.List[string]]::new()
    $grammarLexicon = Get-LambekGrammarLexicon -Language $language
    $parameters = [ordered]@{}
    $missing = @()
    $questions = [System.Collections.Generic.List[string]]::new()

    # Decision
    if ($selection.Status -eq 'Unknown') {
        # What was recognised is said, when it is not an order; an order not understood is asked again
        if ($act.Kind -ne 'Order' -and $act.Say) { $questions.Add($act.Say) }
        else { $questions.Add($lexicon.SentenceQuestion) }
    }
    elseif ($selection.Status -eq 'Ambiguous') {
        $status = 'Ambiguous'
        # The options worth offering: two, or three when the third gains enough information
        $offer = Get-LambekQuestionOption -Evidence $Evidence -Ranked $selection.Ranked
        $titles = @(foreach ($id in $offer.Actions) { Get-LambekTitle -Action (@($selection.Ranked | Where-Object { $_.Action.Id -eq $id })[0].Action) -Language $language })
        if ($titles.Count -ge 3 -and $lexicon.AmbiguityQuestion3) { $questions.Add(($lexicon.AmbiguityQuestion3 -f $titles[0], $titles[1], $titles[2])) }
        else { $questions.Add(($lexicon.AmbiguityQuestion -f $titles[0], $titles[1])) }
    }
    else {
        # Parameters (cached when the same request is scored many times)
        $id = $best.Action.Id
        if ($null -ne $ParameterCache -and $ParameterCache.ContainsKey($id)) {
            $filled = $ParameterCache[$id]
        }
        else {
            $filled = Get-LambekParameter -Action $best.Action -Request $request -Grammar $grammar
            if ($null -ne $ParameterCache) { $ParameterCache[$id] = $filled }
        }

        $parameters = $filled.Values
        $missing = $filled.Missing
        $asked = @($filled.Questions)

        # A pronoun in the place of the object the sentence lacks ("supprime-les", "delete them")
        # stands for the files of the step before: their place and their filters, never where they went
        $pronouns = @($lexicon.FollowUp['Pronouns'])
        $hasPronoun = @($request.Tokens | Where-Object { $_ -in $pronouns }).Count -gt 0
        if ($Referent -and $hasPronoun -and 'o' -in @($grammar.Missing) -and -not ($parameters.Contains('Path') -or $parameters.Contains('Source'))) {
            $names = @($best.Action.Parameters | ForEach-Object { $_.Name })
            foreach ($name in $Referent.Keys) {
                $target = $name
                if ($name -eq 'Path' -and 'Path' -notin $names) { $target = 'Source' }
                if ($name -eq 'Source' -and 'Source' -notin $names) { $target = 'Path' }
                if ($target -notin $names -or $name -in 'Destination', 'NewName', 'Parent' -or $parameters.Contains($target)) { continue }
                $parameters[$target] = $Referent[$name]
            }
            $ordered = [ordered]@{}
            foreach ($parameter in $best.Action.Parameters) { if ($parameters.Contains($parameter.Name)) { $ordered[$parameter.Name] = $parameters[$parameter.Name] } }
            $parameters = $ordered
            $check = Get-LambekMissingParameter -Action $best.Action -Parameters $parameters -Language $language
            $missing = $check.Missing
            $asked = @($check.Questions)
        }

        # A place the user always gives the same ("to D:\Backup, as usual"), when the request leaves it out
        if ($Adapted) {
            foreach ($parameter in $best.Action.Parameters) {
                if (-not $parameter['Habit'] -or $parameters.Contains($parameter.Name)) { continue }
                $habit = Get-LambekHabit -ActionId $best.Action.Id -Name $parameter.Name
                if (-not $habit) { continue }
                $parameters[$parameter.Name] = $habit
                $fromHabit.Add($parameter.Name)
                $missing = @($missing | Where-Object { $_ -ne $parameter.Name })
                if ($parameter.ContainsKey('Question')) { $asked = @($asked | Where-Object { $_ -notin $parameter.Question.Values }) }
            }
        }

        foreach ($question in $grammar.Questions) {
            if ($question -ne $lexicon.SentenceQuestion) { $questions.Add($question) }
        }
        # "Which files?" already asks what "from which folder?" would
        if ('o' -in @($grammar.Missing) -and $best.Action.ContainsKey('RequireOneOf')) {
            $asked = @($asked | Where-Object { $_ -notin @($best.Action.RequireOneOf.Question.Values) })
        }
        foreach ($question in $asked) {
            if (-not $questions.Contains($question)) { $questions.Add($question) }
        }

        # Safety guards: never act on a negation or an exclusion, never ignore a value
        $hasNegation = @($request.Words | Where-Object { $_ -in $lexicon.Negations }).Count -gt 0
        $hasExclusion = @($request.Words | Where-Object { $_ -in $lexicon.Exclusions }).Count -gt 0
        # An exception the action understood ("except the .log files") is a filter, not a doubt
        $exceptions = @($best.Action.Parameters | Where-Object { $_.ContainsKey('After') -and @($_.After | Where-Object { $_ -in $lexicon.Exclusions }).Count -gt 0 })
        if ($hasExclusion -and @($exceptions | Where-Object { $parameters.Contains($_.Name) }).Count -gt 0) { $hasExclusion = $false }

        if ($hasNegation) {
            $questions.Insert(0, $lexicon.NegationQuestion)
        }
        if ($hasExclusion) {
            $questions.Insert(0, $lexicon.ExclusionQuestion)
        }
        if ($filled.Unused.Count -gt 0) {
            $questions.Add(($lexicon.UnusedQuestion -f ($filled.Unused -join ', ')))
        }

        # A missing part the parameters already hold: a folder alone stands for the files in it
        # ("delete everything in C:\Temp"), a second folder is the place ("my downloads on the desktop")
        $isSentence = $grammar.IsSentence
        $held = @{ o = @('Path', 'Source'); p = @('Destination') }
        $gaps = @($grammar.Missing)
        # A folder stands for the files in it only when no unknown word could be those files ("delete the screenshots in C:\A")
        if ($Evidence.PSObject.Properties['Guess'] -and $Evidence.Guess) { $held.Remove('o') }
        $covered = @(for ($i = 0; $i -lt $gaps.Count; $i++) {
                $names = $held[$gaps[$i]]
                if ($names -and @($names | Where-Object { $parameters.Contains($_) }).Count -gt 0) { $i }
            })
        if (-not $isSentence -and $gaps.Count -gt 0 -and $covered.Count -eq $gaps.Count) {
            $isSentence = $true
            foreach ($i in $covered) { [void] $questions.Remove($grammar.Questions[$i]) }
            $implied = @($covered | ForEach-Object { $gaps[$_] })
        }

        $status = 'Ready'
        if (-not $isSentence -or $missing.Count -gt 0 -or $hasNegation -or $hasExclusion -or $filled.Unused.Count -gt 0) {
            $status = 'NeedsInput'
        }
        if ($status -eq 'NeedsInput' -and $questions.Count -eq 0) {
            $questions.Add($lexicon.RephraseQuestion)
        }

        # Every word counts: an action that changes things never runs past a word that narrows the files
        # but gives no value ("delete the old files": old how? "delete the temporary files": temporary?)
        if ($status -eq 'Ready' -and $best.Action.Risk -ne 'low') {
            $consumed = [System.Collections.Generic.HashSet[string]]::new()
            # Words the action itself means ("free up space": space is what it frees)
            foreach ($word in @($best.Action['Uses'])) { if ($word) { [void] $consumed.Add($word) } }
            foreach ($parameter in $best.Action.Parameters) {
                if (-not $parameters.Contains($parameter.Name)) { continue }
                if ($parameter.ContainsKey('After')) { foreach ($word in $parameter.After) { [void] $consumed.Add($word) } }
                if ($parameter.ContainsKey('Words')) { foreach ($word in $parameter.Words.Keys) { [void] $consumed.Add($word) } }
            }
            foreach ($item in $grammar.Assignment) {
                if ($item.Word -match '^_' -or $item.Type -notin 'o o^l', 'o^r o' -or $consumed.Contains($item.Word)) { continue }

                # The value it asks for: the parameter that follows this word ("old" -> older than), else its meaning
                $status = 'NeedsInput'
                $owner = @($best.Action.Parameters | Where-Object { $_.ContainsKey('After') -and $_.ContainsKey('Entities') -and $item.Word -in $_.After -and -not $parameters.Contains($_.Name) }) | Select-Object -First 1
                if ($owner) {
                    $pending.Add($owner.Name)
                    $base = (ConvertFrom-LambekType -Type @($grammarLexicon.Words["_$(@($owner.Entities)[0])_"])[0])[0].Base
                    if ($grammarLexicon.Questions.ContainsKey($base)) { $questions.Add($grammarLexicon.Questions[$base]) }
                    else { $questions.Add(($lexicon.GuessOpenQuestion -f $item.Word)) }
                }
                else {
                    $questions.Add(($lexicon.GuessOpenQuestion -f $item.Word))
                }
                break
            }
        }

        # Words taken as free text ("create note title Groceries for Sunday") are used, not unknown
        $freeText = @($best.Action.Parameters | Where-Object { $_.ContainsKey('Free') -and $_.Free -and $parameters.Contains($_.Name) } | ForEach-Object { ConvertTo-LambekNormalizedText -Text ([string] $parameters[$_.Name]) }) -join ' '
        $chosen = @($best.Action.Parameters | Where-Object { $_.ContainsKey('Words') -and $parameters.Contains($_.Name) } | ForEach-Object { $_.Words.Keys })
        $unplaced = @($grammar.Unknown | Select-Object -Unique | Where-Object { $_ -notin $chosen -and " $freeText " -notlike "* $_ *" -and " $freeText " -notlike "* $($_)s *" })
        if ($status -eq 'Ready' -and $unplaced.Count -gt 0 -and $best.Action.Risk -ne 'low') {
            $status = 'NeedsInput'
            $guess = Get-LambekTypeGuess -Request $request -Grammar $grammar -Keeping
            $token = $unplaced[0]
            if ($guess) { $token = $guess.Token }
            $questions.Add(($lexicon.GuessOpenQuestion -f $token))
        }
    }

    # A word the grammar does not know, where the sentence needs one: ask what it means,
    # with the actions whose verb has the type the equation gave it ("purge" is s o^l, like delete or list)
    if (-not $guess -and $status -ne 'Ready' -and $Evidence.PSObject.Properties['Guess'] -and $Evidence.Guess) {
        $guess = $Evidence.Guess
        $options = @()
        if ($guess.IsAction) {
            # Only the actions that can take every value of the request ("the .log files in C:\Temp" is not something to create)
            $values = @($request.Entities | ForEach-Object { $_.Type } | Select-Object -Unique)
            $fitting = @($selection.Ranked | Where-Object {
                    $accepted = @($_.Action.Parameters | Where-Object { $_.ContainsKey('Entities') } | ForEach-Object { $_.Entities })
                    @($values | Where-Object { $_ -notin $accepted }).Count -eq 0
                })
            if ($fitting.Count -eq 0) { $fitting = @($selection.Ranked) }
            # Then first the actions the request already gives everything they need ("free" needs a size)
            $fitting = @($fitting | Sort-Object -Stable {
                    $needed = @($_.Action.Parameters | Where-Object { $_.ContainsKey('Required') -and $_.Required -and $_.ContainsKey('Entities') })
                    @($needed | Where-Object { @($_.Entities | Where-Object { $_ -in $values }).Count -eq 0 }).Count
                })
            $options = @(foreach ($candidate in $fitting) {
                    $verb = Get-LambekActionVerb -Action $candidate.Action -Language $language -Types $guess.Types
                    if ($verb) { $verb }
                }) | Select-Object -Unique -First 3
            $options = @($options)
        }
        $questions.Clear()
        if ($options.Count -gt 1) {
            $list = ($options[0..($options.Count - 2)] -join ', ') + " $($lexicon.Answer.Or) " + $options[-1]
            $questions.Add(($lexicon.GuessQuestion -f $guess.Token, $list))
        }
        else {
            $questions.Add(($lexicon.GuessOpenQuestion -f $guess.Token))
        }
    }

    # Card hash: action and parameters only, so it does not depend on wording or language
    $cardHash = $null
    if ($status -eq 'Ready') {
        $cardHash = Get-LambekCardHash -ActionId $best.Action.Id -Parameters $parameters
    }

    # Intent Card
    $actionId = $null
    $title = $null
    $risk = $null
    $pack = $null
    $confidence = 0.0
    if ($null -ne $best) {
        $actionId = $best.Action.Id
        $title = Get-LambekTitle -Action $best.Action -Language $language
        $risk = $best.Action.Risk
        $pack = $best.Pack
        $confidence = [math]::Round($best.Score, 4)
    }

    $top = foreach ($candidate in ($selection.Ranked | Select-Object -First 3)) {
        [pscustomobject]@{
            Action  = $candidate.Action.Id
            Score   = [math]::Round($candidate.Score, 4)
            Grammar = $candidate.Grammar
            Text    = [math]::Round($candidate.Text, 4)
        }
    }

    [pscustomobject]@{
        PSTypeName  = 'Lambek.IntentCard'
        Status      = $status
        Act         = $act.Kind
        Statement   = $statement
        Asked       = $recall
        Action      = $actionId
        Title       = $title
        Pack        = $pack
        Risk        = $risk
        Confidence  = $confidence
        Parameters  = $parameters
        Missing     = @($missing)
        Questions   = $questions.ToArray()
        Language    = $language
        Original    = $request.Original
        IsSentence  = $grammar.IsSentence
        Types       = $grammar.Types
        Implied     = $implied
        Guess       = $guess
        Integrity   = $selection.Integrity
        Readings    = $grammar.Readings
        Head        = $(if ($grammar.PSObject.Properties['Head']) { $grammar.Head } else { $null })
        Meaning     = $(if ($Evidence.PSObject.Properties['Meaning']) { @($Evidence.Meaning) } else { @() })
        Rows        = @(Get-LambekSignalRow -Evidence $Evidence)
        Pending     = $pending.ToArray()
        FromHabit   = $fromHabit.ToArray()
        Candidates  = @($top)
        RequestHash = $request.Hash
        CardHash    = $cardHash
    }
}

function Get-LambekActionVerb {
    param(
        [hashtable] $Action,
        [string] $Language,
        [string[]] $Types
    )

    # The verb of the action in this language, when one of its types is a solution, as the action says it, with its accents
    $pack = (Get-LambekAction -Id $Action.Id).Pack
    if (-not $pack.Words.ContainsKey($Language)) { return $null }
    foreach ($verb in $Action.Verbs) {
        if (-not $pack.Words[$Language].ContainsKey($verb)) { continue }
        if (@($pack.Words[$Language][$verb] | Where-Object { $_ -in $Types }).Count -eq 0) { continue }
        if ($Action.ContainsKey('Say') -and $Action.Say.ContainsKey($Language)) {
            $said = (@($Action.Say[$Language])[0] -split ' ')[0]
            if ((ConvertTo-LambekNormalizedText -Text $said) -eq $verb) { return $said }
        }
        return $verb
    }
    return $null
}
