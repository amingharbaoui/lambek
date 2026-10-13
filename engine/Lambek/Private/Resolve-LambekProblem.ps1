function Resolve-LambekProblem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # A problem told in words, solved and checked. Two kinds, read with the small words of each language:
    #   quantities: "Marie a 2 ans de plus que Paul. A eux deux, ils ont 30 ans. Quel age a Marie ?" becomes equations,
    #   solved exactly; every value said is put back in every equation before it is said;
    #   places in a row: "Alice n'est pas a cote de Bob. Chloe est a gauche d'Alice. Qui est au milieu ?" is answered by
    #   trying every order, and keeping the ones that keep every condition.
    # What is told without a question is kept for the rest of the conversation. Anything else is left to the rest of
    # Lambek: every sentence of the message must read as part of the problem, or nothing is taken
    $store = Get-LambekProblemStore
    $trigger = Get-LambekProblemTrigger
    if (-not $trigger.Problem.IsMatch($Text) -and -not ($store.Count -gt 0 -and $trigger.Question.IsMatch($Text))) { return $null }

    $language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text)
    $dialogue = (Get-LambekLexicon -Language $language).Dialogue
    if (-not $dialogue -or -not $dialogue['Problems']) { return $null }
    $problems = $dialogue['Problems']

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($sentence in Split-LambekProblemSentence -Text $Text -Language $language) {
        $read = Read-LambekPlaceSentence -Sentence $sentence.Text -Question:$sentence.Question -Language $language
        if (-not $read) { $read = Read-LambekQuantitySentence -Sentence $sentence.Text -Question:$sentence.Question -Language $language }
        if (-not $read) { return $null }
        $read | Add-Member -NotePropertyName Original -NotePropertyValue $sentence.Original -Force
        $items.Add($read)
    }
    $places = @($items | Where-Object { $_.Kind -in 'setup', 'place', 'placequestion' })
    if ($places.Count -gt 0 -and $places.Count -ne $items.Count) { return $null }
    if ($places.Count -gt 0) { return Resolve-LambekPlaceProblem -Items $items.ToArray() -Language $language -Problems $problems }
    return Resolve-LambekQuantityProblem -Items $items.ToArray() -Language $language -Problems $problems
}

function Get-LambekProblemStore {
    # What was told of a problem in this conversation (each chat has its own), in the order it was told
    if ($null -eq $script:ProblemStores) { $script:ProblemStores = [System.Collections.Generic.Dictionary[object, object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance) }
    $here = Get-LambekTold
    if (-not $script:ProblemStores.ContainsKey($here)) { $script:ProblemStores[$here] = [System.Collections.Generic.List[object]]::new() }
    return , $script:ProblemStores[$here]
}

function Get-LambekProblemTrigger {
    # The words without which no message is a problem, in every language, read once: a quick look before any reading
    if ($null -ne $script:ProblemTrigger) { return $script:ProblemTrigger }
    $problem = [System.Collections.Generic.List[string]]::new()
    $question = [System.Collections.Generic.List[string]]::new()
    foreach ($language in Get-LambekAvailableLanguage) {
        $dialogue = (Get-LambekLexicon -Language $language).Dialogue
        if (-not $dialogue -or -not $dialogue['Problems']) { continue }
        $p = $dialogue['Problems']
        foreach ($key in 'More', 'Fewer', 'Times', 'TimesFewer', 'Together') { foreach ($phrase in @($p[$key])) { $problem.Add((ConvertTo-LambekPhrasePattern -Phrase $phrase)) } }
        foreach ($rule in @($p['Rewrite'])) { $problem.Add(($rule[0] -replace '^\(\?i\)', '')) }
        foreach ($key in 'Left', 'Right', 'Next', 'Between', 'Middle', 'End', 'Row') { foreach ($phrase in @($p['Places'][$key])) { $problem.Add((ConvertTo-LambekPhrasePattern -Phrase $phrase)) } }
        foreach ($key in 'Who', 'Order', 'WhereIs') { foreach ($phrase in @($p['Places'][$key])) { $question.Add((ConvertTo-LambekPhrasePattern -Phrase $phrase)) } }
        foreach ($phrase in @($dialogue['General']['HowMany'])) { $question.Add((ConvertTo-LambekPhrasePattern -Phrase $phrase)) }
    }
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $script:ProblemTrigger = [pscustomobject]@{
        Problem  = [regex]::new("(?:$($problem -join '|'))", $options)
        Question = [regex]::new("(?:$($question -join '|'))", $options)
    }
    return $script:ProblemTrigger
}

function ConvertTo-LambekPhrasePattern {
    param([string] $Phrase)

    # A phrase as whole words, its apostrophes either way ("d'" or the other apostrophe), its last letter not followed by another
    $escaped = [regex]::Escape($Phrase.Trim()) -replace "['\u2019]", "['\u2019]"
    $end = '(?![\p{L}])'
    if ($Phrase -match "['\u2019]$") { $end = '' }
    return "(?<![\p{L}])$escaped$end"
}

function Find-LambekPhraseAtStart {
    param([string] $Text, [object[]] $Phrases)

    # The longest of the phrases the text starts with, and what follows it
    foreach ($phrase in @($Phrases | Where-Object { $_ } | Sort-Object { -$_.Length })) {
        $match = [regex]::Match($Text, "(?i)^\s*$(ConvertTo-LambekPhrasePattern -Phrase $phrase)\s*")
        if ($match.Success) { return [pscustomobject]@{ Phrase = $phrase; Rest = $Text.Substring($match.Length).Trim() } }
    }
    return $null
}

function Split-LambekProblemSentence {
    param([string] $Text, [string] $Language)

    # The sentences of the message, each with what it was as written and whether it asks; ", et" and ", puis" start
    # another one. The rewrites of the language put each in its plainest form ("quel age a Marie" asks how many years)
    $problems = (Get-LambekLexicon -Language $Language).Dialogue['Problems']
    $and = (@($problems['And']) | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $parts = [regex]::Split($Text.Trim(), "(?<=[.!?;])\s+|\s*,\s*(?=(?:$and)\s)")
    foreach ($part in $parts) {
        $original = $part.Trim()
        if (-not $original) { continue }
        $question = $original -match '\?\s*$'
        $plain = ($original -replace '[.!?;]+\s*$', '').Trim()
        $plain = [regex]::Replace($plain, "(?i)^(?:$and)\s+", '').Trim(' ', ',')
        foreach ($rule in @($problems['Rewrite'])) { $plain = [regex]::Replace($plain, $rule[0], $rule[1]) }
        $plain = ($plain -replace '\s+', ' ').Trim(' ', ',')
        if (-not $plain) { continue }
        [pscustomobject]@{ Text = $plain; Original = ($original -replace '[.;]+\s*$', '').Trim(); Question = $question }
    }
}

function Get-LambekProblemNumber {
    param([string] $Word, [string] $Language)

    # "2", "deux", "une", "1,5": the number, exact; nothing for a word that is none
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $value = "$([LambekNumberWords]::Digitize($Word, $Language))".Trim()
    if ($value -in @($general['One'])) { $value = '1' }
    if ($value -notmatch '^\d+(?:[.,]\d+)?$') { return $null }
    if ($value -match '[.,]') {
        $parts = $value -split '[.,]'
        $whole = [System.Numerics.BigInteger]::Parse($parts[0] + $parts[1])
        return [LambekRational]::new($whole, [System.Numerics.BigInteger]::Pow(10, $parts[1].Length))
    }
    return [LambekRational]::new([System.Numerics.BigInteger]::Parse($value), 1)
}

function Get-LambekProblemNoun {
    param([string] $Noun, [string] $Language)

    # The thing counted, the same whatever its number: "chats" and "chat" are one thing
    $plain = ConvertTo-LambekNormalizedText -Text $Noun
    $dictionary = Get-LambekDictionary -Language $Language
    if ($dictionary) {
        $lemma = @($dictionary.Lemmas($plain, $Language) | Where-Object { $_.Pos -eq 'n' } | Select-Object -First 1)
        if ($lemma.Count -gt 0) { return ConvertTo-LambekNormalizedText -Text "$($lemma[0].Lemma)" }
    }
    return $plain
}

function Get-LambekProblemHolder {
    param([string] $Written, [string] $Language, [switch] $Speaker, [switch] $Listener)

    # Who has: "je" and "moi" are the one who speaks (said to Lambek: "vous", "you"), "ma soeur" and "votre soeur"
    # are the same one whatever side they are said from; "ils", "nous" are everyone in the problem
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $problems = (Get-LambekLexicon -Language $Language).Dialogue['Problems']
    $plain = (ConvertTo-LambekNormalizedText -Text $Written).Trim()
    $me = @($general['Me']) + @($general['Speakers'] | Where-Object { $_ -notin @($problems['All']) })
    if ($Listener) { $me = @($general['Addressee']) }
    if ($Speaker -or $plain -in $me) { return [pscustomobject]@{ Key = 'speaker'; Written = $Written } }
    if ($plain -in @($problems['All'])) { return [pscustomobject]@{ Key = 'all'; Written = $Written } }
    # (an article says nothing of who it is: "le fils" and "son fils" are the same one; "mon" and "ma" say whose)
    $owners = @($general['Owners'])
    $articles = @($general['Determiners'] | Where-Object { $_ -notin $owners })
    $words = @($plain -split '[^\p{L}\p{N}]+' | Where-Object { $_ -and $_ -notin $articles } | ForEach-Object { if ($_ -in $owners) { '@' } else { $_ } })
    if ($words.Count -eq 0) { return $null }
    return [pscustomobject]@{ Key = "other:$($words -join ' ')"; Written = $Written }
}

function Read-LambekHolding {
    param([string] $Sentence, [string] $Language, [switch] $Listener)

    # "Marie a 2 ans", "j'ai 3 chats", "my sister has 5 cats", read with the grammar: who, how many, of what
    $problems = (Get-LambekLexicon -Language $Language).Dialogue['Problems']
    try { $request = ConvertTo-LambekRequest -Text $Sentence -Language $Language } catch { return $null }
    $reading = Get-LambekGeneralReading -Request $request -Listener:$Listener
    # In a problem, a name that is also a word ("Marie" is a form of "marier") is read as the name it is written as:
    # the sentence is read again with a name no dictionary knows in its place
    $first = [regex]::Match($Sentence, '^(?<name>\p{Lu}[\p{Ll}-]+)(?=\s)')
    if (-not $reading -and $first.Success) {
        $stand = 'Qzxw'
        try { $request = ConvertTo-LambekRequest -Text ($stand + $Sentence.Substring($first.Length)) -Language $Language } catch { return $null }
        $reading = Get-LambekGeneralReading -Request $request -Listener:$Listener
        if ($reading -and "$($reading.Name)" -eq $stand) { $reading.Name = $first.Groups['name'].Value }
        elseif ($reading) { $reading = $null }
    }
    if (-not $reading -or $reading.Kind -ne 'statement' -or ($reading.PSObject.Properties['Negated'] -and $reading.Negated)) { return $null }
    if ((ConvertTo-LambekNormalizedText -Text "$($reading.Verb)") -ne (ConvertTo-LambekNormalizedText -Text "$($problems['Have'])")) { return $null }
    if (@($reading.Roles.Keys).Count -ne 1 -or -not $reading.Roles.Contains('object')) { return $null }
    $object = "$($reading.Roles['object'])"
    # ("2 ans", "3 years" are read as a duration, one word for the grammar: the words as written say how many of what)
    if ($object -match '^_[a-z]+_$') { $object = [regex]::Match($Sentence, '\S+\s+\p{L}[\p{L}-]*\s*$').Value.Trim() }
    $match = [regex]::Match($object, '^(?<n>\S+)\s+(?<noun>\p{L}[\p{L}-]*)$')
    if (-not $match.Success) { return $null }
    $number = Get-LambekProblemNumber -Word $match.Groups['n'].Value -Language $Language
    if ($null -eq $number) { return $null }
    if ($reading.Agent -eq 'speaker') { $holder = Get-LambekProblemHolder -Written '' -Language $Language -Speaker }
    else { $holder = Get-LambekProblemHolder -Written "$($reading.Name)" -Language $Language -Listener:$Listener }
    if (-not $holder -or $holder.Key -eq 'all') { return $null }
    return [pscustomobject]@{ Holder = $holder; Number = $number; Noun = $match.Groups['noun'].Value; NounKey = (Get-LambekProblemNoun -Noun $match.Groups['noun'].Value -Language $Language) }
}

function Read-LambekQuantitySentence {
    param([string] $Sentence, [string] $Language, [switch] $Question, [switch] $Listener)

    # One sentence of a problem of quantities: a question, a sum, a ratio, a difference, or a value
    $lexicon = Get-LambekLexicon -Language $Language
    $problems = $lexicon.Dialogue['Problems']
    $alt = { param($list) (@($list | Where-Object { $_ } | Sort-Object { -$_.Length } | ForEach-Object { ConvertTo-LambekPhrasePattern -Phrase $_ }) -join '|') }

    # "combien de chats a Marie ?", "how many years does Paul have?"
    $howMany = @($lexicon.Dialogue['General']['HowMany'])
    if ($Question -or @($howMany | Where-Object { $Sentence -match "(?i)^$(ConvertTo-LambekPhrasePattern -Phrase $_)" }).Count -gt 0) {
        try { $request = ConvertTo-LambekRequest -Text $Sentence -Language $Language } catch { return $null }
        $asked = Get-LambekCountQuestion -Request $request
        if (-not $asked) { return $null }
        return [pscustomobject]@{ Kind = 'question'; Asked = $asked; NounKey = (Get-LambekProblemNoun -Noun "$($asked.Noun)" -Language $Language) }
    }

    # "a eux deux, ils ont 30 ans", "Marie et Paul ont 30 ans en tout", "together they have 12 cats"
    $together = [regex]::Match($Sentence, "(?i)$(& $alt $problems['Together'])")
    if ($together.Success) {
        $rest = ($Sentence.Remove($together.Index, $together.Length) -replace '\s+', ' ').Trim(' ', ',')
        $match = [regex]::Match($rest, '^(?<who>.+?)\s+\p{L}+\s+(?<n>\S+)\s+(?<noun>\p{L}[\p{L}-]*)$')
        if (-not $match.Success) { return $null }
        $number = Get-LambekProblemNumber -Word $match.Groups['n'].Value -Language $Language
        if ($null -eq $number) { return $null }
        $and = (@($problems['And']) | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $holders = @(foreach ($part in [regex]::Split($match.Groups['who'].Value, "\s*,\s*|\s+(?:$and)\s+")) {
                if (-not $part.Trim()) { continue }
                $holder = Get-LambekProblemHolder -Written $part.Trim() -Language $Language -Listener:$Listener
                if (-not $holder) { return $null }
                $holder
            })
        if ($holders.Count -eq 0 -or (@($holders | Where-Object { $_.Key -eq 'all' }).Count -gt 0 -and $holders.Count -gt 1)) { return $null }
        if ($holders.Count -eq 1 -and $holders[0].Key -ne 'all') { return $null }
        return [pscustomobject]@{ Kind = 'sum'; Holders = $holders; Number = $number; Noun = $match.Groups['noun'].Value; NounKey = (Get-LambekProblemNoun -Noun $match.Groups['noun'].Value -Language $Language) }
    }

    # "Marie a 3 fois plus de chats que Paul", "Paul has 2 times fewer cats than Marie"
    foreach ($kind in 'Times', 'TimesFewer') {
        $match = [regex]::Match($Sentence, "(?i)^(?<head>.+?)\s+(?<k>\S+)\s+(?:$(& $alt $problems[$kind]))\s*(?<noun>\p{L}[\p{L}-]*)\s+(?:$(& $alt $problems['Than']))\s*(?<b>.+)$")
        if (-not $match.Success) { continue }
        $factor = Get-LambekProblemNumber -Word $match.Groups['k'].Value -Language $Language
        $holding = Read-LambekHolding -Sentence "$($match.Groups['head'].Value) 2 $($match.Groups['noun'].Value)" -Language $Language -Listener:$Listener
        $other = Get-LambekProblemHolder -Written $match.Groups['b'].Value.Trim() -Language $Language -Listener:$Listener
        if ($null -eq $factor -or -not $holding -or -not $other -or $other.Key -eq 'all') { return $null }
        return [pscustomobject]@{ Kind = 'ratio'; Holder = $holding.Holder; Other = $other; Number = $factor; Fewer = ($kind -eq 'TimesFewer'); Noun = $match.Groups['noun'].Value; NounKey = $holding.NounKey }
    }

    # "Marie a 2 ans de plus que Paul", "I have 3 cats fewer than my sister"
    foreach ($kind in 'More', 'Fewer') {
        $match = [regex]::Match($Sentence, "(?i)^(?<head>.+?)\s+(?<n>\S+)\s+(?<noun>\p{L}[\p{L}-]*)\s+(?:$(& $alt $problems[$kind]))\s*(?<b>.+)$")
        if (-not $match.Success) { continue }
        $holding = Read-LambekHolding -Sentence "$($match.Groups['head'].Value) $($match.Groups['n'].Value) $($match.Groups['noun'].Value)" -Language $Language -Listener:$Listener
        $other = Get-LambekProblemHolder -Written $match.Groups['b'].Value.Trim() -Language $Language -Listener:$Listener
        if (-not $holding -or -not $other -or $other.Key -eq 'all') { return $null }
        return [pscustomobject]@{ Kind = 'difference'; Holder = $holding.Holder; Other = $other; Number = $holding.Number; Fewer = ($kind -eq 'Fewer'); Noun = $holding.Noun; NounKey = $holding.NounKey }
    }

    # "Paul a 14 ans"
    $holding = Read-LambekHolding -Sentence $Sentence -Language $Language -Listener:$Listener
    if (-not $holding) { return $null }
    return [pscustomobject]@{ Kind = 'value'; Holder = $holding.Holder; Number = $holding.Number; Noun = $holding.Noun; NounKey = $holding.NounKey }
}

function Get-LambekQuantitySignature {
    param([pscustomobject] $Item)

    # What a sentence of a problem says, to see that it reads the same when said back
    $holders = @(); if ($Item.PSObject.Properties['Holders']) { $holders = @($Item.Holders | ForEach-Object { $_.Key }) }
    $one = ''; if ($Item.PSObject.Properties['Holder'] -and $Item.Holder) { $one = $Item.Holder.Key }
    $other = ''; if ($Item.PSObject.Properties['Other'] -and $Item.Other) { $other = $Item.Other.Key }
    $fewer = $Item.PSObject.Properties['Fewer'] -and $Item.Fewer
    return "$($Item.Kind)|$one|$other|$($holders -join ',')|$($Item.Number.Exact())|$($Item.NounKey)|$fewer"
}

function Get-LambekProblemSaid {
    param([pscustomobject] $Item, [string] $Language, [switch] $Place)

    # A sentence of the problem said back, turned to the other side ("j'ai" is "vous avez"), kept only when reading it
    # again gives the same; otherwise quoted as it was written
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    if ($Place) { return "$($Item.Original)".TrimEnd('.') + '.' }
    $sentence = ConvertTo-LambekOtherSide -Text "$($Item.Original)" -Language $Language -Register 'vous'
    if ($sentence) {
        $problems = (Get-LambekLexicon -Language $Language).Dialogue['Problems']
        $again = $sentence.TrimEnd('.')
        foreach ($rule in @($problems['Rewrite'])) { $again = [regex]::Replace($again, $rule[0], $rule[1]) }
        $read = Read-LambekQuantitySentence -Sentence $again -Language $Language -Listener
        if ($read -and (Get-LambekQuantitySignature -Item $read) -eq (Get-LambekQuantitySignature -Item $Item)) { return $sentence }
    }
    return ($say['Quote'] -f "$($Item.Original)".Trim()) + '.'
}

function Get-LambekProblemShown {
    param([pscustomobject] $Holder, [string] $Language)

    # The name of one who has, in an equation: "vous", "Marie", "votre soeur"
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    if ($Holder.Key -eq 'speaker') { return $say['Speaker'] }
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $side = $general['OtherSide']
    $words = foreach ($word in ($Holder.Written -split '\s+')) {
        $plain = ConvertTo-LambekNormalizedText -Text $word
        if ($side -and $side['Words'] -and $side['Words'].Contains($plain)) { $side['Words'][$plain] } else { $word }
    }
    $shown = ($words -join ' ')
    # ("Un pere" at the start of the sentence is "un pere" inside an equation; a name keeps its capital)
    if (@($words).Count -gt 1 -and (ConvertTo-LambekNormalizedText -Text @($words)[0]) -in @($general['Determiners'])) { $shown = $shown.Substring(0, 1).ToLowerInvariant() + $shown.Substring(1) }
    return $shown
}

function Resolve-LambekQuantityProblem {
    param([object[]] $Items, [string] $Language, [System.Collections.IDictionary] $Problems)

    $lexicon = Get-LambekLexicon -Language $Language
    $say = $lexicon.Dialogue.Say
    $store = Get-LambekProblemStore
    $relations = @($Items | Where-Object { $_.Kind -in 'difference', 'ratio', 'sum' })
    $questions = @($Items | Where-Object { $_.Kind -eq 'question' })
    $kept = @($store | Where-Object { $_.Kind -in 'difference', 'ratio', 'sum', 'value' })
    # Nothing that links two quantities, here or before: a number told or asked is for the rest of Lambek
    if ($relations.Count -eq 0 -and @($kept | Where-Object { $_.Kind -ne 'value' }).Count -eq 0) { return $null }
    if ($questions.Count -gt 1) { return $null }
    # Told without a question: kept, and said back
    if ($questions.Count -eq 0) {
        $said = foreach ($item in $Items) { $store.Add($item); Get-LambekProblemSaid -Item $item -Language $Language }
        return [pscustomobject]@{ Language = $Language; Reply = ($say['Noted'] -f (@($said) -join ' ')) }
    }
    $question = $questions[0]
    $all = @($kept) + @($Items | Where-Object { $_.Kind -ne 'question' })

    # The quantities: one for each one who has and each thing had
    $names = [ordered]@{}
    $noun = $question.NounKey
    $add = { param($holder, $key) $name = "$($holder.Key)|$key"; if (-not $names.Contains($name)) { $names[$name] = $holder }; $name }
    foreach ($item in $all) {
        if ($item.NounKey -ne $noun) { continue }
        if ($item.Kind -eq 'sum') { foreach ($holder in @($item.Holders)) { if ($holder.Key -ne 'all') { [void] (& $add $holder $noun) } } }
        else {
            [void] (& $add $item.Holder $noun)
            if ($item.PSObject.Properties['Other'] -and $item.Other) { [void] (& $add $item.Other $noun) }
        }
    }
    $asked = $question.Asked
    $askedHolders = @()
    if ($asked.Holder -eq 'all' -or ($asked.Total -and -not $asked.Direction)) { $askedHolders = @($names.Keys) }
    else {
        $one = $(if ($asked.Holder -eq 'speaker') { Get-LambekProblemHolder -Written '' -Language $Language -Speaker } else { Get-LambekProblemHolder -Written "$($asked.Name)" -Language $Language })
        if (-not $one -or $one.Key -eq 'all') { return $null }
        $askedHolders = @(& $add $one $noun)
        if ($asked.Direction) {
            $two = Get-LambekProblemHolder -Written "$($asked.Compare)" -Language $Language
            if (-not $two) { return $null }
            $askedHolders += & $add $two $noun
        }
    }
    if ($names.Count -lt 1) { return $null }

    # The numbers told before, as things told ("j'ai 3 chats"), for the quantities of the problem: the last one of each
    $told = @(@((Get-LambekToldJournal).ToArray()) + @((Get-LambekTold).ToArray()))
    $toldUsed = [ordered]@{}
    foreach ($fact in $told) {
        if ($fact.PSObject.Properties['Condition'] -and $fact.Condition) { continue }
        if ("$($fact.Language)" -ne $Language -or -not $fact.Text) { continue }
        $holding = Read-LambekHolding -Sentence "$($fact.Text)" -Language $Language
        if (-not $holding -or $holding.NounKey -ne $noun) { continue }
        $name = "$($holding.Holder.Key)|$noun"
        if ($names.Contains($name)) { $toldUsed[$name] = [pscustomobject]@{ Fact = $fact; Number = $holding.Number } }
    }

    # The equations, each with how it is shown
    $shown = @{}
    foreach ($name in $names.Keys) { $shown[$name] = Get-LambekProblemShown -Holder $names[$name] -Language $Language }
    $equations = [System.Collections.Generic.List[object]]::new()
    $one = [LambekRational]::One
    $minusOne = [LambekRational]::new(-1, 1)
    $make = { param([string[]] $n, [object[]] $c, $k, [string] $show, [string[]] $parts) [pscustomobject]@{ Equation = [LambekProblemEquation]::Make($n, [LambekRational[]] $c, $k); Show = $show; Parts = $parts } }
    $num = { param($q) Format-LambekNumber -Number $q.Exact() -Language $Language }
    $valued = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($item in $all) { if ($item.Kind -eq 'value' -and $item.NounKey -eq $noun) { [void] $valued.Add("$($item.Holder.Key)|$noun") } }
    foreach ($name in $toldUsed.Keys) {
        if ($valued.Contains($name)) { continue }
        $equations.Add((& $make @($name) @($one) $toldUsed[$name].Number "{0} = $(& $num $toldUsed[$name].Number)" @($name)))
    }
    foreach ($item in $all) {
        if ($item.NounKey -ne $noun) { continue }
        switch ($item.Kind) {
            'value' {
                $a = "$($item.Holder.Key)|$noun"
                $equations.Add((& $make @($a) @($one) $item.Number "{0} = $(& $num $item.Number)" @($a)))
            }
            'difference' {
                $a = "$($item.Holder.Key)|$noun"; $b = "$($item.Other.Key)|$noun"
                $sign = $(if ($item.Fewer) { '-' } else { '+' })
                $constant = $(if ($item.Fewer) { [LambekRational]::Zero - $item.Number } else { $item.Number })
                $equations.Add((& $make @($a, $b) @($one, $minusOne) $constant "{0} = {1} $sign $(& $num $item.Number)" @($a, $b)))
            }
            'ratio' {
                $a = "$($item.Holder.Key)|$noun"; $b = "$($item.Other.Key)|$noun"
                $times = [char] 0x00D7
                if ($item.Fewer) { $equations.Add((& $make @($b, $a) @($one, ([LambekRational]::Zero - $item.Number)) ([LambekRational]::Zero) "{0} = $(& $num $item.Number) $times {1}" @($b, $a))) }
                else { $equations.Add((& $make @($a, $b) @($one, ([LambekRational]::Zero - $item.Number)) ([LambekRational]::Zero) "{0} = $(& $num $item.Number) $times {1}" @($a, $b))) }
            }
            'sum' {
                $members = @(if (@($item.Holders | Where-Object { $_.Key -eq 'all' }).Count -gt 0) { @($names.Keys) } else { @($item.Holders | ForEach-Object { "$($_.Key)|$noun" }) })
                if ($members.Count -lt 2) { return $null }
                $places = @(for ($k = 0; $k -lt $members.Count; $k++) { "{$k}" })
                $equations.Add((& $make $members @($members | ForEach-Object { $one }) $item.Number "$($places -join ' + ') = $(& $num $item.Number)" $members))
            }
        }
    }
    if ($equations.Count -eq 0) { return $null }
    $solution = [LambekProblems]::Solve([LambekProblemEquation[]] @($equations | ForEach-Object { $_.Equation }))

    $render = { param($eq, $values) $eq.Show -f @($eq.Parts | ForEach-Object { if ($values) { & $num $values[$_] } else { $shown[$_] } }) }
    $lines = [System.Collections.Generic.List[string]]::new()
    $said = @(foreach ($item in @($all | Where-Object { $_.NounKey -eq $noun })) { Get-LambekProblemSaid -Item $item -Language $Language })
    foreach ($item in $Items) { if ($item.Kind -ne 'question') { $store.Add($item) } }
    if ($solution.Kind -eq 'none') {
        $lines.Add($Problems['Contradiction'])
        foreach ($index in $solution.Conflict) { $lines.Add("- $(& $render $equations[$index] $null)") }
        Set-LambekLastProof
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n") }
    }
    $missing = @($askedHolders | Where-Object { -not $solution.Values.ContainsKey($_) })
    $equationLines = @($equations | ForEach-Object { "- $(& $render $_ $null)" })
    if ($missing.Count -gt 0) {
        $lines.Add(($Problems['Missing'] -f $shown[$missing[0]]))
        $lines.Add($Problems['Equations'])
        foreach ($line in $equationLines) { $lines.Add($line) }
        Set-LambekLastProof
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n") }
    }

    # The answer, as a sentence of the user's own turned to the other side, then the others found on the way
    $sentence = {
        param($name)
        $holder = $names[$name]
        $value = & $num $solution.Values[$name]
        $says = $Problems['Says']
        if ($Problems['AgeSays'] -and $noun -eq (Get-LambekProblemNoun -Noun "$($Problems['Age'])" -Language $Language)) { $says = $Problems['AgeSays'] }
        $form = $(if ($holder.Key -eq 'speaker') { $says['speaker'] } else { $says['other'] })
        $nounSaid = $question.Asked.Noun
        $mine = $form -f $holder.Written, $value, $nounSaid
        $turned = ConvertTo-LambekOtherSide -Text $mine -Language $Language -Register 'vous'
        if ($turned) { return $turned }
        return "$($shown[$name]) : $value $nounSaid."
    }
    if ($asked.Direction) {
        $difference = $solution.Values[$askedHolders[0]] - $solution.Values[$askedHolders[1]]
        $size = $(if ($difference.CompareTo([LambekRational]::Zero) -lt 0) { [LambekRational]::Zero - $difference } else { $difference })
        $template = $(if ($difference.IsZero) { 'CountSame' } elseif ($difference.CompareTo([LambekRational]::Zero) -gt 0) { 'CountMore' } else { 'CountFewer' })
        $first = $say[$template] -f (& $num $size), $asked.Noun
        $lines.Add($first.Substring(0, 1).ToUpperInvariant() + $first.Substring(1))
    }
    elseif ($askedHolders.Count -gt 1) {
        $total = [LambekRational]::Zero
        foreach ($name in $askedHolders) { $total = $total + $solution.Values[$name] }
        $lines.Add(($say['CountTotal'] -f (& $num $total), $asked.Noun))
    }
    else { $lines.Add((& $sentence $askedHolders[0])) }
    foreach ($name in $names.Keys) {
        if ($name -in $askedHolders -or -not $solution.Values.ContainsKey($name)) { continue }
        $lines.Add((($Problems['Also'] -f (Format-LambekInline -Text (& $sentence $name) -Language $Language)) + '.'))
    }
    $lines.Add($Problems['Equations'])
    foreach ($line in $equationLines) { $lines.Add($line) }
    # Every value put back in every equation: what is said is checked, not believed
    $mark = [char] 0x2713
    $checks = foreach ($eq in $equations) {
        if (-not $eq.Equation.Holds($solution.Values)) { throw "A value found does not keep the equation $(& $render $eq $null)." }
        # (a value given is not checked against itself)
        if (@($eq.Parts).Count -gt 1) { "$(& $render $eq $solution.Values) $mark" }
    }
    $lines.Add(($Problems['Check'] -f (@($checks) -join ' ; ')))
    foreach ($name in $askedHolders) {
        $value = $solution.Values[$name]
        if (-not $value.IsInteger -and $noun -ne (Get-LambekProblemNoun -Noun "$($Problems['Age'])" -Language $Language)) { $lines.Add(($Problems['NotWhole'] -f (& $num $value))) }
        elseif ($value.CompareTo([LambekRational]::Zero) -lt 0) { $lines.Add(($Problems['Negative'] -f (& $num $value))) }
    }
    $facts = @($toldUsed.Values | ForEach-Object { $_.Fact })
    Set-LambekLastProof -Facts $facts -Said $said -Calculation (@($equations | ForEach-Object { & $render $_ $null }) -join ' ; ')
    return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n") }
}

function Read-LambekPlaceSentence {
    param([string] $Sentence, [string] $Language, [switch] $Question)

    # One sentence of a problem of places: who is in the row, where one is, or a question about the row
    $places = (Get-LambekLexicon -Language $Language).Dialogue['Problems']['Places']
    $name = '\p{Lu}[\p{Ll}\p{Lu}-]*'
    $alt = { param($list) (@($list | Where-Object { $_ } | Sort-Object { -$_.Length } | ForEach-Object { ConvertTo-LambekPhrasePattern -Phrase $_ }) -join '|') }

    # "dans quel ordre sont-ils assis ?"
    if ([regex]::IsMatch($Sentence, "(?i)$(& $alt $places['Order'])")) { return [pscustomobject]@{ Kind = 'placequestion'; Ask = 'order' } }
    # "ou est assise Alice ?"
    $where = Find-LambekPhraseAtStart -Text $Sentence -Phrases @($places['WhereIs'])
    if ($where) {
        $who = @([regex]::Matches($where.Rest, $name) | ForEach-Object { $_.Value })
        if ($who.Count -ne 1) { return $null }
        return [pscustomobject]@{ Kind = 'placequestion'; Ask = 'where'; Name = $who[0] }
    }
    # "qui est au milieu ?"
    $who = Find-LambekPhraseAtStart -Text $Sentence -Phrases @($places['Who'])
    if ($who) {
        $relation = Read-LambekPlaceRelation -Text $who.Rest -Places $places -Name $name
        if (-not $relation) { return $null }
        return [pscustomobject]@{ Kind = 'placequestion'; Ask = 'who'; Relation = $relation }
    }
    if ($Question) { return $null }
    # "Alice, Bob et Chloe sont assis sur un banc"
    $row = [regex]::Match($Sentence, "(?i)$(& $alt $places['Row'])")
    if ($row.Success) {
        $before = $Sentence.Substring(0, $row.Index)
        $and = (@($places['And']) | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $people = @([regex]::Split($before.Trim(), "\s*,\s*|\s+(?:$and)\s+") | Where-Object { $_ })
        if ($people.Count -ge 2 -and @($people | Where-Object { $_ -cnotmatch "^$name$" }).Count -eq 0) { return [pscustomobject]@{ Kind = 'setup'; People = $people } }
        return $null
    }
    # "Alice n'est pas a cote de Bob", "Chloe est juste a gauche d'Alice"
    $first = [regex]::Match($Sentence, "^(?<a>$name)\s+(?<rest>.+)$")
    if (-not $first.Success) { return $null }
    $negated = $false
    $verb = Find-LambekPhraseAtStart -Text $first.Groups['rest'].Value -Phrases @($places['Not'])
    if ($verb) { $negated = $true } else { $verb = Find-LambekPhraseAtStart -Text $first.Groups['rest'].Value -Phrases @($places['Is']) }
    if (-not $verb) { return $null }
    $relation = Read-LambekPlaceRelation -Text $verb.Rest -Places $places -Name $name
    if (-not $relation) { return $null }
    $relation.Negated = $negated
    $relation.A = $first.Groups['a'].Value
    return [pscustomobject]@{ Kind = 'place'; Relation = $relation }
}

function Read-LambekPlaceRelation {
    param([string] $Text, [System.Collections.IDictionary] $Places, [string] $Name)

    # Where: "a cote de Bob", "juste a gauche d'Alice", "entre Bob et Chloe", "au milieu", "tout a droite"
    $just = Find-LambekPhraseAtStart -Text $Text -Phrases @($Places['Just'])
    if ($just) { $Text = $just.Rest }
    $and = (@($Places['And']) | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $make = { param($kind, $b, $c, $position) [pscustomobject]@{ Kind = $kind; A = $null; B = $b; C = $c; Position = $position; Negated = $false } }
    $between = Find-LambekPhraseAtStart -Text $Text -Phrases @($Places['Between'])
    if ($between) {
        $two = [regex]::Match($between.Rest, "^(?<b>$Name)\s+(?:$and)\s+(?<c>$Name)$")
        if ($two.Success -and -not $just) { return & $make 'between' $two.Groups['b'].Value $two.Groups['c'].Value 0 }
        return $null
    }
    foreach ($pair in @(@('Left', 'left'), @('Right', 'right'), @('Next', 'next'))) {
        $found = Find-LambekPhraseAtStart -Text $Text -Phrases @($Places[$pair[0]])
        if (-not $found) { continue }
        if ($found.Rest -cnotmatch "^$Name$") { return $null }
        $kind = $pair[1]
        if ($just -and $kind -ne 'next') { $kind = "just$kind" }
        return & $make $kind $found.Rest $null 0
    }
    if ($just) { return $null }
    foreach ($pair in @(@('Middle', 'middle', 0), @('End', 'end', 0), @('First', 'at', 1), @('Last', 'last', 0), @('LeftAlone', 'at', 1), @('RightAlone', 'last', 0))) {
        $found = Find-LambekPhraseAtStart -Text $Text -Phrases @($Places[$pair[0]])
        if ($found -and -not $found.Rest) { return & $make $pair[1] $null $null $pair[2] }
    }
    return $null
}

function Resolve-LambekPlaceProblem {
    param([object[]] $Items, [string] $Language, [System.Collections.IDictionary] $Problems)

    $places = $Problems['Places']
    $store = Get-LambekProblemStore
    $all = @(@($store | Where-Object { $_.Kind -in 'setup', 'place' }) + @($Items | Where-Object { $_.Kind -ne 'placequestion' }))
    $questions = @($Items | Where-Object { $_.Kind -eq 'placequestion' })
    if ($questions.Count -gt 1) { return $null }
    $conditions = @($all | Where-Object { $_.Kind -eq 'place' })
    $setups = @($all | Where-Object { $_.Kind -eq 'setup' })
    if ($conditions.Count -eq 0 -and $setups.Count -eq 0) { return $null }
    # (one place told alone, "Paris est a cote de Versailles", is a thing told, not a problem)
    if ($setups.Count -eq 0 -and $questions.Count -eq 0 -and $conditions.Count -lt 2) { return $null }
    # Who is in the row: as told, else everyone named
    $people = [System.Collections.Generic.List[string]]::new()
    if ($setups.Count -gt 0) { foreach ($one in $setups[-1].People) { if (-not $people.Contains($one)) { $people.Add($one) } } }
    else {
        foreach ($condition in $conditions) { foreach ($one in @($condition.Relation.A, $condition.Relation.B, $condition.Relation.C)) { if ($one -and -not $people.Contains($one)) { $people.Add($one) } } }
        foreach ($question in $questions) { if ($question.PSObject.Properties['Name'] -and $question.Name -and -not $people.Contains($question.Name)) { $people.Add($question.Name) } }
    }
    if ($people.Count -lt 2 -or $people.Count -gt 8) { return $null }
    $made = @(foreach ($condition in $conditions) {
            $r = $condition.Relation
            foreach ($one in @($r.A, $r.B, $r.C)) { if ($one -and -not $people.Contains($one)) { return $null } }
            [LambekPlace]::Make($r.Kind, $r.A, $r.B, $r.C, [int] $r.Position, [bool] $r.Negated)
        })
    $separator = $places['Separator']
    $and = " $(@($places['And'])[0]) "
    $listed = { param([string[]] $order) $order -join $separator }
    $result = [LambekProblems]::Arrange([string[]] $people.ToArray(), [LambekPlace[]] $made, 6)
    foreach ($item in $Items) { if ($item.Kind -ne 'placequestion') { $store.Add($item) } }
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($result.Count -eq 0) {
        $lines.Add($places['None'])
        foreach ($index in $result.Conflict) { $lines.Add("- $(Get-LambekProblemSaid -Item $conditions[$index] -Language $Language -Place)") }
        Set-LambekLastProof
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n") }
    }
    if ($questions.Count -eq 0) {
        $lines.Add((Format-LambekPlural -Template $places['Noted'] -Language $Language -Values @([int] $result.Count, [int] $result.Tried)))
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n") }
    }
    $question = $questions[0]
    # What the question asks, in each order kept: the same in all of them, or it cannot be known
    $answerOf = {
        param([string[]] $order)
        switch ($question.Ask) {
            'order' { return (& $listed $order) }
            'where' { return [string] ([array]::IndexOf($order, $question.Name) + 1) }
            'who' {
                $at = [System.Collections.Generic.Dictionary[string, int]]::new()
                for ($i = 0; $i -lt $order.Length; $i++) { $at[$order[$i]] = $i }
                $r = $question.Relation
                $found = @(foreach ($one in $order) {
                        if ($one -eq $r.B -or $one -eq $r.C) { continue }
                        $test = [LambekPlace]::Make($r.Kind, $one, $r.B, $r.C, [int] $r.Position, $false)
                        if ($test.Holds($at, $order.Length)) { $one }
                    })
                return ($found -join $and)
            }
        }
    }
    # (every order is looked at, not only the ones kept to be shown)
    $every = [LambekProblems]::Arrange([string[]] $people.ToArray(), [LambekPlace[]] $made, 40320)
    $answers = @($every.Orders | ForEach-Object { & $answerOf $_ } | Select-Object -Unique)
    $proof = @($conditions | ForEach-Object { Get-LambekProblemSaid -Item $_ -Language $Language -Place })
    if ($answers.Count -eq 1 -and $answers[0]) {
        switch ($question.Ask) {
            'order' { $lines.Add(($places['Order1'] -f $answers[0])) }
            'where' { $lines.Add(($places['Where1'] -f $question.Name, $answers[0], $people.Count)) }
            'who' { $lines.Add(($places['Who1'] -f $answers[0])) }
        }
        if ($result.Count -eq 1) {
            if ($question.Ask -eq 'order') { $lines.Add(($places['OnlyOrder'] -f $result.Tried)) }
            else { $lines.Add(($places['Only'] -f (& $listed $result.Orders[0]), $result.Tried)) }
        }
        else { $lines.Add(($places['Always'] -f $result.Count)) }
        Set-LambekLastProof -Said $proof -Calculation (@($every.Orders | ForEach-Object { & $listed $_ }) -join ' ; ')
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n") }
    }
    $lines.Add(($places['Several'] -f $result.Count))
    foreach ($order in $result.Orders) { $lines.Add("- $(& $listed $order)") }
    $lines.Add($places['More'])
    Set-LambekLastProof
    return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n") }
}
