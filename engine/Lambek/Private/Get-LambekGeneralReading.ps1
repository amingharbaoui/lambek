function Get-LambekGeneralReading {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        # Read as the one spoken to: "you bought a car" is then about the user, as when Lambek says it back
        [switch] $Listener
    )

    # A sentence about anything, read with the same pregroup grammar as an order but with the words of the dictionary:
    # a noun is n, a verb takes its subject on the left (n^r s) and maybe an object on the right (n^r s n^l),
    # "my" and "the" make a noun of a noun (n n^l), "in" adds a place to the sentence (s^r s n^l).
    # When the words reduce to s, the cancellations say who does what, to what, where. Nothing is guessed:
    # a sentence that does not reduce, has two verbs, or says "not", gives nothing
    $language = $Request.Language
    $lexicon = Get-LambekLexicon -Language $language
    $general = $null
    if ($lexicon.Dialogue) { $general = $lexicon.Dialogue['General'] }
    if (-not $general) { return $null }
    $dictionary = Get-LambekDictionary -Language $language
    if (-not $dictionary) { return $null }

    # The words as they were typed: a word corrected towards a word of a pack ("live" read as "move") is not the word said
    $typedAs = Read-LambekRequest -Text (Repair-LambekPhrase -Text "$($Request.Original)") -Original "$($Request.Original)" -Language $language
    $tokens = @($typedAs.Tokens)
    if ($tokens.Count -lt 2 -or $tokens.Count -gt 16) { return $null }
    if (@($tokens | Where-Object { $_ -in $lexicon.Negations -or $_ -in @($general['Negations']) }).Count -gt 0) { return $null }
    # "I want the newest", "je voudrais...": a wish is a way to ask, not something told
    if (@($tokens | Where-Object { $_ -in @($lexicon.Dialogue['Wishes']) }).Count -gt 0) { return $null }
    # "what time is it", "she moved": who or what "it" and "she" are would have to come from the sentences before
    if (@($tokens | Where-Object { $_ -in @($general['Pronouns']) }).Count -gt 0) { return $null }
    # "who are you", "what can you do": what is said to Lambek about itself is answered elsewhere
    $first = @($general['Speakers'])
    $second = @($general['Addressee'])
    if ($Listener) { $first = @($general['Addressee']); $second = @($general['Speakers']) }
    if (@($tokens | Where-Object { $_ -in $second }).Count -gt 0) { return $null }
    # "what time is it", "which file...": a question word before a noun is not read yet
    if ($tokens[0] -in @($general['What']) -and $tokens[1] -notin @($general['Auxiliaries']) -and $tokens[1] -notin @($general['Speakers'])) {
        $next = @($dictionary.Lemmas($tokens[1], $language) | ForEach-Object { $_.Pos })
        if ('v' -notin $next) { return $null }
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

    # The types each word may have: the small words from the language file, the others from the dictionary
    $typed = [System.Collections.Generic.List[object]]::new()
    $kinds = @{}
    $lemmas = @{}
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        if ($timeAt[$i] -eq 'rest' -or $token -in @($general['Skipped'])) { continue }
        # "vous vous appelez": the second one goes with the verb, as "m'" does in "je m'appelle"
        if ($Listener -and $i -gt 0 -and $token -in $first -and $tokens[$i - 1] -eq $token) { continue }
        $types = [System.Collections.Generic.List[string]]::new()
        $kind = 'word'
        if ($timeAt[$i] -eq 'first') { $kind = 'time'; $types.AddRange([string[]] @('s^r s', 's s^l')) }
        elseif ($token -match '^_[a-z]+_$') { $types.Add('n') }
        elseif ($token -in @($general['Where'])) { $kind = 'where'; $types.Add('s s^l') }
        elseif ($token -in @($general['What'])) { $kind = 'what'; $types.AddRange([string[]] @('s n^ll s^l', 's s^l n')) }
        elseif ($token -in $first -or $token -in $second -or $token -in @($general['Pronouns'])) { $kind = 'pronoun'; $types.Add('n') }
        elseif ($token -in @($general['Determiners'])) { $types.Add('n n^l') }
        elseif ($token -in @($general['Prepositions'])) { $kind = 'preposition'; $types.AddRange([string[]] @('s^r s n^l', 's s^l n^l')) }
        else {
            $found = @($dictionary.Lemmas($token, $language))
            $pos = @($found | ForEach-Object { $_.Pos } | Select-Object -Unique)
            if ($token -in @($general['Auxiliaries'])) { $kind = 'auxiliary'; $types.AddRange([string[]] @('n^r n', 'n n^l')) }
            if ('v' -in $pos -or $token -in @($general['Verbs'])) {
                $types.AddRange([string[]] @('n^r s', 'n^r s n^l'))
                # ("suis" is "etre" before it is "suivre": a verb that also helps the others is read as itself)
                $helps = @($found | Where-Object { $_.Pos -like 'aux*' } | ForEach-Object { $_.Lemma })
                $verb = @(@($found | Where-Object { $_.Pos -eq 'v' -and $_.Lemma -in $helps }) + @($found | Where-Object { $_.Pos -eq 'v' }) | Select-Object -First 1)
                $lemmas[$i] = $(if ($verb.Count -gt 0) { if ($verb[0].Shown) { $verb[0].Shown } else { $verb[0].Lemma } } else { $token })
            }
            # A word no dictionary knows is a name only when it is written like one ("Amin", "Felix")
            if ($pos.Count -eq 0 -and $kind -eq 'word' -and (Get-LambekWritten -Request $typedAs -Words @($token)) -cnotmatch '^\p{Lu}') { return $null }
            if ('n' -in $pos -or $pos.Count -eq 0) { $types.Add('n') }
            if ('a' -in $pos) { $types.AddRange([string[]] @('n n^l', 'n^r n')); if ('n' -notin $pos) { $types.Add('n') } }
            if ('r' -in $pos) { $types.AddRange([string[]] @('s^r s', 's s^l')) }
            if ('det' -in $pos) { $types.Add('n n^l') }
            if ('prep' -in $pos -and $kind -eq 'word') { $types.AddRange([string[]] @('s^r s n^l', 's s^l n^l')) }
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
    $readings = @(foreach ($choice in $root['s|0']) { Get-LambekGeneralChoice -Request $typedAs -Typed $typed -Choice $choice -Kinds $kinds -Lemmas $lemmas -General $general -First $first })
    $readings = @($readings | Where-Object { $_ })
    if ($readings.Count -eq 0) { return $null }
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
        [string[]] $First = @()
    )

    # One reading of the sentence: who, the verb, what, where
    $dictionary = Get-LambekDictionary -Language $Request.Language
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
    $verbs = @(for ($w = 0; $w -lt $typed.Count; $w++) { if ($chosen[$w] -in 'n^r s', 'n^r s n^l') { $w } })
    if ($verbs.Count -ne 1) { return $null }
    $verb = $verbs[0]

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
    $asked = $null
    $subject = & $slot $verb 1
    if ($subject -lt 0 -or -not $partner.ContainsKey($subject)) { return $null }
    $who = @(& $phrase $partner[$subject])
    if ($who.Count -eq 0) { return $null }
    # A subject is "I", a name, or a noun with its article: "answers small talk" has none, and is no sentence
    # (the first word of a sentence has a capital whatever it is: there, a name is a word no dictionary knows,
    # or a noun in the singular standing alone, which only a name can do: "Lyon is...", never "Files left...")
    $named = @($who | Where-Object {
            $written = Get-LambekWritten -Request $typedAs -Words @($tokens[$_])
            $known = @($dictionary.Lemmas($tokens[$_], $Request.Language))
            $alone = @($known | Where-Object { $_.Pos -ne 'n' -or $_.Lemma -ne $tokens[$who[0]] }).Count -eq 0
            $written -cmatch '^\p{Lu}' -and ($_ -gt 0 -or $known.Count -eq 0 -or $alone)
        }).Count -eq $who.Count
    $article = @($who | Where-Object { $tokens[$_] -in @($general['Determiners']) }).Count -gt 0
    $single = $who.Count -eq 1 -and ($tokens[$who[0]] -in $First -or $kinds[$who[0]] -eq 'what')
    if (-not ($named -or $article -or $single)) { return $null }
    $agent = 'other'
    $name = & $said $who
    if ($who.Count -eq 1 -and $kinds[$who[0]] -eq 'what') { $asked = 'agent'; $agent = $null; $name = $null }
    elseif ($who.Count -eq 1 -and $tokens[$who[0]] -in $First) { $agent = 'speaker'; $name = $null }
    elseif (@($who | Where-Object { $tokens[$_] -in @($general['Addressee']) }).Count -gt 0) { return $null }
    # "she", "it": who that is would have to come from the sentences before, which is not read yet
    elseif ($who.Count -eq 1 -and $tokens[$who[0]] -in @($general['Pronouns'])) { return $null }

    # What: the n the verb takes on its right, then each place or other complement a preposition brings
    $roles = [ordered]@{}
    $shown = @{}
    $object = & $slot $verb -1
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
        if ($roles.Contains($key)) { continue }
        $roles[$key] = & $said @(& $phrase $partner[$takes])
        $shown[$key] = Get-LambekWritten -Request $typedAs -Words @($key)
    }
    if (@($typed | Where-Object { $kinds[$_.Position] -eq 'where' }).Count -gt 0) { $asked = 'place' }
    if (-not $asked -and $roles.Count -eq 0) { return $null }

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
        Types = (@(for ($w = 0; $w -lt $typed.Count; $w++) { "$($typed[$w].Word):[$($chosen[$w])]" }) -join '  ')
    }
}
