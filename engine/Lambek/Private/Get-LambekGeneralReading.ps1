function Get-LambekGeneralReading {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        # Read as the one spoken to: "you bought a car" is then about the user, as when Lambek says it back
        [switch] $Listener,

        # Read as a question that asks whether: "est-ce que ma soeur habite a Lyon", its first word left out
        [switch] $Whether,

        # Read once, as it stands (the function calls itself with this, to try another reading after the first)
        [switch] $Once
    )

    # A sentence about anything, read with the same pregroup grammar as an order, each word typed by what it was read as:
    # a noun is n, a verb takes its subject on the left (n^r s) and maybe an object on the right (n^r s n^l),
    # "my" and "the" make a noun of a noun (n n^l), "in" adds a place to the sentence (s^r s n^l).
    # When the words reduce to s, the cancellations say who does what, to what, where. Nothing is guessed:
    # a sentence that does not reduce, has two verbs, or says "not", gives nothing
    $language = $Request.Language
    $lexicon = Get-LambekLexicon -Language $language
    $general = $null
    if ($lexicon.Dialogue) { $general = $lexicon.Dialogue['General'] }
    if (-not $general) { return $null }
    # What each word may be: read by the forms Lambek learned, in this very sentence
    $dictionary = Get-LambekSentenceReading -Text "$($Request.Original)" -Language $language
    if (-not $dictionary) { return $null }

    # The words as they were typed: a word corrected towards a word of a pack ("live" read as "move") is not the word said
    $typedAs = Read-LambekRequest -Text (Repair-LambekPhrase -Text "$($Request.Original)") -Original "$($Request.Original)" -Language $language
    $tokens = @($typedAs.Tokens)
    if ($tokens.Count -lt 2 -or $tokens.Count -gt 16) { return $null }

    # "que fait ma soeur" asks what; "(est-ce) que ma soeur habite a Lyon" asks whether. The first reading is tried,
    # then the second: the grammar decides, the word alone cannot
    $marks = @($general['PolarMark'])
    if (-not $Once -and -not $Whether -and $tokens[0] -in $marks) {
        # The word that asks what comes before its verb ("que fait..."); before a subject ("que je travaille...",
        # "que ma soeur...") it only marks the question whether
        $subjectNext = $tokens[1] -in @($general['Speakers']) -or $tokens[1] -in @($general['Determiners']) -or $tokens[1] -in @($general['Pronouns'])
        if (-not $subjectNext) {
            $what = Get-LambekGeneralReading -Request $Request -Listener:$Listener -Once
            if ($what) { return $what }
        }
        return Get-LambekGeneralReading -Request $Request -Listener:$Listener -Whether -Once
    }
    # "why does my sister live in Lyon": the question whether, asking for its reason
    $why = $tokens[0] -in @($general['Why'])
    if ($why -and -not $Whether -and -not $Once) {
        $reading = Get-LambekGeneralReading -Request $Request -Listener:$Listener -Whether -Once
        if ($reading -and $reading.Kind -eq 'question') { $reading.Asked = 'reason' }
        return $reading
    }
    # "does my sister live in Lyon", "is Lyon in France": the verb that helps comes first, and the sentence asks whether
    $whether = [bool] $Whether -or (-not $Listener -and $tokens[0] -in @($general['Polar']))
    $questions = @($general['What']) + @($general['WhatObject']) + @($general['WhatSubject']) | Where-Object { $_ }
    $asks = $tokens[0] -in $questions -or $tokens[0] -in @($general['Where'])
    # "I do not like coffee", "je n'aime pas le cafe": the sentence is read without its negation, and said to be negative.
    # In French the "ne" makes it one ("plus" alone is "more"); a question in the negative is not read yet
    $denied = @($general['Negations'])
    $needs = @($general['NegationNeeds'])
    $negated = @($tokens | Where-Object { $_ -in $denied }).Count -gt 0
    if ($negated -and $needs.Count -gt 0 -and @($tokens | Where-Object { $_ -in $needs }).Count -eq 0) { $negated = $false }
    if ($negated -and ($asks -or $whether)) { return $null }
    # "I want the newest", "je voudrais...": a wish is a way to ask, not something told
    if (@($tokens | Where-Object { $_ -in @($lexicon.Dialogue['Wishes']) }).Count -gt 0) { return $null }
    # "what time is it", "she moved": who or what "it" and "she" are would have to come from the sentences before
    # A pronoun is read as the one it stands for, found among what was told; only as the subject for now
    $features = @{}
    if ($general['PronounFeatures']) { $features = $general['PronounFeatures'] }
    if (@($tokens | Where-Object { $_ -in @($general['Pronouns']) -and -not $features.Contains($_) }).Count -gt 0) { return $null }
    # "who are you", "what can you do": what is said to Lambek about itself is answered elsewhere
    $first = @($general['Speakers'])
    $second = @($general['Addressee'])
    if ($Listener) { $first = @($general['Addressee']); $second = @($general['Speakers']) }
    if (@($tokens | Where-Object { $_ -in $second }).Count -gt 0) { return $null }
    # "what time is it", "which file...": a question word before a noun is not read yet
    $next = @($tokens | Select-Object -Skip 1 | Where-Object { $_ -notin @($general['Skipped']) -and $_ -notin $marks } | Select-Object -First 1)
    # ("qu'est-ce que ma soeur a achete": after "est-ce que" comes a whole sentence, its subject first)
    $announced = $tokens.Count -gt 1 -and $tokens[1] -in $marks
    if (-not $Whether -and -not $announced -and $next.Count -gt 0 -and $tokens[0] -in $questions -and $next[0] -notin @($general['Auxiliaries']) -and $next[0] -notin @($general['Speakers'])) {
        $follows = @($dictionary.Lemmas($next[0], $language) | ForEach-Object { $_.Pos })
        if ('v' -notin $follows) { return $null }
    }
    # "why", "because", "and": a reason or two sentences in one are not read yet
    if (@($tokens | Where-Object { $_ -in @($general['Unread']) }).Count -gt 0) { return $null }

    # Words of time said in several words count as one
    $timeAt = @{}
    $times = @()
    if ($lexicon.Dialogue['Times']) { $times = @($lexicon.Dialogue['Times'].Keys | Sort-Object { -$_.Length }, { $_ }) }
    foreach ($phrase in $times) {
        $parts = @($phrase -split ' ')
        for ($i = 0; $i -le $tokens.Count - $parts.Count; $i++) {
            if ($timeAt.ContainsKey($i) -or ($tokens[$i..($i + $parts.Count - 1)] -join ' ') -ne $phrase) { continue }
            $timeAt[$i] = 'first'
            for ($k = 1; $k -lt $parts.Count; $k++) { $timeAt[$i + $k] = 'rest' }
        }
    }

    # The types each word may have: the small words from the language file, the others from what the word was read as
    $typed = [System.Collections.Generic.List[object]]::new()
    $kinds = @{}
    $lemmas = @{}
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        if ($timeAt[$i] -eq 'rest' -or $token -in @($general['Skipped'])) { continue }
        if ($negated -and $token -in $denied) { continue }
        # "(est-ce) que ...", "ou (est-ce) que ...": the "que" that only announces the sentence
        if ($token -in $marks -and (($i -eq 0 -and $Whether) -or ($i -eq 1 -and $asks))) { continue }
        # "why", "pourquoi" asks for the reason of what follows; "pourquoi est-ce que" too
        if ($Whether -and $token -in @($general['Why']) -and $i -eq 0) { continue }
        if ($Whether -and $token -in $marks -and $i -eq 1 -and $tokens[0] -in @($general['Why'])) { continue }
        # "vous vous appelez": the second one goes with the verb, as "m'" does in "je m'appelle"
        if ($Listener -and $i -gt 0 -and $token -in $first -and $tokens[$i - 1] -eq $token) { continue }
        # "votre patron vous appelle", "ma soeur nous voit": after the subject and before the verb, "vous" is the one the
        # verb is about, said before it as "me" and "te" are, and goes with the verb
        # (the word before it ends the subject: a noun or a name, never a word of time, "hier vous avez achete")
        if ($i -gt 0 -and $i -lt $tokens.Count - 1 -and $token -in @($general['ObjectClitics']) -and -not $timeAt.ContainsKey($i - 1) -and
            $tokens[$i - 1] -notin @($general['Prepositions']) -and $tokens[$i - 1] -notin @($general['ObjectClitics']) -and
            (@($dictionary.Lemmas($tokens[$i - 1], $language) | Where-Object { $_.Pos -eq 'n' }).Count -gt 0 -or (Get-LambekWritten -Request $typedAs -Words @($tokens[$i - 1])) -cmatch '^\p{Lu}') -and
            @($dictionary.Lemmas($tokens[$i + 1], $language) | Where-Object { $_.Pos -eq 'v' }).Count -gt 0) { continue }
        $types = [System.Collections.Generic.List[string]]::new()
        $kind = 'word'
        if ($timeAt[$i] -eq 'first') { $kind = 'time'; $types.AddRange([string[]] @('s^r s', 's s^l')) }
        # ("two brothers": a number goes with its noun as an article does, or stands alone)
        elseif ($token -eq '_number_') { $types.AddRange([string[]] @('n n^l', 'n')) }
        elseif ($token -match '^_[a-z]+_$') { $types.Add('n') }
        elseif ($token -in @($general['Where'])) { $kind = 'where'; $types.Add('s s^l') }
        elseif ($token -in @($general['What'])) { $kind = 'what'; $types.AddRange([string[]] @('s n^ll s^l', 's s^l n')) }
        # "que", "comment" ask for what the verb takes; "qui", "quel" for the one who does it
        elseif ($token -in @($general['WhatObject'])) { $kind = 'what'; $types.Add('s n^ll s^l') }
        elseif ($token -in @($general['WhatSubject'])) { $kind = 'what'; $types.Add('s s^l n') }
        elseif ($token -in $first -or $token -in $second -or $token -in @($general['Pronouns'])) { $kind = 'pronoun'; $types.Add('n') }
        # ("la liste des courses", "the name of my cat": a word that links a noun to another noun, n^r n n^l)
        elseif ($token -in @($general['Determiners'])) { $types.Add('n n^l'); if ($token -in @($general['NounLinks'])) { $types.Add('n^r n n^l') } }
        # ("a" is "to" and "has": a word of place that also helps a verb is read both ways, the grammar chooses)
        elseif ($token -in @($general['Prepositions']) -and $token -notin @($general['Auxiliaries'])) {
            $kind = 'preposition'
            $types.AddRange([string[]] @('s^r s n^l', 's s^l n^l'))
            if ($token -in @($general['NounLinks'])) { $types.Add('n^r n n^l') }
        }
        else {
            $found = @($dictionary.Lemmas($token, $language))
            $pos = @($found | ForEach-Object { $_.Pos } | Select-Object -Unique)
            if ($token -in @($general['Auxiliaries'])) { $kind = 'auxiliary'; $types.AddRange([string[]] @('n^r n', 'n n^l')) }
            if ('v' -in $pos -or $token -in @($general['Verbs'])) {
                $types.AddRange([string[]] @('n^r s', 'n^r s n^l'))
                # In a question the subject may come after the verb ("ou habite ma soeur", "is Lyon in France"):
                # the verb then takes it on its right (s n^l), after what it asks for when it asks for something (s n^l n^l)
                if ($asks -or $whether) { $types.AddRange([string[]] @('s n^l', 's n^l n^l')) }
                # ("suis" is "etre" before it is "suivre": a verb that also helps the others is read as itself)
                $helps = @($found | Where-Object { $_.Pos -like 'aux*' } | ForEach-Object { $_.Lemma })
                $verb = @(@($found | Where-Object { $_.Pos -eq 'v' -and $_.Lemma -in $helps }) + @($found | Where-Object { $_.Pos -eq 'v' }) | Select-Object -First 1)
                $lemmas[$i] = $(if ($verb.Count -gt 0) { if ($verb[0].Shown) { $verb[0].Shown } else { $verb[0].Lemma } } else { $token })
            }
            # A word no dictionary knows is a name only when it is written like one ("Amin", "Felix")
            if ($pos.Count -eq 0 -and $kind -eq 'word' -and (Get-LambekWritten -Request $typedAs -Words @($token)) -cnotmatch '^\p{Lu}') { return $null }
            # (a verb that helps the others is never a noun: "est" is not "the east" in "mon frere est content")
            if (('n' -in $pos -or $pos.Count -eq 0) -and $kind -ne 'auxiliary') { $types.Add('n') }
            if ('a' -in $pos) { $types.AddRange([string[]] @('n n^l', 'n^r n')); if ('n' -notin $pos) { $types.Add('n') } }
            if ('r' -in $pos) { $types.AddRange([string[]] @('s^r s', 's s^l')) }
            if ('det' -in $pos) { $types.Add('n n^l') }
            if ('prep' -in $pos -and $kind -eq 'word') { $types.AddRange([string[]] @('s^r s n^l', 's s^l n^l')) }
            if ($token -in @($general['Prepositions'])) { $types.AddRange([string[]] @('s^r s n^l', 's s^l n^l')) }
            if ($types.Count -eq 0) { $types.Add('n') }
        }
        $kinds[$i] = $kind
        $typed.Add([pscustomobject]@{ Word = $token; Position = $i; Candidates = [string[]] @($types | Select-Object -Unique) })
    }
    if ($typed.Count -lt 2) { return $null }

    $root = Invoke-LambekChart -TypedWords $typed -Keep 16 -Fuel 400000 -SentenceOnly
    if (-not $root.ContainsKey('s|0')) { return $null }

    # Several readings may reduce to s ("I am tired": "am" helps "tired", or "am" is the verb). Each is read;
    # the first that says something wins, one whose verb is a real verb before one whose verb is "be" or "have"
    $readings = @(foreach ($choice in $root['s|0']) { Get-LambekGeneralChoice -Request $typedAs -Typed $typed -Choice $choice -Kinds $kinds -Lemmas $lemmas -General $general -First $first -Whether:$whether -Question:($asks -or $whether) })
    foreach ($reading in $readings) { if ($reading -and $reading.Kind -ne 'unresolved') { $reading | Add-Member -NotePropertyName Negated -NotePropertyValue $negated -Force } }
    $readings = @($readings | Where-Object { $_ })
    if ($readings.Count -eq 0) { return $null }
    $whole = @($readings | Where-Object { $_.Kind -ne 'unresolved' })
    if ($whole.Count -eq 0) { return $readings[0] }
    $readings = $whole
    # A question that asks whether asks about every word it has: with the same verb, the reading that keeps the most
    # complements wins ("is my brother happy" asks about "happy", not about someone called "my brother happy")
    if ($whether) {
        $readings = @($readings | Where-Object {
                $mine = $_
                @($readings | Where-Object { $_.Verb -eq $mine.Verb -and @($_.Roles.Keys).Count -gt @($mine.Roles.Keys).Count }).Count -eq 0
            })
    }
    # A verb alone ("je travaille") is read only when nothing else reads: "mon frere a deux livres" has "livres",
    # not "mon frere deux" who "livre"
    $complete = @($readings | Where-Object { $_.Kind -ne 'statement' -or @($_.Roles.Keys).Count -gt 0 -or ($_.Name -and $_.Name -in @($general['Pronouns'])) })
    if ($complete.Count -gt 0) { $readings = $complete }
    $plain = @($readings | Where-Object { -not $_.Helper })
    if ($plain.Count -gt 0) { return $plain[0] }
    return $readings[0]
}

function Get-LambekGeneralChoice {
    param(
        [pscustomobject] $Request,
        [System.Collections.Generic.List[object]] $Typed,
        [int[]] $Choice,
        [hashtable] $Kinds,
        [hashtable] $Lemmas,
        [System.Collections.IDictionary] $General,

        # The words for the one who speaks
        [string[]] $First = @(),

        # The sentence asks whether
        [switch] $Whether,

        # The sentence is a question
        [switch] $Question
    )

    # One reading of the sentence: who, the verb, what, where
    $dictionary = Get-LambekSentenceReading -Text "$($Request.Original)" -Language $Request.Language
    $typedAs = $Request
    $tokens = @($Request.Tokens)


    # The reading chosen, reduced once more to know which types cancel which
    $simple = [System.Collections.Generic.List[object]]::new()
    $owner = [System.Collections.Generic.List[int]]::new()
    $chosen = @{}
    for ($w = 0; $w -lt $typed.Count; $w++) {
        $chosen[$w] = $typed[$w].Candidates[$choice[$w]]
        foreach ($part in ConvertFrom-LambekType -Type $chosen[$w]) { $simple.Add($part); $owner.Add($w) }
    }
    $reduction = Invoke-LambekReduction -SimpleTypes $simple.ToArray()
    $partner = @{}
    foreach ($pair in $reduction.Pairs) { $partner[[int] $pair.Left] = [int] $pair.Right; $partner[[int] $pair.Right] = [int] $pair.Left }

    # One verb only: the word that makes the sentence
    $verbs = @(for ($w = 0; $w -lt $typed.Count; $w++) { if ($chosen[$w] -in 'n^r s', 'n^r s n^l', 's n^l', 's n^l n^l') { $w } })
    if ($verbs.Count -ne 1) { return $null }
    $verb = $verbs[0]
    # A verb right after the verb that helps it is its participle ("a achete", "est parti"): "est content" is never
    # "est" helping "content" read as a form of "conter"
    # (in the languages whose dictionary says which forms are participles)
    if ($General['Participles'] -and $verb -gt 0 -and $chosen[$verb - 1] -eq 'n^r n' -and $Kinds[$typed[$verb - 1].Position] -eq 'auxiliary') {
        $forms = @($dictionary.Lemmas($typed[$verb].Word, $Request.Language) | Where-Object { $_.Pos -eq 'v' })
        if ($forms.Count -gt 0 -and @($forms | Where-Object { "$($_.Tag)" -cmatch 'K' }).Count -eq 0) { return $null }
    }

    # The words of a noun phrase: from one n, every word that hangs on it (its article, its adjective), but no auxiliary
    $phrase = {
        param([int] $at)
        $seen = [System.Collections.Generic.SortedSet[int]]::new()
        $todo = [System.Collections.Generic.Queue[int]]::new()
        $todo.Enqueue($at)
        $guard = 0
        while ($todo.Count -gt 0 -and $guard++ -lt 64) {
            $index = $todo.Dequeue()
            $word = $owner[$index]
            if ($kinds[$typed[$word].Position] -ne 'auxiliary') { [void] $seen.Add($typed[$word].Position) }
            for ($x = 0; $x -lt $simple.Count; $x++) {
                if ($owner[$x] -ne $word -or $x -eq $index -or $simple[$x].Base -ne 'n' -or $simple[$x].Order -eq 0) { continue }
                if ($partner.ContainsKey($x) -and $simple[$partner[$x]].Order -eq 0) { $todo.Enqueue($partner[$x]) }
            }
        }
        return @($seen)
    }
    $slot = {
        param([int] $word, [int] $order)
        for ($x = 0; $x -lt $simple.Count; $x++) { if ($owner[$x] -eq $word -and $simple[$x].Base -eq 'n' -and $simple[$x].Order -eq $order) { return $x } }
        return -1
    }
    $said = { param($positions) Get-LambekWritten -Request $typedAs -Words @($positions | ForEach-Object { $tokens[$_] }) }

    # Who: the n the verb takes on its left
    # (after the verb in a question: the n it takes last is its subject, the one before is what it asks for)
    $asked = $null
    $resolved = $null
    $subject = & $slot $verb 1
    $after = @(for ($x = 0; $x -lt $simple.Count; $x++) { if ($owner[$x] -eq $verb -and $simple[$x].Base -eq 'n' -and $simple[$x].Order -eq -1) { $x } })
    $turned = $chosen[$verb] -in 's n^l', 's n^l n^l'
    if ($turned) { $subject = $after[-1] }
    if ($subject -lt 0 -or -not $partner.ContainsKey($subject)) { return $null }
    $who = @(& $phrase $partner[$subject])
    if ($who.Count -eq 0) { return $null }
    # A subject is "I", a name, or a noun with its article: "answers small talk" has none, and is no sentence
    # (the first word of a sentence has a capital whatever it is: there, a name is a word no dictionary knows,
    # or a noun in the singular standing alone, which only a name can do: "Lyon is...", never "Files left...")
    $named = @($who | Where-Object {
            $written = Get-LambekWritten -Request $typedAs -Words @($tokens[$_])
            $known = @($dictionary.Lemmas($tokens[$_], $Request.Language))
            # ("Paris" is also the plural of "pari": a noun that is its own lemma, and nothing but a noun, is enough;
            # so is a single word, when one of its readings is a noun that is its own lemma: "Marie" is also "marie",
            # but a word alone before the verb, with a capital and no article, can only be a name)
            $token = $tokens[$_]
            $itself = @($known | Where-Object { $_.Lemma -eq $token -and ($who.Count -eq 1 -or $_.Pos -eq 'n') }).Count -gt 0
            $alone = $itself -and ($who.Count -eq 1 -or @($known | Where-Object { $_.Pos -ne 'n' }).Count -eq 0)
            $written -cmatch '^\p{Lu}' -and ($_ -gt 0 -or $known.Count -eq 0 -or $alone)
        }).Count -eq $who.Count
    $article = @($who | Where-Object { $tokens[$_] -in @($general['Determiners']) }).Count -gt 0
    $single = $who.Count -eq 1 -and ($tokens[$who[0]] -in $First -or $kinds[$who[0]] -eq 'what' -or $tokens[$who[0]] -in @($general['Pronouns']))
    if (-not ($named -or $article -or $single)) { return $null }
    $agent = 'other'
    $name = & $said $who
    if ($who.Count -eq 1 -and $kinds[$who[0]] -eq 'what') { $asked = 'agent'; $agent = $null; $name = $null }
    elseif ($who.Count -eq 1 -and $tokens[$who[0]] -in $First) { $agent = 'speaker'; $name = $null }
    elseif (@($who | Where-Object { $tokens[$_] -in @($general['Addressee']) }).Count -gt 0) { return $null }
    # "elle", "he": the one it stands for, as it was told; nobody when the conversation does not say who
    elseif ($who.Count -eq 1 -and $tokens[$who[0]] -in @($general['Pronouns'])) {
        $pronoun = $tokens[$who[0]]
        # "il pleut", "it is raining": the pronoun stands for nobody, the sentence is about the weather or the time
        # (asked, the verb comes first: "is it raining", "pleut-il")
        # ("il ne pleut pas": the words of negation are not part of it)
        $rest = " $(@($tokens | Select-Object -Skip ($who[0] + 1) | Where-Object { $_ -notin @($General['Negations']) }) -join ' ') "
        $turnedRest = $rest
        if ($who[0] -gt 0) { $turnedRest = " $($tokens[$who[0] - 1])$rest" }
        $impersonal = @(@($general['Impersonal']) | Where-Object {
                $weather = " $(ConvertTo-LambekNormalizedText -Text $_) "
                $_ -and ($rest.StartsWith($weather) -or $turnedRest.StartsWith($weather))
            }).Count -gt 0
        # (in a question, "it" is too often about nothing told: "what time is it")
        if (-not $impersonal -and $Question -and "$($general['PronounFeatures'][$pronoun])" -match 'thing') { return $null }
        if ($impersonal) { $name = Get-LambekWritten -Request $typedAs -Words @($pronoun) }
        else {
            $name = Get-LambekReferent -Pronoun $pronoun -Language $Request.Language -Verb "$($lemmas[$typed[$verb].Position])"
            # Read, but about nobody known: it is said, so the user can say who
            if (-not $name) { return [pscustomobject]@{ Kind = 'unresolved'; Pronoun = Get-LambekWritten -Request $typedAs -Words @($pronoun) } }
            $resolved = [pscustomobject]@{ Pronoun = Get-LambekWritten -Request $typedAs -Words @($pronoun); Antecedent = $name }
        }
    }

    # A pronoun anywhere else is not read yet
    $elsewhere = @(for ($w = 0; $w -lt $typed.Count; $w++) { if ($typed[$w].Position -notin $who -and $typed[$w].Word -in @($general['Pronouns'])) { $w } })
    if ($elsewhere.Count -gt 0) { return $null }

    # What: the n the verb takes on its right, then each place or other complement a preposition brings
    $roles = [ordered]@{}
    $shown = @{}
    $object = & $slot $verb -1
    if ($turned) { $object = -1; if ($after.Count -eq 2) { $object = $after[0] } }
    if ($object -ge 0 -and $partner.ContainsKey($object)) {
        $target = $partner[$object]
        if ($kinds[$typed[$owner[$target]].Position] -eq 'what') { $asked = 'object' }
        else { $roles['object'] = & $said @(& $phrase $target) }
    }
    for ($w = 0; $w -lt $typed.Count; $w++) {
        if ($kinds[$typed[$w].Position] -ne 'preposition' -and $chosen[$w] -notin 's^r s n^l', 's s^l n^l') { continue }
        $takes = & $slot $w -1
        if ($takes -lt 0 -or -not $partner.ContainsKey($takes)) { continue }
        $key = $typed[$w].Word
        # The same word of place twice ("in Lyon and in Paris") cannot be kept as one: the sentence is not read
        if ($roles.Contains($key)) { return $null }
        $roles[$key] = & $said @(& $phrase $partner[$takes])
        $shown[$key] = Get-LambekWritten -Request $typedAs -Words @($key)
    }
    if (@($typed | Where-Object { $kinds[$_.Position] -eq 'where' }).Count -gt 0) { $asked = 'place' }
    if (-not $asked -and $Whether) { $asked = 'whether' }
    # (a verb alone is a sentence about the weather, "il pleut", or about someone said plainly: "je travaille",
    # "ma soeur dort", "Paul sleeps"; "answers small talk" is none)
    # (said plainly: its subject first, and no word that asks: "what is the weather" tells nothing)
    $plainly = ($agent -eq 'speaker' -or $article -or $named) -and -not $turned -and @($typed | Where-Object { $kinds[$_.Position] -in 'what', 'where' }).Count -eq 0
    if (-not $asked -and $roles.Count -eq 0 -and -not $plainly -and -not ($agent -eq 'other' -and $name -and $name -in @($general['Pronouns']))) { return $null }

    # Said back in its plainest form: the verb as the dictionary gives it, then what and where ("live in Lyon")
    $lemma = "$($lemmas[$typed[$verb].Position])"
    $what = @($lemma) + @(foreach ($key in $roles.Keys) { if ($key -eq 'object') { $roles[$key] } else { "$($shown[$key]) $($roles[$key])" } })

    [pscustomobject]@{
        Kind  = $(if ($asked) { 'question' } else { 'statement' })
        What  = ($what -join ' ')
        Verb  = $lemma
        Agent = $agent
        Name  = $name
        Roles = $roles
        Asked = $asked
        Helper = ($typed[$verb].Word -in @($general['Auxiliaries']))
        Resolved = $resolved
        Types = (@(for ($w = 0; $w -lt $typed.Count; $w++) { "$($typed[$w].Word):[$($chosen[$w])]" }) -join '  ')
    }
}
