function Get-LambekCategorySupport {
    # The verbs a language says "does" with and no more ("does" of "Rex does fly"): the words of its own sentence for
    # what one does ("{0} does {1}") that are none of what it is filled with, read by its forms model. None in most
    # languages ("{0} {1}")
    param([string] $Language)

    if ($null -eq $script:CategorySupport) { $script:CategorySupport = @{} }
    if ($script:CategorySupport.ContainsKey($Language)) { return $script:CategorySupport[$Language] }
    $found = [System.Collections.Generic.List[string]]::new()
    $sentence = "$((Get-LambekCategoryVocabulary -Language $Language).Data['Sentences']['does'])"
    $words = @(($sentence -replace '\{\d+\}', ' ').Trim() -split '\s+' | Where-Object { $_ })
    $model = Get-LambekFormModel -Language $Language
    if ($model -and $words.Count -gt 0) {
        foreach ($reading in $model.Read([string[]] $words)) { if ($reading.Lemma) { $found.Add((ConvertTo-LambekNormalizedText -Text "$($reading.Lemma)")) } }
    }
    $script:CategorySupport[$Language] = $found.ToArray()
    return $script:CategorySupport[$Language]
}

function Get-LambekLogicWord {
    # The words of logic of a language, learned (tools/Learn-LambekLogicWords.ps1, Data/Forms/<language>.logic): what
    # each says of how many things ("all", "some", "no"), a word learned with two kinds saying neither; and its copulas,
    # the verbs that only join ("etre", "be"); the article a negation puts before what is done to, and the first letters
    # before which it is cut ("pas de poils", "pas d'ailes"). Nothing when the language has none
    param([string] $Language)

    if ($null -eq $script:LogicWords) { $script:LogicWords = @{} }
    if ($script:LogicWords.ContainsKey($Language)) { return $script:LogicWords[$Language] }
    $found = $null
    $path = Join-Path $PSScriptRoot "../Data/Forms/$Language.logic"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $words = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
        $twice = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $copulas = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $negated = $null
        $elided = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
        foreach ($word in [LambekLogicWords]::Read([IO.Path]::GetFullPath($path))) {
            if ($word.Kind -eq 'copula') { [void] $copulas.Add($word.Word); continue }
            if ($word.Kind -eq 'negated') { $negated = $word.Word; continue }
            if ($word.Kind -eq 'elided') { $cut = $word.Word -split ' ', 2; $elided[$cut[1]] = $cut[0]; continue }
            if ($words.ContainsKey($word.Word) -and $words[$word.Word] -ne $word.Kind) { [void] $twice.Add($word.Word) }
            $words[$word.Word] = $word.Kind
        }
        foreach ($word in $twice) { [void] $words.Remove($word) }
        if ($copulas.Count -gt 0) { $found = [pscustomobject]@{ Kinds = $words; Copulas = $copulas; Negated = $negated; Elided = $elided } }
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
    param(
        [string] $Sentence,
        [string] $Language,
        [switch] $Question,
        [switch] $Shape,

        # Also read how many is said ("au moins trois", "au plus deux", "exactement deux"): the item says it in Count
        # {Least; Most}; one said of at most so many is read (Kind "count"), and one asked of so many (Kind "askcount").
        # Without it, at most is not read and so many asked is not, as "some" does not answer it
        [switch] $Counting
    )

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
    # pronoun...) is one its treebanks, its texts or its dictionary had ("est" is no English word), what is spoken of may be new; a word
    # never seen written with a capital is a name, whatever the tagger guessed ("Socrates"), but the first word of the
    # sentence, which any word may be, only when it was guessed a verb ("Penguins do not fly"). And no word that asks
    # which or how many ("quel", "combien", "what"): those are questions of another kind
    # (the names told in the conversation: "Rex" told as one is a name when it comes back, whatever the tagger guessed)
    # (and the words told: a word the dictionary gives more than one lemma is read with the one told, "come" is the
    # "comer" of "comen" told before, not "comar"; in either part of a rule told with "si" too, kind~who~what)
    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $said = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($thing in @($script:Told)) {
        if (-not $thing -or -not $thing.PSObject.Properties['Core']) { continue }
        foreach ($match in [regex]::Matches("$($thing.Core)", 'name:([\p{L}-]+)(?=[|+)>~])')) { [void] $names.Add($match.Groups[1].Value) }
        foreach ($match in [regex]::Matches("$($thing.Core)", '(?<=[|+>~]|[|~]v:)[\p{L}-]+(?=[|+>~)])')) { [void] $said.Add($match.Value) }
    }
    if ($said.Count -gt 0 -and $model.Lexicon) {
        foreach ($reading in $readings) {
            $entries = $null
            if (-not $reading.Lemma -or -not $model.Lexicon.TryGet("$($reading.Form)", [ref] $entries)) { continue }
            if ($said.Contains((ConvertTo-LambekNormalizedText -Text "$($reading.Lemma)"))) { continue }
            $told = @($entries | Where-Object { $_.Upos -eq $reading.Upos -and $said.Contains((ConvertTo-LambekNormalizedText -Text "$($_.Lemma)")) } | ForEach-Object Lemma | Select-Object -Unique)
            if ($told.Count -eq 1) { $reading.Lemma = $told[0] }
        }
    }
    # (a question opened by the word that asks who, learned: "wer ist ein Tier", "wie blaft")
    # (written with its accents or without: "quien" is the "quien" of the treebank, with its accent)
    $opening = ConvertTo-LambekNormalizedText -Text "$(if ($readings.Count -gt 0) { $readings[0].Form })"
    $who = $Question -and $readings.Count -gt 1 -and @($logic.Kinds.Keys | Where-Object { $logic.Kinds[$_] -eq 'who' -and (ConvertTo-LambekNormalizedText -Text $_) -eq $opening }).Count -gt 0
    $upos = [string[]]::new($readings.Count)
    for ($r = 0; $r -lt $readings.Count; $r++) {
        $form = "$($readings[$r].Form)"
        $upos[$r] = "$($readings[$r].Upos)"
        if ($form.Length -gt 0 -and [char]::IsUpper($form[0]) -and $names.Contains((ConvertTo-LambekNormalizedText -Text $form))) { $upos[$r] = 'PROPN'; $readings[$r].Upos = 'PROPN' }
        # (a word the dictionary of the language has is one of its words too: "abbaiano", "fressen")
        $known = $model.Knows($form.ToLowerInvariant()) -or $model.Learned.ContainsKey($form.ToLowerInvariant()) -or ($model.Lexicon -and $model.Lexicon.Forms.ContainsKey($form.ToLowerInvariant()))
        $capital = $form.Length -gt 0 -and [char]::IsUpper($form[0])
        if (-not $known -and $capital -and ($r -gt 0 -or $upos[$r] -in 'VERB', 'AUX', 'X')) { $upos[$r] = 'PROPN' }
        elseif (-not $known -and $upos[$r] -notin 'NOUN', 'ADJ', 'PROPN') { return $null }
        if (-not ($who -and $r -eq 0) -and "|$($readings[$r].Feats)|" -match '\|PronType=(?:[A-Za-z]+,)*Int(?:,[A-Za-z]+)*\|') { return $null }
    }
    # (the words learned to say how many before a number are no verb, whatever the tagger guessed: "au moins trois",
    # where "au" was read a verb at the head of a sentence)
    $surface = [string[]] @(for ($r = 0; $r -lt $readings.Count; $r++) { if ($r -eq 0 -or $of[$r] -ne $of[$r - 1]) { ConvertTo-LambekNormalizedText -Text "$($written[$of[$r]])" } else { '' } })
    for ($r = 0; $r -lt $readings.Count; $r++) {
        $counted = Get-LambekCategoryCount -Readings $readings -At $r -Language $Language -Surface $surface
        if (-not $counted) { continue }
        for ($j = $r; $j -lt $counted.Next - 1; $j++) { if ($upos[$j] -in 'VERB', 'AUX', 'ADP', 'DET') { $upos[$j] = 'ADV' } }
        break
    }
    $has = { param($r, $feature) "|$($readings[$r].Feats)|".Contains("|$feature|") }
    $negative = [bool[]]::new($readings.Count)
    # (what says not, as each treebank tags it: "no", "nao" with Polarity=Neg; "non", and "kein", "geen" after the verb,
    # with PronType=Neg; first, "kein", "nessun" say how many: none)
    # (and the adverb learned where English says "not", for a treebank that marks it with nothing: "niet")
    $not = @(Get-LambekNotWord -Language $Language)
    $verbSeen = $false
    for ($r = 0; $r -lt $readings.Count; $r++) {
        $negative[$r] = (& $has $r 'Polarity=Neg') -or ((& $has $r 'PronType=Neg') -and ("$($readings[$r].Upos)" -in 'ADV', 'PART' -or $verbSeen)) -or
        ("$($readings[$r].Upos)" -in 'ADV', 'PART' -and $not.Count -gt 0 -and (ConvertTo-LambekNormalizedText -Text "$($readings[$r].Form)") -in $not)
        if ("$($readings[$r].Upos)" -in 'AUX', 'VERB') { $verbSeen = $true }
    }
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
    # (a question with no verb read: its first word is the verb when the dictionary gives it as one, "ladra" of
    # "ladra Rex", read a noun by the tagger at the start of a sentence)
    # (and any sentence with no verb read and one word only the dictionary gives as a verb: that word, "blaffen" of
    # "alle honden blaffen", "late" of "Rex late?", read as nouns)
    if ($verbal.Count -eq 0 -and $model.Lexicon) {
        $verbs = [ordered]@{}
        for ($r = $first; $r -lt $readings.Count; $r++) {
            if ($negative[$r] -or $upos[$r] -eq 'PROPN') { continue }
            $entries = $null
            if (-not $model.Lexicon.TryGet("$($readings[$r].Form)", [ref] $entries)) { continue }
            # (right after a pronoun of a person, or right before it opening a question, a verb the dictionary
            # conjugates for that person and number, or for none it names: "io lavoro", "werk ik?", the tagger reading
            # "lavoro", "werk" as the noun)
            $agreeing = @()
            $by = $(if ($r -gt $first -and $upos[$r - 1] -eq 'PRON') { $r - 1 } elseif ($Question -and $r -eq $first -and $r + 1 -lt $readings.Count -and $upos[$r + 1] -eq 'PRON') { $r + 1 } else { -1 })
            if ($by -ge 0 -and (& $has $by 'PronType=Prs') -and "|$($readings[$by].Feats)|" -match '\|Person=(\d)\|') {
                $person = $Matches[1]
                $count = $(if ("|$($readings[$by].Feats)|" -match '\|Number=(\w+)\|') { $Matches[1] } else { '' })
                $agreeing = @($entries | Where-Object {
                        $feats = "|$($_.Feats)|"
                        "$($_.Upos)" -eq 'VERB' -and ($feats -notmatch '\|Person=' -or $feats -match "\|Person=$person\|") -and
                        (-not $count -or $feats -notmatch '\|Number=' -or $feats -match "\|Number=$count\|") -and $feats -notmatch '\|VerbForm=(Inf|Part|Ger)\|'
                    })
            }
            # (but no word the treebanks saw only as something else: "gato" of "nenhum gato late" is the noun they saw)
            $seen = $null
            if ($agreeing.Count -eq 0 -and $model.Tags.TryGetValue("$($readings[$r].Form)".ToLowerInvariant(), [ref] $seen) -and @($seen).Count -gt 0 -and
                @($seen | Where-Object { $_ -like 'VERB|*' -or $_ -like 'AUX|*' }).Count -eq 0) { continue }
            $verb = @($(if ($agreeing.Count -gt 0) { $agreeing } else { @($entries | Where-Object Upos -EQ 'VERB') }) | Select-Object -First 1)
            if ($verb.Count -gt 0) { $verbs[[string] $r] = $verb[0] }
        }
        $at = -1
        if ($Question -and $verbs.Contains([string] $first)) { $at = $first }
        elseif ($verbs.Count -eq 1) { $at = [int] @($verbs.Keys)[0] }
        if ($at -ge 0) {
            $verb = $verbs[[string] $at]
            $upos[$at] = 'VERB'
            $readings[$at].Upos = 'VERB'
            $readings[$at].Lemma = $verb.Lemma
            $readings[$at].Feats = $verb.Feats
            $verbal = @($at)
        }
    }
    if ($verbal.Count -eq 0) { return $null }

    # Who: the word that asks it, then the copula and what the one asked is ("wer ist ein Tier"), or the verb and what
    # it is done to ("wie blaft", "quien come carne"); nothing that says not
    if ($who) {
        if (@($negative | Where-Object { $_ }).Count -gt 0 -or $upos[1] -notin 'AUX', 'VERB') { return $null }
        if ($Shape) { return [pscustomobject]@{ Kind = 'askwho' } }
        $asked = @{}
        $lemmas = @{}
        foreach ($reading in $readings) {
            if ("$($reading.Upos)" -notin 'NOUN', 'ADJ', 'PROPN' -or -not $reading.Lemma) { continue }
            $lemmas[(ConvertTo-LambekNormalizedText -Text "$($reading.Form)")] = ConvertTo-LambekNormalizedText -Text "$($reading.Lemma)"
        }
        $asked['lemmas'] = $lemmas
        $rest = & $text 2 $readings.Count
        if (& $isCopula 1) {
            if (-not $rest) { return $null }
            $asked['p'] = $rest
        }
        else {
            $asked['v'] = "$($readings[1].Form)"
            $asked['lemma'] = "$($readings[1].Lemma)"
            if ($rest) { $asked['o'] = $rest }
        }
        return Read-LambekCategoryPart -Kind 'askwho' -Values $asked -Language $Language
    }
    # (asked with the word the language says "does" with, first, and no other verb read: the verb is the word after
    # the one asked of that its treebanks or its dictionary also give as a verb, "do all dogs bark", "bark" read a
    # noun)
    if ($Question -and $verbal.Count -eq 1 -and $verbal[0] -eq $first -and
        (ConvertTo-LambekNormalizedText -Text "$($readings[$first].Lemma)") -in @(Get-LambekCategorySupport -Language $Language)) {
        for ($r = $readings.Count - 1; $r -gt $first + 1; $r--) {
            $form = "$($readings[$r].Form)".ToLowerInvariant()
            $tags = $null
            $tagged = $model.Tags.TryGetValue($form, [ref] $tags) -and @($tags | Where-Object { "$_".StartsWith('VERB|') }).Count -gt 0
            $listed = $model.Lexicon -and $model.Lexicon.Forms.ContainsKey($form) -and @($model.Lexicon.Forms[$form] | Where-Object { "$($_.Upos)" -eq 'VERB' }).Count -gt 0
            if ($upos[$r] -in 'NOUN', 'ADJ' -and $upos[$r - 1] -in 'NOUN', 'PROPN' -and ($tagged -or $listed)) {
                $upos[$first] = 'AUX'
                $upos[$r] = 'VERB'
                $verbal = @($first, $r)
                break
            }
        }
    }
    $front = $verbal[0] -eq $first -and ($upos[$first] -eq 'AUX' -or ($Question -and $verbal.Count -gt 1))
    # (in a question, the verb alone first, the one after it: "bellt Rex", "ladra Rex")
    $alone = $Question -and -not $front -and $verbal.Count -eq 1 -and $verbal[0] -eq $first -and $upos[$first] -eq 'VERB'
    if ($alone) { $front = $true }
    if ($front) { $asking = $true }

    # Of how many: a word of logic first, then its article if any ("tous les"); a plural with none, of all
    $from = $(if ($front) { $first + 1 } else { $first })
    $quantity = $null
    $quantifier = ''
    $implied = $false
    $count = $null
    $q = $from
    while ($q -lt $readings.Count -and $negative[$q]) { $q++ }
    if ($q -lt $readings.Count -and $upos[$q] -notin 'NOUN', 'PROPN', 'VERB', 'AUX') {
        $form = "$($readings[$q].Form)".ToLowerInvariant()
        # (or a form of one, read with its lemma: "nessuna" is "nessuno", which says none)
        $base = $(if ($upos[$q] -in 'DET', 'PRON' -and $readings[$q].Lemma) { "$($readings[$q].Lemma)".ToLowerInvariant() } else { '' })
        if (-not $logic.Kinds.ContainsKey($form) -and $base -and $logic.Kinds.ContainsKey($base)) { $form = $base }
        if ($logic.Kinds.ContainsKey($form)) {
            $quantity = $logic.Kinds[$form]
            $quantifier = $form
            $q++
            if ($q -lt $readings.Count -and $upos[$q] -eq 'DET' -and (& $has $q 'PronType=Art')) { $q++ }
            $from = $q
        }
        elseif ($q + 2 -lt $readings.Count -and $upos[$q] -eq 'ADP' -and $upos[$q + 1] -eq 'DET' -and (& $has ($q + 1) 'PronType=Art') -and
            $of[$q] -eq $of[$q + 1] -and $upos[$q + 2] -in 'NOUN', 'ADJ') {
            # (one written word for a preposition and its article, first: the language's article of some, as "des" in
            # "des chats sont noirs", where nothing comes before to go "of" from)
            $quantity = 'some'
            $implied = $true
            $from = $q + 2
        }
        elseif ($null -ne ($counted = Get-LambekCategoryCount -Readings $readings -At $q -Language $Language -Surface $surface)) {
            # (how many said with words learned before a number: "au moins trois", "au plus deux", "exactement deux".
            # At least one said is some; at most, and so many asked, only for the reading of counts)
            $least = $counted.Least
            $most = $counted.Most
            $onlyCounted = $Question -or $null -eq $least -or $least -lt 1
            if ($onlyCounted -and -not $Counting) { return $null }
            $quantity = 'some'
            $implied = $true
            $from = $counted.Next
            $count = [pscustomobject]@{ Least = $least; Most = $most; Start = $counted.Start }
        }
        elseif ($q + 1 -lt $readings.Count -and $upos[$q + 1] -in 'NOUN', 'ADJ') {
            # (a number of things, an article that says not which, or a word the tags say does not say which ("quelques",
            # "plusieurs", PronType=Ind): at least one, as "some" says. "trois chats sont noirs", "un Irlandais a recu le
            # prix": some are. Only a number the language writes and that is one or more: "zero" and "moins de trois"
            # say no such thing)
            $count = $null
            if ($upos[$q] -eq 'NUM') {
                $said = "$($readings[$q].Form)"
                $numbers = (Get-LambekLexicon -Language $Language).Numbers
                if ($said -match '^\d+$') { $count = [long] $said }
                elseif ($numbers) {
                    # (as the dictionary writes it, with its accents or without)
                    foreach ($spelled in @($said.ToLowerInvariant(), (ConvertTo-LambekNormalizedText -Text $said))) {
                        if ($numbers.ContainsKey($spelled) -and "$($numbers[$spelled])" -match '^\d+$') { $count = [long] "$($numbers[$spelled])"; break }
                    }
                }
            }
            # (a word that says not which only in the plural: one said of one thing may say none, as "nessuna" or "nul"
            # do where a tagger reads them so; one that says it of several says there are some. Never a word that
            # says not)
            $denies = (& $has $q 'Polarity=Neg') -or (& $has $q 'PronType=Neg')
            $which = ((& $has $q 'Definite=Ind') -and (& $has $q 'PronType=Art')) -or ((& $has $q 'PronType=Ind') -and (& $has $q 'Number=Plur') -and -not $Question)
            $article = $upos[$q] -eq 'DET' -and -not $denies -and $which
            # (told, "trois" and "plusieurs" say at least one; asked, they ask for more than one, which "some" does not
            # answer: "un seul comptable" says nothing of whether "plusieurs comptables" came. An article asks for one)
            if (($null -ne $count -and $count -ge 1 -and (-not $Question -or $count -eq 1)) -or $article) {
                $quantity = 'some'
                $implied = $true
                $from = $q + 1
                if ($null -ne $count) { $count = [pscustomobject]@{ Least = $count; Most = $null; Start = $q } }
            }
            elseif ($Counting -and $Question -and $null -ne $count -and $count -ge 2) {
                # (asked of so many: "trois chats sont-ils noirs ?", for the reading of counts)
                $quantity = 'some'
                $implied = $true
                $from = $q + 1
                $count = [pscustomobject]@{ Least = $count; Most = $null; Start = $q }
            }
            else { $count = $null }
        }
    }

    # The verb: what is said after the one or the kind
    $main = $null
    $objectFrom = $null
    $copula = $null
    $subjectEnd = $null
    $v = $null
    $clauseAt = $null
    if ($front) {
        # (asked first: the copula is followed by the one and what it is, where the one ends is cut below; any other
        # verb that asks, by the one and the verb: "does my phone have a sensor")
        if (& $isCopula $first) { $copula = $first }
        elseif ($alone) { $main = $first }
        else {
            $after = @($verbal | Where-Object { $_ -gt $from -and $upos[$_] -eq 'VERB' })
            if ($after.Count -eq 0) { return $null }
            $main = $after[0]
            $subjectEnd = $main
            # (asked first with a verb its treebanks also write as a helper, the verb after it in its past participle:
            # helping it, "hat Tom gegessen")
            if ($upos[$first] -eq 'VERB' -and (& $has $main 'VerbForm=Part')) {
                $tags = $null
                if ($model.Tags.TryGetValue("$($readings[$first].Form)".ToLowerInvariant(), [ref] $tags) -and @($tags | Where-Object { "$_".StartsWith('AUX|') }).Count -gt 0) { $upos[$first] = 'AUX' }
            }
            # (asked with a verb that changes what is said: "can Klaus travel", the verb is "can", what follows what it
            # says; "does Klaus travel" is only "travel")
            if ($upos[$first] -eq 'AUX' -and (& $has $main 'VerbForm=Inf') -and
                (ConvertTo-LambekNormalizedText -Text "$($readings[$first].Lemma)") -notin @(Get-LambekCategorySupport -Language $Language)) {
                $objectFrom = $main
                $main = $first
            }
        }
    }
    else {
        $verb = @($verbal | Where-Object { $_ -ge $from })
        if ($verb.Count -eq 0) { return $null }
        $v = $verb[0]
        # (the one or the kind said with what it does, after a pronoun that says which, before what is said of it: "les
        # chats qui sont noirs aiment le lait", "toute personne qui a le droit de vivre en Europe peut circuler"; the
        # verb of the sentence is its last said in a person, the others are of the clause)
        # (a pronoun read so, or that its treebanks write so after a noun: "die" in "alle Hunde die bellen")
        $relative = {
            param($r)
            if ($upos[$r] -eq 'PRON' -and (& $has $r 'PronType=Rel')) { return $true }
            $known = $null
            return [bool] ($upos[$r - 1] -eq 'NOUN' -and $model.Tags.TryGetValue("$($readings[$r].Form)".ToLowerInvariant(), [ref] $known) -and
                @($known | Where-Object { "$_" -match '^PRON\|' -and "$_" -match '(^|\|)PronType=([^|]*,)?Rel(,|\||$)' }).Count -gt 0)
        }
        $which = @(for ($r = $from + 1; $r -lt $v; $r++) { if (& $relative $r) { $r } })
        if ($which.Count -gt 0) {
            # (the verb of the clause may be one the tagger read as a noun right after the pronoun, "dogs that bark":
            # the last verb said in a person after it is the verb of the sentence all the same)
            $finite = @($verb | Where-Object { (& $has $_ 'VerbForm=Fin') -and $_ -gt $which[0] + 1 })
            if ($finite.Count -lt 1) { return $null }
            $v = $finite[-1]
            $clauseAt = $which[0]
        }
        $subjectEnd = $v
        # (a verb the tagger read as said alone, right before one said in its past participle, that its treebanks also
        # write as a helper: helping it, "all cats have eaten" as "all cats have not eaten")
        $after = $v + 1
        while ($after -lt $readings.Count -and $negative[$after]) { $after++ }
        if ($upos[$v] -eq 'VERB' -and $after -lt $readings.Count -and $upos[$after] -eq 'VERB' -and (& $has $after 'VerbForm=Part')) {
            $tags = $null
            if ($model.Tags.TryGetValue("$($readings[$v].Form)".ToLowerInvariant(), [ref] $tags) -and @($tags | Where-Object { "$_".StartsWith('AUX|') }).Count -gt 0) { $upos[$v] = 'AUX' }
        }
        if (& $isCopula $v) { $copula = $v }
        elseif ($upos[$v] -eq 'AUX') {
            # (a verb that helps another, with only what says not between: "a mange", "don't fly")
            $next = $v + 1
            while ($next -lt $readings.Count -and $negative[$next]) { $next++ }
            # (with none, it is the verb itself: "a un chat", as the tagger may read "avoir" before its object)
            $main = $(if ($next -lt $readings.Count -and $upos[$next] -eq 'VERB') { $next } else { $v })
            # (but one that helps a verb said in its infinitive changes what is said: "can travel" is not "travels",
            # "kann fliegen" not "fliegt": it is the verb, what follows what it says. Only the word the language says
            # "does" with is no more than help: "does fly" is "flies")
            if ($main -ne $v -and (& $has $main 'VerbForm=Inf')) {
                $support = @(Get-LambekCategorySupport -Language $Language)
                if ((ConvertTo-LambekNormalizedText -Text "$($readings[$v].Lemma)") -notin $support) { $main = $v }
            }
        }
        else { $main = $v }
    }
    # (a verb said with the one that helps it into a past: "a mange", "has eaten", "ont assiste"; what it says is the
    # verb, how it is said again keeps the helper, "Tom a mange", not "Tom mange")
    $helper = $null
    if ($null -ne $main -and $upos[$main] -eq 'VERB' -and (& $has $main 'VerbForm=Part')) {
        $by = $(if ($front) { $first } elseif ($null -ne $v -and $v -ne $main) { $v } else { $null })
        if ($null -ne $by -and $by -ne $main -and $upos[$by] -eq 'AUX' -and
            (ConvertTo-LambekNormalizedText -Text "$($readings[$by].Lemma)") -notin @(Get-LambekCategorySupport -Language $Language)) { $helper = $by }
    }
    $denied = @(for ($r = $from; $r -lt $readings.Count; $r++) { if ($negative[$r]) { $r } }).Count -gt 0

    # What kind of sentence: of how many, whether it says not, whether it asks
    $generic = $false
    if (-not $quantity) {
        $end = $(if ($null -ne $clauseAt) { $clauseAt } elseif ($null -ne $subjectEnd) { $subjectEnd } else { $readings.Count })
        $nouns = @(for ($r = $from; $r -lt $end; $r++) { if ($upos[$r] -in 'NOUN', 'PROPN', 'PRON') { $r } })
        # (never a name the tagger read as a plural here, "Jonas e um cao", "Lukas sind Studenten": a word its treebanks
        # saw only as a name, or, never seen there, its dictionary gives only as a name; nor one whose verb is said
        # of one, "e" of "Jonas e um cao")
        $named = $false
        if ($nouns.Count -gt 0) {
            $form = "$($readings[$nouns[-1]].Form)"
            $seen = $null
            $entries = $null
            if ($model.Tags.TryGetValue($form.ToLowerInvariant(), [ref] $seen) -and @($seen).Count -gt 0) {
                $named = @($seen | Where-Object { "$_".StartsWith('NOUN|') }).Count -eq 0 -and @($seen | Where-Object { "$_".StartsWith('PROPN|') }).Count -gt 0
            }
            elseif ($model.Lexicon -and $model.Lexicon.TryGet($form, [ref] $entries) -and @($entries).Count -gt 0) {
                $named = @($entries | Where-Object { "$($_.Upos)" -eq 'NOUN' }).Count -eq 0 -and @($entries | Where-Object { "$($_.Upos)" -eq 'PROPN' }).Count -gt 0
            }
            if ($null -ne $v -and (& $has $v 'Number=Sing')) { $named = $true }
        }
        if ($nouns.Count -gt 0 -and $upos[$nouns[-1]] -eq 'NOUN' -and (& $has $nouns[-1] 'Number=Plur') -and -not $named) {
            $generic = $true
            $quantity = 'all'
            # (the article of the plural is its word of how many: "les")
            if ($upos[$from] -eq 'DET' -and (& $has $from 'Definite=Def') -and (& $has $from 'Number=Plur')) { $quantifier = "$($readings[$from].Form)".ToLowerInvariant(); $from++ }
        }
    }
    # (some said with no word of some is said again with the language's own, agreed with the kind it is of: "des
    # chats sont noirs" is answered "certains chats sont noirs", "des souris", "certaines souris"; one of them, as it
    # was said)
    if ($implied) {
        $end = $(if ($null -ne $subjectEnd) { $subjectEnd } else { $readings.Count })
        $nouns = @(for ($r = $from; $r -lt $end; $r++) { if ($upos[$r] -eq 'NOUN') { $r } })
        if ($nouns.Count -gt 0 -and (& $has $nouns[-1] 'Number=Plur')) {
            # (the gender an adjective that agrees with it says first, as a noun may be written the same in both:
            # "souris")
            $agreeing = @(for ($r = $nouns[-1] + 1; $r -lt $readings.Count; $r++) { if ($upos[$r] -eq 'ADJ' -and (& $has $r 'Number=Plur') -and "|$($readings[$r].Feats)|" -match '\|Gender=') { $r } })
            $by = $(if ($agreeing.Count -gt 0) { $agreeing[0] } else { $nouns[-1] })
            $gender = $(if ("|$($readings[$by].Feats)|" -match '\|Gender=(\w+)\|') { $Matches[1] } else { '' })
            $sentences = (Get-LambekCategoryVocabulary -Language $Language).Data['Sentences']
            foreach ($word in @($logic.Kinds.Keys | Where-Object { $logic.Kinds[$_] -eq 'some' } | Sort-Object)) {
                if (-not $sentences -or -not ($sentences.Contains("some|$word") -and $sentences.Contains("somedo|$word"))) { continue }
                $single = @($model.Read([string[]] @($word)))
                if ($single.Count -ne 1 -or "|$($single[0].Feats)|" -notmatch '\|Number=Plur\|') { continue }
                $other = $(if ("|$($single[0].Feats)|" -match '\|Gender=(\w+)\|') { $Matches[1] } else { '' })
                if ($gender -and $other -and $gender -ne $other) { continue }
                $quantifier = $word
                break
            }
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
    # (the lemma each word was read with in its sentence, for a word the dictionary does not know out of it: "caes"
    # without its accent, "animais" a verb alone and a noun here)
    $lemmas = @{}
    foreach ($reading in $readings) {
        if ("$($reading.Upos)" -notin 'NOUN', 'ADJ', 'PROPN' -or -not $reading.Lemma) { continue }
        $lemmas[(ConvertTo-LambekNormalizedText -Text "$($reading.Form)")] = ConvertTo-LambekNormalizedText -Text "$($reading.Lemma)"
    }
    $values['lemmas'] = $lemmas
    # (a verb is written with a capital only for being said first: "Aboie-t-il" is "aboie")
    $lower = { param($r) $form = "$($readings[$r].Form)"; if ($upos[$r] -in 'VERB', 'AUX' -and $form.Length -gt 0) { $form.Substring(0, 1).ToLowerInvariant() + $form.Substring(1) } else { $form } }
    if ($asking) { $values['asked'] = $true }
    $name = $(if ($individual) { 'n' } else { 's' })
    if ($alone -and $null -ne $main) {
        # (where the one ends and what is done to begins is not said; the first cut that reads, from the left)
        $values['v'] = & $lower $main
        $values['lemma'] = "$($readings[$main].Lemma)"
        for ($j = $from + 1; $j -le $readings.Count; $j++) {
            $cut = $values.Clone()
            $cut[$name] = & $text $from $j
            $object = & $text $j $readings.Count
            if ($object) { $cut['o'] = $object }
            if ($cut[$name]) { $cuts.Add($cut) }
        }
    }
    elseif ($null -ne $main) {
        $values['v'] = & $lower $main
        $values['lemma'] = "$($readings[$main].Lemma)"
        $object = & $text $(if ($null -ne $objectFrom) { $objectFrom } else { $main + 1 }) $readings.Count
        if ($object) { $values['o'] = $object }
        $subject = & $text $from $subjectEnd
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
        if (-not $item) { continue }
        if ($null -ne $helper -and $item.Verb) {
            $item.Written.Predicate = & $lower $helper
            $item.Written.Object = " $($readings[$main].Form)$($item.Written.Object)"
        }
        if ($Counting -and $count -is [pscustomobject]) {
            # (how many, for the reading of counts: what one is of, and what is said of them; and the sentence said as
            # told, with its own words: "au moins deux chats sont noirs" of "au moins deux chats sont-ils noirs")
            $verbWord = $(if ($null -ne $copula) { & $lower $copula } else { '' })
            $told = @((& $text $count.Start $from), "$($item.Written.Subject)".Trim())
            if ($item.Verb) { $told += "$($item.Written.Predicate)$($item.Written.Object)".Trim() } else { $told += @($verbWord, "$($item.Written.Predicate)".Trim()) }
            $item | Add-Member -NotePropertyName Count -NotePropertyValue ([pscustomobject]@{ Least = $count.Least; Most = $count.Most }) -Force
            $item | Add-Member -NotePropertyName Statement -NotePropertyValue ((@($told | Where-Object { $_ }) -join ' ') -replace '\s+', ' ') -Force
            if ($asking) { $item.Kind = 'askcount' }
            elseif ($null -ne $count.Most -and ($null -eq $count.Least -or $count.Least -lt 1)) { $item.Kind = 'count' }
        }
        return $item
    }
    return $null
}

function Get-LambekNotWord {
    param([string] $Language)

    # The word that says not, learned where English says "not" (Dialogue.General.Not); none for a language without it
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $general = $(if ($dialogue -and $dialogue['General']) { $dialogue['General'] } else { $null })
    if (-not $general -or -not $general.Contains('Not')) { return }
    @($general['Not']) | Where-Object { $_ } | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" }
}

function Get-LambekCategoryCount {
    param([object[]] $Readings, [int] $At, [string] $Language, [string[]] $Surface)

    # How many is said from a word on, with the words learned to say it before a number (Dialogue.General.Counting:
    # AtLeast, AtMost, Exactly, where English says "at least", "at most", "exactly"), then the number (a NUM the
    # language writes, or figures; "un" too, read as an article), then a noun or an adjective: {Least; Most; Next, the word after the number}. The
    # words as written (Surface: the written word at the first reading of each, nothing at the others: "au" is read
    # "a le"); without them, the readings
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $general = $(if ($dialogue -and $dialogue['General']) { $dialogue['General'] } else { $null })
    if (-not $general -or -not $general.Contains('Counting')) { return $null }
    if (-not $Surface) { $Surface = [string[]] @($Readings | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$($_.Form)" }) }
    if ($At -ge $Surface.Count -or -not $Surface[$At]) { return $null }
    $after = { param([int] $p) $p++; while ($p -lt $Surface.Count -and -not $Surface[$p]) { $p++ }; $p }
    $numbers = (Get-LambekLexicon -Language $Language).Numbers
    foreach ($way in 'AtLeast', 'AtMost', 'Exactly') {
        foreach ($phrase in @($general['Counting'][$way])) {
            $words = @((ConvertTo-LambekNormalizedText -Text "$phrase") -split ' ' | Where-Object { $_ })
            if ($words.Count -eq 0) { continue }
            $p = $At
            $same = $true
            foreach ($word in $words) {
                if ($p -ge $Surface.Count -or $Surface[$p] -ne $word) { $same = $false; break }
                $p = & $after $p
            }
            if (-not $same -or $p + 1 -ge $Readings.Count) { continue }
            $said = "$($Readings[$p].Form)"
            $value = $null
            if ($said -match '^\d+$') { $value = [long] $said }
            elseif ("$($Readings[$p].Upos)" -in 'NUM', 'DET' -and $numbers) {
                # (as the dictionary writes it, with its accents or without: "tres" of "tres")
                foreach ($spelled in @($said.ToLowerInvariant(), (ConvertTo-LambekNormalizedText -Text $said))) {
                    if ($numbers.ContainsKey($spelled) -and "$($numbers[$spelled])" -match '^\d+$') { $value = [long] "$($numbers[$spelled])"; break }
                }
            }
            if ($null -eq $value -or "$($Readings[$p + 1].Upos)" -notin 'NOUN', 'ADJ') { continue }
            return [pscustomobject]@{
                Least = $(if ($way -ne 'AtMost') { $value } else { $null })
                Most = $(if ($way -ne 'AtLeast') { $value } else { $null })
                Start = $At
                Next = $p + 1
            }
        }
    }
    return $null
}
