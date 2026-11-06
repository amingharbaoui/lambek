function Get-LambekLogicWord {
    # The words of logic of a language, learned (tools/Learn-LambekLogicWords.ps1, Data/Forms/<language>.logic): what
    # each says of how many things ("all", "some", "no"), a word learned with two kinds saying neither; and its copulas,
    # the verbs that only join ("etre", "be"). Nothing when the language has none
    param([string] $Language)

    if ($null -eq $script:LogicWords) { $script:LogicWords = @{} }
    if ($script:LogicWords.ContainsKey($Language)) { return $script:LogicWords[$Language] }
    $found = $null
    $path = Join-Path $PSScriptRoot "../Data/Forms/$Language.logic"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $words = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
        $twice = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $copulas = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($word in [LambekLogicWords]::Read([IO.Path]::GetFullPath($path))) {
            if ($word.Kind -eq 'copula') { [void] $copulas.Add($word.Word); continue }
            if ($words.ContainsKey($word.Word) -and $words[$word.Word] -ne $word.Kind) { [void] $twice.Add($word.Word) }
            $words[$word.Word] = $word.Kind
        }
        foreach ($word in $twice) { [void] $words.Remove($word) }
        if ($copulas.Count -gt 0) { $found = [pscustomobject]@{ Kinds = $words; Copulas = $copulas } }
    }
    $script:LogicWords[$Language] = $found
    return $found
}

function Read-LambekCategoryTagged {
    # A general rule or a question about one read by what its words are, as the treebanks of the language tag them, and
    # by its words of logic, learned: no pattern written for a language. The verb is the first word tagged AUX or VERB:
    # a copula, as the treebanks tag it, joins the one to what it is ("est un chat"); any other AUX leaves the VERB after
    # it to say what is done ("a mange", "does it fly"); a VERB says what is done, "avoir" too ("ont un capteur").
    # Before it, the one or the kind it is said of; a word of logic first says of how many ("tous", "aucun",
    # "certains"); a plural with no word of logic, of all of them ("les oiseaux volent"). A word tagged Polarity=Neg
    # says not. A question is asked by its mark, an AUX first, or a pronoun after the verb ("aime-t-il"); one that asks
    # who, which or how many is left to the patterns. Read with the same parts as the patterns read, by
    # Read-LambekCategoryPart; nothing when a part does not read
    param([string] $Sentence, [string] $Language, [switch] $Question, [switch] $Shape)

    $model = Get-LambekFormModel -Language $Language
    $logic = Get-LambekLogicWord -Language $Language
    if (-not $model -or -not $logic) { return $null }
    $isCopula = { param($r) "$($readings[$r].Lemma)".ToLowerInvariant() -in $logic.Copulas }
    # (the marks that open or close the sentence are no words of it: the inverted mark that opens a question in Spanish)
    $words = @(($Sentence.Trim() -replace '^\p{P}+', '' -replace '\p{P}+$', '') -split ' ' | Where-Object { $_ })
    $inverted = $false
    # (asked as the language asks before the sentence, its last vowel elided before a vowel: "est-ce que", "est-ce
    # qu'il")
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $lead = ''
    if ($dialogue -and $dialogue['General']) { $lead = (ConvertTo-LambekNormalizedText -Text "$($dialogue['General']['Inverted'])") -replace '-', ' ' }
    if ($lead) {
        $parts = @($lead -split ' ' | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) })
        $last = $parts[-1]
        $elided = "$($last.Substring(0, $last.Length - 1))(?:$($last.Substring($last.Length - 1))\s+|['\u2019])"
        $pattern = '^' + ((@($parts | Select-Object -SkipLast 1) + @($elided)) -join '\s+')
        $joined = $words -join ' '
        $match = [regex]::Match(((ConvertTo-LambekNormalizedText -Text $joined) -replace '-', ' '), $pattern)
        if ($match.Success -and $match.Length -le $joined.Length) {
            $rest = $joined.Substring($match.Length).Trim()
            $words = @($rest -split ' ' | Where-Object { $_ })
            $inverted = $true
        }
    }
    $written = [System.Collections.Generic.List[string]]::new()
    foreach ($word in $words) {
        # (a pronoun after the verb, joined to it, as the treebank writes it: "aime-t-il", "est-elle")
        $cut = -1
        for ($k = 1; $k -lt $word.Length -and $cut -lt 0; $k++) {
            if ($word[$k] -ne '-') { continue }
            $tags = $null
            # (a pronoun that is the subject, as the treebank tags it: Case=Nom, or of the third person with a
            # gender; not "raconte-moi", where it is told to)
            if (-not $model.Tags.TryGetValue($word.Substring($k).ToLowerInvariant(), [ref] $tags)) { continue }
            $pronoun = @($tags | Where-Object { -not $_.StartsWith('PRON|') }).Count -eq 0
            $subject = @($tags | Where-Object { $_ -match '\|Case=Nom(\||$)' -or ($_ -match '\|Person=3(\||$)' -and $_ -match '\|Gender=') }).Count -gt 0
            if ($pronoun -and $subject) { $cut = $k }
        }
        if ($cut -gt 0) {
            # (the pronoun after the verb that opens the sentence is the one it is said of: "suis-je mortel" says of
            # "je" what "je suis mortel" says)
            if ($written.Count -eq 0) { $written.Add(@($word.Substring($cut) -split '-' | Where-Object { $_ })[-1]) }
            $written.Add($word.Substring(0, $cut))
            $inverted = $true
        }
        else { $written.Add($word) }
    }
    if ($written.Count -eq 0) { return $null }

    # The words read in context, each with the written word it is in
    $readings = @($model.ReadText(($written -join ' ')))
    $of = [int[]]::new($readings.Count)
    $at = 0
    for ($w = 0; $w -lt $written.Count; $w++) {
        $word = $written[$w].ToLowerInvariant()
        $joined = ''
        $start = $at
        while ($at -lt $readings.Count -and $joined.Length -lt $word.Length) {
            $joined += "$($readings[$at].Form)".ToLowerInvariant()
            $of[$at] = $w
            $at++
        }
        if ($joined -ne $word) {
            # (a word the language writes as two: "du" is "de le")
            $at = $start
            $parts = $null
            if (-not $model.Contractions.TryGetValue($word, [ref] $parts)) { return $null }
            foreach ($part in @("$parts" -split ' ')) {
                if ($at -ge $readings.Count -or "$($readings[$at].Form)".ToLowerInvariant() -ne $part) { return $null }
                $of[$at] = $w
                $at++
            }
        }
    }
    if ($at -ne $readings.Count) { return $null }
    # Only a sentence of the language: every word that makes the sentence (a verb, a determiner, a preposition, a
    # pronoun...) is one its treebanks or its texts had ("est" is no English word), what is spoken of may be new; a word
    # never seen written with a capital is a name, whatever the tagger guessed ("Socrates"), but the first word of the
    # sentence, which any word may be, only when it was guessed a verb ("Penguins do not fly"). And no word that asks
    # which or how many ("quel", "combien", "what"): those are questions of another kind
    $upos = [string[]]::new($readings.Count)
    for ($r = 0; $r -lt $readings.Count; $r++) {
        $form = "$($readings[$r].Form)"
        $upos[$r] = "$($readings[$r].Upos)"
        $known = $model.Knows($form.ToLowerInvariant()) -or $model.Learned.ContainsKey($form.ToLowerInvariant())
        $capital = $form.Length -gt 0 -and [char]::IsUpper($form[0])
        if (-not $known -and $capital -and ($r -gt 0 -or $upos[$r] -in 'VERB', 'AUX', 'X')) { $upos[$r] = 'PROPN' }
        elseif (-not $known -and $upos[$r] -notin 'NOUN', 'ADJ', 'PROPN') { return $null }
        if ("|$($readings[$r].Feats)|".Contains('|PronType=Int|')) { return $null }
    }
    $has = { param($r, $feature) "|$($readings[$r].Feats)|".Contains("|$feature|") }
    $negative = [bool[]]::new($readings.Count)
    for ($r = 0; $r -lt $readings.Count; $r++) { $negative[$r] = & $has $r 'Polarity=Neg' }
    # (the text of readings from one to another, as written when whole words, else as read: "i" of "i'm")
    $text = {
        param([int] $From, [int] $To)
        $out = [System.Collections.Generic.List[string]]::new()
        $r = $From
        while ($r -lt $To) {
            if ($negative[$r]) { $r++; continue }
            $w = $of[$r]
            $first = [array]::IndexOf($of, $w)
            $last = [array]::LastIndexOf($of, $w)
            $inside = $true
            for ($k = $first; $k -le $last; $k++) {
                if (($k -lt $From -or $k -ge $To) -and -not $negative[$k]) { $inside = $false }
            }
            if ($inside -and $first -ge $From) {
                # (the written word, without what in it says not: "n'aime" is "aime")
                $parts = @(for ($k = $first; $k -le $last; $k++) { if (-not $negative[$k]) { "$($readings[$k].Form)" } })
                $out.Add($(if (@(for ($k = $first; $k -le $last; $k++) { if ($negative[$k]) { $k } }).Count -eq 0) { $written[$w] } else { $parts -join '' }))
                $r = $last + 1
            }
            else { $out.Add("$($readings[$r].Form)"); $r++ }
        }
        ($out -join ' ').Trim()
    }

    $first = 0
    while ($first -lt $readings.Count -and $negative[$first]) { $first++ }
    if ($first -ge $readings.Count) { return $null }
    $asking = $Question -or $inverted
    # (an AUX first asks: "does it fly", "is Tom a cat"; in a question, so does a VERB first when another follows: "do
    # all cats drink milk")
    $verbal = @(for ($r = $first; $r -lt $readings.Count; $r++) { if ($upos[$r] -in 'AUX', 'VERB') { $r } })
    if ($verbal.Count -eq 0) { return $null }
    $front = $verbal[0] -eq $first -and ($upos[$first] -eq 'AUX' -or ($Question -and $verbal.Count -gt 1))
    if ($front) { $asking = $true }

    # Of how many: a word of logic first, then its article if any ("tous les"); a plural with none, of all
    $from = $(if ($front) { $first + 1 } else { $first })
    $quantity = $null
    $quantifier = ''
    $q = $from
    while ($q -lt $readings.Count -and $negative[$q]) { $q++ }
    if ($q -lt $readings.Count -and $upos[$q] -notin 'NOUN', 'PROPN', 'VERB', 'AUX') {
        $form = "$($readings[$q].Form)".ToLowerInvariant()
        if ($logic.Kinds.ContainsKey($form)) {
            $quantity = $logic.Kinds[$form]
            $quantifier = $form
            $q++
            if ($q -lt $readings.Count -and $upos[$q] -eq 'DET' -and (& $has $q 'PronType=Art')) { $q++ }
            $from = $q
        }
    }

    # The verb: what is said after the one or the kind
    $main = $null
    $copula = $null
    $subjectEnd = $null
    if ($front) {
        # (asked first: the copula is followed by the one and what it is, where the one ends is cut below; any other
        # verb that asks, by the one and the verb: "does my phone have a sensor")
        if (& $isCopula $first) { $copula = $first }
        else {
            $after = @($verbal | Where-Object { $_ -gt $from -and $upos[$_] -eq 'VERB' })
            if ($after.Count -eq 0) { return $null }
            $main = $after[0]
            $subjectEnd = $main
        }
    }
    else {
        $verb = @($verbal | Where-Object { $_ -ge $from })
        if ($verb.Count -eq 0) { return $null }
        $v = $verb[0]
        $subjectEnd = $v
        if (& $isCopula $v) { $copula = $v }
        elseif ($upos[$v] -eq 'AUX') {
            # (a verb that helps another, with only what says not between: "a mange", "don't fly")
            $next = $v + 1
            while ($next -lt $readings.Count -and $negative[$next]) { $next++ }
            # (with none, it is the verb itself: "a un chat", as the tagger may read "avoir" before its object)
            $main = $(if ($next -lt $readings.Count -and $upos[$next] -eq 'VERB') { $next } else { $v })
        }
        else { $main = $v }
    }
    $denied = @(for ($r = $from; $r -lt $readings.Count; $r++) { if ($negative[$r]) { $r } }).Count -gt 0

    # What kind of sentence: of how many, whether it says not, whether it asks
    $generic = $false
    if (-not $quantity) {
        $end = $(if ($null -ne $subjectEnd) { $subjectEnd } else { $readings.Count })
        $nouns = @(for ($r = $from; $r -lt $end; $r++) { if ($upos[$r] -in 'NOUN', 'PROPN', 'PRON') { $r } })
        if ($nouns.Count -gt 0 -and $upos[$nouns[-1]] -eq 'NOUN' -and (& $has $nouns[-1] 'Number=Plur')) {
            $generic = $true
            $quantity = 'all'
            # (the article of the plural is its word of how many: "les")
            if ($upos[$from] -eq 'DET' -and (& $has $from 'Definite=Def') -and (& $has $from 'Number=Plur')) { $quantifier = "$($readings[$from].Form)".ToLowerInvariant(); $from++ }
        }
    }
    $kind = switch ($quantity) {
        'all' { if ($denied) { if ($generic) { 'no' } else { $null } } else { 'all' } }
        'some' { if ($denied) { 'somenot' } else { 'some' } }
        'no' { 'no' }
        default { $null }
    }
    $individual = -not $quantity
    if ($individual) { $kind = $(if ($null -ne $copula) { if ($denied) { 'isnot' } else { 'is' } } else { if ($denied) { 'doesnot' } else { 'does' } }) }
    if (-not $kind) { return $null }
    if ($asking) {
        $kind = @{ all = 'askall'; some = 'asksome'; no = 'askno'; somenot = 'asksomenot'; is = 'askis'; does = 'askdoes' }[$kind]
        if (-not $kind) { return $null }
    }
    if ($Shape) { return [pscustomobject]@{ Kind = $kind } }

    # The parts, as the patterns name them: q of how many, s the kind or n the one, p what it is, v the verb, o its object
    $cuts = [System.Collections.Generic.List[hashtable]]::new()
    $values = @{}
    if ($quantifier) { $values['q'] = $quantifier }
    $name = $(if ($individual) { 'n' } else { 's' })
    if ($null -ne $main) {
        $values['v'] = "$($readings[$main].Form)"
        $values['lemma'] = "$($readings[$main].Lemma)"
        $object = & $text ($main + 1) $readings.Count
        if ($object) { $values['o'] = $object }
        $subject = & $text $from $(if ($front) { $main } else { $subjectEnd })
        if (-not $subject) { return $null }
        $values[$name] = $subject
        $cuts.Add($values)
    }
    elseif ($front) {
        # (asked first with the copula: where the one ends and what it is begins is not said; the first cut that reads,
        # from the left)
        $rest = @(for ($r = $from; $r -lt $readings.Count; $r++) { if (-not $negative[$r]) { $r } })
        for ($j = 1; $j -lt $rest.Count; $j++) {
            $cut = $values.Clone()
            $cut[$name] = & $text $rest[0] $rest[$j]
            $cut['p'] = & $text $rest[$j] $readings.Count
            if ($cut[$name] -and $cut['p']) { $cuts.Add($cut) }
        }
    }
    else {
        $subject = & $text $from $copula
        $predicate = & $text ($copula + 1) $readings.Count
        if (-not $subject -or -not $predicate) { return $null }
        $values[$name] = $subject
        $values['p'] = $predicate
        $cuts.Add($values)
    }
    foreach ($cut in $cuts) {
        $item = Read-LambekCategoryPart -Kind $kind -Values $cut -Language $Language
        if ($item) { return $item }
    }
    return $null
}
