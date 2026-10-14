function Resolve-LambekCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # General rules told in words, and what follows from them, exactly:
    #   "tous les chats de ma soeur sont noirs", "Minou est un chat de ma soeur", "Minou est-il noir ?" -> yes, and why;
    #   "aucun chien n'est un chat", "Rex est un chien", "Rex est-il un chat ?" -> no, and why;
    #   "certains chats sont gris", "Tom est un chat", "Tom est-il gris ?" -> it cannot be concluded: "certains" says not which.
    # Every sentence of the message must read as one of these, or nothing is taken. What is told is kept as told; what
    # is asked is answered yes, no, or that it cannot be known, never guessed (see Category.cs)
    if ($Text -notmatch '\p{L}') { return $null }
    # The answer to the question Lambek asked when it could not conclude: "oui" tells what the question asked,
    # and the question that could not be answered is answered again. Anything else said, the question is dropped
    $pending = Get-LambekCategoryPending
    if ($pending) {
        Set-LambekCategoryPending -Pending $null
        $answer = Test-LambekCategoryAnswer -Text $Text -Language $pending.Language
        if ($answer) {
            $told = $(if ($answer -eq 'yes') { $pending.Yes } else { $pending.No })
            $sentences = @(Split-LambekCategorySentence -Text "$told. $($pending.Question)" -Language $pending.Language)
            $result = Resolve-LambekCategoryMessage -Sentences $sentences -Language $pending.Language -Noted
            if ($result) { return $result }
        }
    }
    $detected = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text)
    $languages = @($detected) + @(Get-LambekAvailableLanguage | Where-Object { $_ -ne $detected } | Sort-Object)
    foreach ($language in $languages) {
        $words = Get-LambekCategoryVocabulary -Language $language
        if (-not $words) { continue }
        $sentences = @(Split-LambekCategorySentence -Text $Text -Language $language)
        if ($sentences.Count -eq 0) { continue }
        # A quick look first, with the shapes of the sentences only
        $shapes = @(foreach ($sentence in $sentences) {
                $shape = Read-LambekCategorySentence -Sentence $sentence.Text -Language $language -Question:$sentence.Question -Shape
                if (-not $shape) { break }
                $shape
            })
        if ($shapes.Count -ne $sentences.Count) { continue }
        # (what is told just after the question asked is the answer to it, said in full: the question is answered again)
        if ($pending -and $language -eq $pending.Language -and @($sentences | Where-Object { $_.Question }).Count -eq 0) {
            $again = @(Split-LambekCategorySentence -Text $pending.Question -Language $language)
            return Resolve-LambekCategoryMessage -Sentences (@($sentences) + @($again)) -Language $language -Noted
        }
        return Resolve-LambekCategoryMessage -Sentences $sentences -Language $language
    }
    return $null
}

function Get-LambekCategoryVocabulary {
    param([string] $Language)

    # The words and shapes of general rules in a language, with their patterns read once
    if ($null -eq $script:CategoryWords) { $script:CategoryWords = @{} }
    if ($script:CategoryWords.ContainsKey($Language)) { return $script:CategoryWords[$Language] }
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $words = $null
    if ($dialogue -and $dialogue['Categories']) {
        $data = $dialogue['Categories']
        $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        $rules = {
            param($list)
            # ("fait partie des chats" says what "est un chat" says, with the name of the kind in the plural)
            @(foreach ($rule in @($list)) {
                    if (-not $rule) { continue }
                    $kind = "$($rule[0])"
                    $member = $kind.EndsWith('member')
                    if ($member) { $kind = @{ ismember = 'is'; isnotmember = 'isnot'; askmember = 'askis' }[$kind] }
                    [pscustomobject]@{ Kind = $kind; Member = $member; Regex = [regex]::new("$($rule[1])", $options) }
                })
        }
        $words = [pscustomobject]@{
            Statements = & $rules $data['Statements']
            Listener   = & $rules $data['Listener']
            Questions  = & $rules $data['Questions']
            # (what is only imagined: "et si Tweety etait un pingouin", "would he fly")
            Imagined   = $(if ($data['Imagine']) { & $rules $data['Imagine']['Statements'] } else { @() })
            Wondered   = $(if ($data['Imagine']) { & $rules $data['Imagine']['Questions'] } else { @() })
            Data       = $data
        }
    }
    $script:CategoryWords[$Language] = $words
    return $words
}

function Split-LambekCategorySentence {
    param([string] $Text, [string] $Language)

    # The sentences of the message, each as written, in its plain form, and whether it asks. A sentence with anything
    # but words (a number, a path, a file) is no general rule: the whole message is left to the rest of Lambek
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $lead = @($data['Lead'] | Where-Object { $_ } | ForEach-Object { [regex]::Escape("$_") })
    $sentences = [System.Collections.Generic.List[object]]::new()
    foreach ($part in [regex]::Split($Text.Trim(), '(?<=[.!?;])\s+')) {
        $original = $part.Trim()
        if (-not $original) { continue }
        $question = $original -match '\?\s*$'
        $plain = ($original -replace '[.!?;]+\s*$', '').Trim()
        if ($lead.Count -gt 0) { $plain = [regex]::Replace($plain, "(?i)^(?:$($lead -join '|'))\s*,?\s+", '') }
        # (a comma only marks a pause: "normalement, les oiseaux volent")
        $plain = (($plain -replace ',', ' ') -replace '\s+', ' ').Trim()
        if (-not $plain -or $plain -notmatch "^[\p{L}'\u2019 -]+$") { return @() }
        $sentences.Add([pscustomobject]@{ Text = $plain; Original = ($original -replace '[.;]+\s*$', '').Trim(); Question = $question })
    }
    return $sentences.ToArray()
}

function Read-LambekCategorySentence {
    param(
        [string] $Sentence,
        [string] $Language,
        # A question ends with its mark; a sentence without one that only reads as a question is one too
        [switch] $Question,
        # The sentence is said by Lambek: "vous" is the user
        [switch] $Listener,
        # Only the shape: what kind of sentence it is, without the dictionary
        [switch] $Shape,
        # The sentence is read as it is, without looking for "normalement" in it
        [switch] $Strict,
        # The sentence is imagined: "Tweety etait un pingouin", "est-ce que Tweety serait gris"
        [switch] $Imagined
    )

    $words = Get-LambekCategoryVocabulary -Language $Language
    if (-not $words) { return $null }
    # "normalement, les oiseaux volent", "la plupart des oiseaux volent": a rule about every one that holds unless
    # something told says otherwise. It must read as such a rule once the word is taken out
    if (-not $Question -and -not $Strict) {
        $usual = @(Get-LambekCategoryUsual -Sentence $Sentence -Language $Language)
        if ($usual.Count -gt 0) {
            foreach ($rest in $usual) {
                $read = Read-LambekCategorySentence -Sentence $rest -Language $Language -Listener:$Listener -Shape:$Shape -Strict
                if (-not $read -or $read.Kind -notin 'all', 'no') { continue }
                $read | Add-Member -NotePropertyName Default -NotePropertyValue $true -Force
                return $read
            }
            return $null
        }
    }
    $lists = @()
    if (-not $Question) {
        if ($Listener) { $lists += , @($words.Listener) }
        if ($Imagined) { $lists += , @($words.Imagined) }
        $lists += , @($words.Statements)
    }
    if ($Imagined) { $lists += , @($words.Wondered) }
    $lists += , @($words.Questions)
    foreach ($list in $lists) {
        foreach ($rule in $list) {
            $match = $rule.Regex.Match($Sentence)
            if (-not $match.Success) { continue }
            if ($Shape) { return [pscustomobject]@{ Kind = $rule.Kind } }
            $read = ConvertTo-LambekCategoryItem -Kind $rule.Kind -Match $match -Language $Language -Listener:$Listener -Member:$rule.Member
            if ($read) { return $read }
        }
    }
    return $null
}

function ConvertTo-LambekCategoryItem {
    param([string] $Kind, [System.Text.RegularExpressions.Match] $Match, [string] $Language, [switch] $Listener, [switch] $Member)

    # What the parts of a sentence are: the quantifier, the kind of things, the one named, what is said of them.
    # Parts side by side ("is my sister a student", "tous les chats de ma soeur aiment le lait") are cut where they all
    # read: the first cut that does, from the left
    $groups = $Match.Groups
    $group = { param($name) if ($groups[$name].Success) { $groups[$name] } else { $null } }
    $values = @{}
    foreach ($name in 'q', 's', 'n', 'p', 'v', 'o') { $found = & $group $name; if ($found) { $values[$name] = $found.Value } }
    $next = { param($a, $b) $a -and $b -and $a.Index + $a.Length + 1 -eq $b.Index }
    $who = $(if (& $group 's') { 's' } elseif (& $group 'n') { 'n' } else { $null })
    $cuts = @($values)
    if ($who -and (& $next (& $group $who) (& $group 'p'))) {
        $span = "$($values[$who]) $($values['p'])"
        $cuts = @(foreach ($space in [regex]::Matches($span, ' ')) {
                $cut = $values.Clone()
                $cut[$who] = $span.Substring(0, $space.Index)
                $cut['p'] = $span.Substring($space.Index + 1)
                $cut
            })
    }
    elseif ($who -and (& $next (& $group $who) (& $group 'v'))) {
        # (the verb is one word; what follows it right away is its object)
        $span = "$($values[$who]) $($values['v'])"
        $tail = $(if (& $next (& $group 'v') (& $group 'o')) { " $($values['o'])" } else { '' })
        $parts = @(($span + $tail) -split ' ')
        $cuts = @(for ($j = 1; $j -lt $parts.Count; $j++) {
                if (-not $tail -and $j -ne $parts.Count - 1) { continue }
                $cut = $values.Clone()
                $cut[$who] = ($parts[0..($j - 1)] -join ' ')
                $cut['v'] = $parts[$j]
                if ($tail) { if ($j -lt $parts.Count - 1) { $cut['o'] = ($parts[($j + 1)..($parts.Count - 1)] -join ' ') } else { $cut.Remove('o') } }
                $cut
            })
    }
    foreach ($cut in $cuts) {
        $item = Read-LambekCategoryPart -Kind $Kind -Values $cut -Language $Language -Listener:$Listener -Member:$Member
        if ($item) { return $item }
    }
    return $null
}

function Read-LambekCategoryPart {
    param([string] $Kind, [hashtable] $Values, [string] $Language, [switch] $Listener, [switch] $Member)

    $item = [pscustomobject]@{
        Kind       = $Kind
        Member     = [bool] $Member
        Default    = $false
        Quantifier = ''
        Subject    = $null
        Individual = $null
        Predicate  = $null
        Verb       = $false
        Written    = [pscustomobject]@{ Subject = ''; Predicate = ''; Object = '' }
    }
    if ($Values.ContainsKey('q')) { $item.Quantifier = ConvertTo-LambekNormalizedText -Text $Values['q'] }
    if ($Values.ContainsKey('s')) {
        $item.Subject = ConvertTo-LambekCategoryTerm -Text $Values['s'] -Language $Language -Bare
        if (-not $item.Subject) { return $null }
        $item.Written.Subject = $Values['s'].Trim()
    }
    if ($Values.ContainsKey('n')) {
        $item.Individual = ConvertTo-LambekCategoryIndividual -Text $Values['n'] -Language $Language -Listener:$Listener
        if (-not $item.Individual) { return $null }
        $item.Written.Subject = $Values['n'].Trim()
    }
    if ($Values.ContainsKey('p')) {
        $item.Predicate = ConvertTo-LambekCategoryTerm -Text $Values['p'] -Language $Language
        if (-not $item.Predicate) { return $null }
        $item.Written.Predicate = $Values['p'].Trim()
    }
    elseif ($Values.ContainsKey('v')) {
        $lemma = Get-LambekCategoryLemma -Word (ConvertTo-LambekNormalizedText -Text $Values['v']) -Language $Language -Verb
        if (-not $lemma) { return $null }
        # "aiment le lait": the verb and what it is done to are one thing said ("aimer le lait"), whatever the article
        $atom = "v:$lemma"
        if ($Values.ContainsKey('o') -and $Values['o']) {
            $object = ConvertTo-LambekCategoryTerm -Text $Values['o'] -Language $Language -Object
            if (-not $object) { return $null }
            $atom += ">$($object.Atoms -join '+')"
            $item.Written.Object = " $($Values['o'].Trim())"
        }
        $item.Predicate = [pscustomobject]@{ Atoms = @($atom) }
        $item.Verb = $true
        $item.Written.Predicate = $Values['v'].Trim()
    }
    # A question about who has no one named; anything else is about someone or about a kind of things
    if (-not $item.Predicate -or ($Kind -ne 'askwho' -and -not $item.Subject -and -not $item.Individual)) { return $null }
    return $item
}

function Get-LambekCategoryToken {
    param([string] $Text)

    # The words, plain, an elided word on its own: "l'animal" is "l" and "animal"
    return @((ConvertTo-LambekNormalizedText -Text $Text) -split "[\s'\u2019]+" | Where-Object { $_ })
}

function ConvertTo-LambekCategoryTerm {
    param(
        [string] $Text,
        [string] $Language,
        # Said without its article ("chats" in "tous les chats")
        [switch] $Bare,

        # What a verb is done to ("le lait", "de lait" after "ne... pas")
        [switch] $Object
    )

    # A kind of things, as the properties it puts together: "un chat noir de ma soeur" is chat, noir and "de ma soeur".
    # Every word must be one the dictionary knows as a noun or an adjective, each taken in its base form ("noires" is
    # "noir"), and none a small word of the language; what follows "de" is one property, whose it is said the same
    # from either side ("ma soeur", "votre soeur")
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $lexicon = Get-LambekLexicon -Language $Language
    $general = $lexicon.Dialogue['General']
    $tokens = @(Get-LambekCategoryToken -Text $Text)
    $articles = @($data['Articles'])
    if ($Object) { $articles = @($data['ObjectArticles']) }
    if (-not $Bare -and $tokens.Count -gt 0 -and $tokens[0] -in $articles) { $tokens = @($tokens | Select-Object -Skip 1) }
    if ($tokens.Count -eq 0) { return $null }
    $of = -1
    for ($i = 1; $i -lt $tokens.Count; $i++) { if ($tokens[$i] -in @($data['Of'])) { $of = $i; break } }
    $head = @($tokens)
    $complement = @()
    if ($of -gt 0) { $head = @($tokens[0..($of - 1)]); $complement = @($tokens | Select-Object -Skip ($of + 1)) }
    if ($head.Count -gt 4) { return $null }
    $atoms = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($token in $head) {
        if ($lexicon.StopWords.Contains($token)) { return $null }
        $lemma = Get-LambekCategoryLemma -Word $token -Language $Language
        if (-not $lemma) { return $null }
        [void] $atoms.Add($lemma)
    }
    if ($of -gt 0) {
        $whose = @(foreach ($token in $complement) {
                if ($token -in @($general['Owners'])) { '@' }
                elseif ($token -notin @($data['Definite'])) { $token }
            })
        # (whose it is, and of whom: "de ma soeur", never "de ma" alone)
        if (@($whose | Where-Object { $_ -ne '@' }).Count -eq 0 -or $whose.Count -gt 4) { return $null }
        [void] $atoms.Add("of:$($whose -join ' ')")
    }
    return [pscustomobject]@{ Atoms = @($atoms) }
}

function ConvertTo-LambekCategoryIndividual {
    param([string] $Text, [string] $Language, [switch] $Listener)

    # The one a sentence is about: the user ("je"; "vous" when Lambek says it), a name ("Minou", "Jean Dupont"),
    # or someone said with whose or which it is ("ma soeur", "le chat"). A pronoun, or something said with "un", is none
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $written = $Text.Trim()
    $plain = (ConvertTo-LambekNormalizedText -Text $written).Trim()
    $me = @($data['Speaker']); $you = @($data['Addressee'])
    if ($Listener) { $me, $you = $you, $me }
    if ($plain -in $me) { return [pscustomobject]@{ Key = 'speaker'; Written = $written } }
    if ($plain -in $you) { return $null }
    $small = @($general['Determiners']) + @($general['Pronouns']) + @($general['Speakers']) + @($general['Addressee']) + @($data['Articles'])
    $tokens = @(Get-LambekCategoryToken -Text $written)
    if ($tokens.Count -eq 0) { return $null }
    if ($written -cmatch '^\p{Lu}[\p{L}-]*(?: \p{Lu}[\p{L}-]*){0,2}$' -and $tokens[0] -notin $small) {
        return [pscustomobject]@{ Key = "name:$($tokens -join ' ')"; Written = $written }
    }
    if ($tokens.Count -lt 2 -or $tokens.Count -gt 4) { return $null }
    if ($tokens[0] -notin @($general['Owners']) -and $tokens[0] -notin @($data['Definite'])) { return $null }
    foreach ($token in @($tokens | Select-Object -Skip 1)) { if (-not (Get-LambekCategoryLemma -Word $token -Language $Language)) { return $null } }
    $key = @(foreach ($token in $tokens) { if ($token -in @($general['Owners'])) { '@' } elseif ($token -notin @($data['Definite'])) { $token } })
    return [pscustomobject]@{ Key = "the:$($key -join ' ')"; Written = $written }
}

function Get-LambekCategoryLemma {
    param([string] $Word, [string] $Language, [switch] $Verb)

    # The base form of a word: of an adjective, else of a noun ("grises" is "gris", "hommes" is "homme"); or, for a verb,
    # the verb it is a form of ("volent" is "voler"), never "etre" or "avoir" (they are the sentence, not what it says)
    if ($null -eq $script:CategoryLemmas) { $script:CategoryLemmas = @{} }
    $key = "$Language|$([bool] $Verb)|$Word"
    if ($script:CategoryLemmas.ContainsKey($key)) { return $script:CategoryLemmas[$key] }
    $lemma = $null
    $dictionary = Get-LambekDictionary -Language $Language
    if ($dictionary -and $Word -match '^\p{L}+(?:-\p{L}+)*$') {
        $known = @($dictionary.Lemmas($Word, $Language))
        $plain = { param($entry) ConvertTo-LambekNormalizedText -Text "$($entry.Lemma)" }
        if ($Verb) {
            $not = @((Get-LambekCategoryVocabulary -Language $Language).Data['NotVerbs'])
            $found = @($known | Where-Object { $_.Pos -eq 'v' -and (& $plain $_) -notin $not } | Select-Object -First 1)
            if ($found.Count -gt 0) { $lemma = & $plain $found[0] }
        }
        else {
            $adjectives = @($known | Where-Object { $_.Pos -eq 'a' })
            $nouns = @($known | Where-Object { $_.Pos -eq 'n' })
            if ($adjectives.Count -gt 0) {
                # (the shortest: "grise" is a form of "gris" before it is a word of its own)
                $lemma = & $plain (@($adjectives | Sort-Object -Stable { "$($_.Lemma)".Length })[0])
            }
            elseif ($nouns.Count -gt 0) {
                $lemma = & $plain (@($nouns | Sort-Object -Stable { "$($_.Lemma)".Length })[0])
            }
        }
    }
    $script:CategoryLemmas[$key] = $lemma
    return $lemma
}

function Get-LambekCategorySignature {
    param([pscustomobject] $Item)

    # What a sentence says, the same whatever words said it: to see that a sentence said back reads the same
    $who = ''
    if ($Item.Individual) { $who = $Item.Individual.Key }
    elseif ($Item.Subject) { $who = ($Item.Subject.Atoms -join '+') }
    $usual = $(if ($Item.PSObject.Properties['Default'] -and $Item.Default) { 'usual:' } else { '' })
    return "$usual$($Item.Kind)|$who|$($Item.Predicate.Atoms -join '+')"
}

function Get-LambekCategoryKnown {
    param([string] $Language, [switch] $Shape)

    # What was told, here and before, read as general rules and sentences about someone: each with the thing told it
    # comes from. Only what reads as one counts; rules told with "si" are another kind of thing
    $told = @((Get-LambekTold).ToArray())
    $here = @($told | Where-Object { $_.PSObject.Properties['Hash'] -and $_.Hash } | ForEach-Object { $_.Hash })
    $before = @((Get-LambekToldJournal).ToArray() | Where-Object { $_.Hash -notin $here })
    foreach ($fact in @($before) + @($told)) {
        if ($fact.PSObject.Properties['Condition'] -and $fact.Condition) { continue }
        if ($fact.PSObject.Properties['Deduced'] -and $fact.Deduced) { continue }
        if ("$($fact.Language)" -ne $Language -or -not $fact.Text) { continue }
        $words = "$($fact.Text)"
        if ($fact.PSObject.Properties['Said'] -and $fact.Said) { $words = "$($fact.Said)" }
        $sentence = ((($words.Trim() -replace '[.!;]+\s*$', '') -replace ',', ' ') -replace '\s+', ' ').Trim()
        if ($sentence -notmatch "^[\p{L}'\u2019 -]+$") { continue }
        if ($null -eq $script:CategoryReadings) { $script:CategoryReadings = @{} }
        $key = "$Language|$([bool] $Shape)|$sentence"
        if (-not $script:CategoryReadings.ContainsKey($key)) { $script:CategoryReadings[$key] = Read-LambekCategorySentence -Sentence $sentence -Language $Language -Shape:$Shape }
        $read = $script:CategoryReadings[$key]
        if (-not $read -or "$($read.Kind)".StartsWith('ask')) { continue }
        [pscustomobject]@{ Fact = $fact; Item = $read }
    }
}

function ConvertTo-LambekCategoryFact {
    param([pscustomobject] $Sentence, [pscustomobject] $Item, [string] $Language)

    # A sentence of the message, kept as a thing told, in the shape of every thing told
    $signature = Get-LambekCategorySignature -Item $Item
    return [pscustomobject]@{
        Action     = 'verb:category'
        Parameters = [ordered]@{}
        What       = $Sentence.Original
        Agent      = 'other'
        Name       = ''
        Wish       = $false
        Time       = $null
        Day        = $null
        Told       = $null
        Text       = $Sentence.Original
        Said       = $null
        Language   = $Language
        Hash       = $null
        Negated    = $false
        Core       = "category($signature)|"
        Form       = "category($signature)"
    }
}

function Get-LambekCategorySaid {
    param([pscustomobject] $Fact, [string] $Register = 'vous')

    # A general rule told, said back from the other side ("tous les chats de votre soeur sont noirs"), kept only when
    # reading it again gives the same; nothing otherwise (it is then quoted as it was told)
    $sentence = ConvertTo-LambekOtherSide -Text "$($Fact.Text)" -Language "$($Fact.Language)" -Register $Register
    if (-not $sentence) { return $null }
    $plain = { param($text) (((("$text".Trim()) -replace '[.!;]+\s*$', '') -replace ',', ' ') -replace '\s+', ' ').Trim() }
    $told = Read-LambekCategorySentence -Sentence (& $plain $Fact.Text) -Language "$($Fact.Language)"
    $again = Read-LambekCategorySentence -Sentence (& $plain $sentence) -Language "$($Fact.Language)" -Listener
    if (-not $told -or -not $again -or (Get-LambekCategorySignature -Item $told) -cne (Get-LambekCategorySignature -Item $again)) { return $null }
    return $sentence
}

function ConvertTo-LambekCategoryStatement {
    param([pscustomobject] $Item, [hashtable] $Atoms)

    # A sentence as clauses (see Category.cs): every one of a kind, one named, or one imagined for "certains"
    $table = $Atoms
    $index = { param($atom) if (-not $table.ContainsKey($atom)) { $table[$atom] = $table.Count + 1 }; [int] $table[$atom] }
    $s = @(); if ($Item.Subject) { $s = @($Item.Subject.Atoms | ForEach-Object { & $index $_ }) }
    $p = @($Item.Predicate.Atoms | ForEach-Object { & $index $_ })
    $notS = @($s | ForEach-Object { - $_ })
    $notP = @($p | ForEach-Object { - $_ })
    $statement = [LambekCategoryStatement]::new()
    # (a rule that holds "normalement" is no clause: it is used only where nothing told says otherwise)
    if ($Item.PSObject.Properties['Default'] -and $Item.Default) { return $statement }
    switch ($Item.Kind) {
        'all' { foreach ($atom in $p) { $statement.AddEvery([int[]] (@($notS) + @($atom))) } }
        'no' { $statement.AddEvery([int[]] (@($notS) + @($notP))) }
        'some' { $w = $statement.AddWitness(); foreach ($atom in @($s) + @($p)) { $statement.AddToWitness($w, [int[]] @($atom)) } }
        'somenot' { $w = $statement.AddWitness(); foreach ($atom in $s) { $statement.AddToWitness($w, [int[]] @($atom)) }; $statement.AddToWitness($w, [int[]] $notP) }
        { $_ -in 'is', 'does' } { foreach ($atom in $p) { $statement.AddNamed($Item.Individual.Key, [int[]] @($atom)) } }
        { $_ -in 'isnot', 'doesnot' } { $statement.AddNamed($Item.Individual.Key, [int[]] $notP) }
    }
    return $statement
}

function Get-LambekCategoryOpposite {
    param([pscustomobject] $Item, [hashtable] $Atoms, [string] $Individual, [switch] $No)

    # What would make the answer wrong, as clauses: for "yes", that it does not hold; for "no", that it does.
    # "Minou est-il noir ?": yes when Minou not noir cannot be; no when Minou noir cannot be
    $table = $Atoms
    $index = { param($atom) if (-not $table.ContainsKey($atom)) { $table[$atom] = $table.Count + 1 }; [int] $table[$atom] }
    $s = @(); if ($Item.Subject) { $s = @($Item.Subject.Atoms | ForEach-Object { & $index $_ }) }
    $p = @($Item.Predicate.Atoms | ForEach-Object { & $index $_ })
    $notS = @($s | ForEach-Object { - $_ })
    $notP = @($p | ForEach-Object { - $_ })
    $o = [LambekCategoryStatement]::new()
    $witness = { param([int[]] $units, [int[]] $clause) $w = $o.AddWitness(); foreach ($atom in $units) { $o.AddToWitness($w, [int[]] @($atom)) }; if ($clause) { $o.AddToWitness($w, $clause) } }
    $every = { param([int[]] $clause) $o.AddEvery($clause) }
    $kind = $Item.Kind
    if ($kind -in 'askis', 'askdoes', 'askwho') {
        if ($No) { foreach ($atom in $p) { $o.AddNamed($Individual, [int[]] @($atom)) } } else { $o.AddNamed($Individual, [int[]] $notP) }
    }
    elseif ($kind -eq 'askall') {
        if ($No) { foreach ($atom in $p) { & $every ([int[]] (@($notS) + @($atom))) } } else { & $witness $s $notP }
    }
    elseif ($kind -eq 'asksome') {
        if ($No) { & $witness (@($s) + @($p)) $null } else { & $every ([int[]] (@($notS) + @($notP))) }
    }
    elseif ($kind -eq 'asksomenot') {
        if ($No) { & $witness $s $notP } else { foreach ($atom in $p) { & $every ([int[]] (@($notS) + @($atom))) } }
    }
    elseif ($kind -eq 'askno') {
        if ($No) { & $every ([int[]] (@($notS) + @($notP))) } else { & $witness (@($s) + @($p)) $null }
    }
    return $o
}

function Get-LambekCategorySentence {
    param(
        [pscustomobject] $Item,
        [string] $Shape,
        [string] $Language,
        [string] $Subject = '',
        # Which shapes: the sentences of answers, or the questions Lambek asks ("Asks")
        [string] $Shapes = 'Sentences',
        # Said from the user's side, as it is kept when told: "ma soeur", "je"
        [switch] $Plain
    )

    # The sentence of an answer, made with the user's own words of the question, then said from the other side:
    # "Minou est-il noir ?" gives "Minou est noir", "suis-je mortel ?" gives "vous etes mortel". Nothing when the
    # language has no sentence for it
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $sentences = $(if ($Shapes -eq 'Imagine') { $data['Imagine']['Sentences'] } else { $data[$Shapes] })
    $who = $(if ($Subject) { $Subject } else { $Item.Written.Subject })
    $key = $Shape
    if ($Item.Verb) { $key = $(switch ($Shape) { 'is' { 'does' } 'isnot' { 'doesnot' } default { "$($Shape)do" } }) }
    elseif ($Item.PSObject.Properties['Member'] -and $Item.Member -and $Shape -in 'is', 'isnot') { $key = $(if ($Shape -eq 'is') { 'member' } else { 'notmember' }) }
    $candidates = @()
    # ("qui vole ?" is answered with its own verb: "Tweety vole", "Tweety flies")
    if ($Item.Kind -eq 'askwho' -and $Item.Verb -and $Shape -eq 'is') { $candidates += 'whodo' }
    if ($Item.Quantifier) { $candidates += "$key|$($Item.Quantifier)" }
    $speaker = $Item.Individual -and $Item.Individual.Key -eq 'speaker' -and -not $Subject
    if ($speaker) { $candidates += "$key|$(@($data['Speaker'])[0])" }
    if ($Shape -in 'is', 'isnot' -or $key -in 'member', 'notmember') { $candidates += $key }
    $template = $null
    foreach ($candidate in $candidates) { if ($sentences.Contains($candidate)) { $template = $sentences[$candidate]; break } }
    if (-not $template) { return $null }
    $built = $template -f $who, $Item.Written.Predicate, $Item.Written.Object
    foreach ($rule in @($data['Elide'])) { $built = [regex]::Replace($built, $rule[0], $rule[1]) }
    if ($Plain) { return $built }
    $turned = ConvertTo-LambekOtherSide -Text $built -Language $Language -Register 'vous'
    if (-not $turned) { return $built }
    if ($Shapes -ne 'Asks') { $turned = $turned.TrimEnd('.') }
    # (a sentence made with a small word first says it small; a name keeps its capital)
    if ($built -cmatch '^\p{Ll}') { $turned = $turned.Substring(0, 1).ToLowerInvariant() + $turned.Substring(1) }
    return $turned
}

function Resolve-LambekCategoryMessage {
    param(
        [object[]] $Sentences,
        [string] $Language,
        # What is told with the question is said back first ("C'est note. Tom est un chat."), then the answer
        [switch] $Noted
    )

    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    $quantified = 'all', 'no', 'some', 'somenot'
    # Nothing general, here or before: the sentences are for the rest of Lambek
    $shapes = @(foreach ($sentence in $Sentences) { (Read-LambekCategorySentence -Sentence $sentence.Text -Language $Language -Question:$sentence.Question -Shape).Kind })
    $asks = @($shapes | Where-Object { "$_".StartsWith('ask') })
    if ($asks.Count -gt 1) { return $null }
    $general = @($shapes | Where-Object { $_ -in $quantified }).Count -gt 0
    if (-not $general -and @(Get-LambekCategoryKnown -Language $Language -Shape | Where-Object { $_.Item.Kind -in $quantified }).Count -eq 0) { return $null }

    # Each sentence read, with the dictionary: every one must read, or nothing is taken
    $items = @(foreach ($sentence in $Sentences) {
            $read = Read-LambekCategorySentence -Sentence $sentence.Text -Language $Language -Question:$sentence.Question
            if (-not $read) { return $null }
            [pscustomobject]@{ Sentence = $sentence; Item = $read }
        })
    $known = @(Get-LambekCategoryKnown -Language $Language)
    # (the shape of a sentence only said what it may be: what it is read as says whether it is general)
    $general = @($items | Where-Object { $_.Item.Kind -in $quantified }).Count -gt 0
    if (-not $general -and @($known | Where-Object { $_.Item.Kind -in $quantified }).Count -eq 0) { return $null }

    # What is told in the message is kept as told
    $facts = @(foreach ($entry in $items) { if (-not $entry.Item.Kind.StartsWith('ask')) { ConvertTo-LambekCategoryFact -Sentence $entry.Sentence -Item $entry.Item -Language $Language } })
    $premises = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $known) { $premises.Add($entry) }
    $k = 0
    foreach ($entry in $items) { if (-not $entry.Item.Kind.StartsWith('ask')) { $premises.Add([pscustomobject]@{ Fact = $facts[$k]; Item = $entry.Item }); $k++ } }
    $atoms = @{}
    $statements = [LambekCategoryStatement[]] @($premises | ForEach-Object { ConvertTo-LambekCategoryStatement -Item $_.Item -Atoms $atoms })
    $listed = { param([int[]] $indices) @(foreach ($i in $indices) { "- $(Format-LambekFact -Fact $premises[$i].Fact -Language $Language -Register 'vous' -Bare)" }) }
    $lines = [System.Collections.Generic.List[string]]::new()

    $question = @($items | Where-Object { $_.Item.Kind.StartsWith('ask') })
    if ($question.Count -eq 0) {
        # Told: said back, and said at once when it cannot be true with what was told before
        $shape = 'Noted'
        if ($script:Incognito) { $shape += 'Here' }
        $lines.Add(($say[$shape] -f (@($facts | ForEach-Object { Format-LambekFact -Fact $_ -Language $Language -Register 'vous' }) -join ' ')))
        if (-not [LambekCategories]::Satisfiable($statements)) {
            $lines.Add($data['Clash'])
            foreach ($line in & $listed ([LambekCategories]::Smallest($statements, $null))) { $lines.Add($line) }
        }
        Set-LambekLastProof
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }

    # What was told cannot all be true: nothing follows from it, and it is said which sentences
    if (-not [LambekCategories]::Satisfiable($statements)) {
        $lines.Add($data['Contradiction'])
        foreach ($line in & $listed ([LambekCategories]::Smallest($statements, $null))) { $lines.Add($line) }
        Set-LambekLastProof
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }

    $ask = $question[0].Item
    if ($Noted -and @($facts).Count -gt 0) {
        $shape = 'Noted'
        if ($script:Incognito) { $shape += 'Here' }
        $lines.Add(($say[$shape] -f (@($facts | ForEach-Object { Format-LambekFact -Fact $_ -Language $Language -Register 'vous' }) -join ' ')))
    }
    $because = {
        param([int[]] $indices)
        $lines.Add($data['Because'])
        foreach ($line in & $listed $indices) { $lines.Add($line) }
        Set-LambekLastProof -Facts @($indices | ForEach-Object { $premises[$_].Fact })
    }

    # "qui est noir ?": every one named that it follows of, each with what it rests on
    if ($ask.Kind -eq 'askwho') {
        $named = [System.Collections.Generic.List[object]]::new()
        foreach ($premise in $premises) {
            $one = $premise.Item.Individual
            if ($one -and @($named | Where-Object { $_.Key -eq $one.Key }).Count -eq 0) { $named.Add($one) }
        }
        $found = [System.Collections.Generic.List[object]]::new()
        $used = [System.Collections.Generic.SortedSet[int]]::new()
        foreach ($one in $named) {
            $opposite = Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $one.Key
            $support = [LambekCategories]::Smallest($statements, $opposite)
            if ($null -eq $support) { continue }
            $found.Add($one)
            foreach ($i in $support) { [void] $used.Add($i) }
        }
        if ($found.Count -eq 0) { Set-LambekLastProof; return [pscustomobject]@{ Language = $Language; Reply = $data['WhoUnknown']; Facts = $facts } }
        if ($found.Count -eq 1) {
            $only = Get-LambekCategorySentence -Item $ask -Shape 'is' -Language $Language -Subject $found[0].Written
            if ($found[0].Key -eq 'speaker') {
                $speaking = $ask.PSObject.Copy(); $speaking.Individual = $found[0]
                $only = Get-LambekCategorySentence -Item $speaking -Shape 'is' -Language $Language
            }
            $lines.Add("$($only.Substring(0, 1).ToUpperInvariant())$($only.Substring(1)).")
        }
        else {
            $names = @($found | ForEach-Object { Get-LambekProblemShown -Holder ([pscustomobject]@{ Key = $(if ($_.Key -eq 'speaker') { 'speaker' } else { "other:$($_.Key)" }); Written = $_.Written }) -Language $Language })
            $list = "$(($names[0..($names.Count - 2)]) -join ', ') $($data['And']) $($names[-1])"
            $lines.Add("$($list.Substring(0, 1).ToUpperInvariant())$($list.Substring(1)).")
        }
        & $because ([int[]] @($used))
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }

    $individual = ''
    if ($ask.Individual) { $individual = $ask.Individual.Key }
    $yes = [LambekCategories]::Smallest($statements, (Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $individual))
    $no = $null
    if ($null -eq $yes) { $no = [LambekCategories]::Smallest($statements, (Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $individual -No)) }
    $answers = @{
        askis      = @('is', 'isnot')
        askdoes    = @('is', 'isnot')
        askall     = @('all', 'notall')
        asksome    = @('some', $null)
        asksomenot = @('somenot', 'notsomenot')
        askno      = @('no', $null)
    }
    $pair = $answers[$ask.Kind]
    # Nothing follows for sure: what holds "normalement" may say what to suppose
    if ($null -eq $yes -and $null -eq $no -and $ask.Kind -in 'askis', 'askdoes') {
        $usual = Resolve-LambekCategoryUsual -Ask $ask -Premises $premises.ToArray() -Statements $statements -Atoms $atoms -Language $Language
        if ($usual) {
            foreach ($line in $usual.Lines) { $lines.Add($line) }
            Set-LambekLastProof -Facts $usual.Facts
            return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
        }
    }
    if ($null -ne $yes -or $null -ne $no) {
        $answer = $(if ($null -ne $yes) { 'Yes' } else { 'No' })
        $shape = $(if ($null -ne $yes) { $pair[0] } else { $pair[1] })
        $sentence = $null
        if ($shape) { $sentence = Get-LambekCategorySentence -Item $ask -Shape $shape -Language $Language }
        if ($sentence) { $lines.Add(($data[$answer] -f $sentence)) }
        elseif ($answer -eq 'No' -and $ask.Kind -eq 'asksome') { $lines.Add($data['NoneThere']) }
        else { $lines.Add($data["$($answer)Short"]) }
        & $because ([int[]] $(if ($null -ne $yes) { $yes } else { $no }))
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }

    # Neither follows: it is said, with what was told that may look as if it did
    $sentence = Get-LambekCategorySentence -Item $ask -Shape $pair[0] -Language $Language
    if (-not $sentence) { $sentence = $question[0].Sentence.Original.TrimEnd('?').Trim() }
    $lines.Add(($data['Unknown'] -f ($say['Quote'] -f $sentence)))
    $asked = @($ask.Predicate.Atoms)
    foreach ($premise in $premises) {
        if ($premise.Item.Kind -notin 'some', 'somenot') { continue }
        if (@($premise.Item.Predicate.Atoms | Where-Object { $_ -in $asked }).Count -eq 0) { continue }
        # (said back as everything told is: "<<Certains chats sont gris>> ne dit pas lesquels")
        $said = Get-LambekFactSentence -Fact $premise.Fact -Register 'vous'
        $quoted = $(if ($said) { $say['Quote'] -f $said.Trim().TrimEnd('.') } else { $say['Quote'] -f "$($premise.Fact.Text)".Trim().TrimEnd('.') })
        $lines.Add(($data['Which'] -f $quoted))
    }
    # "certains chats sont-ils noirs ?" when all of them are, but nothing says there are any
    $exists = $null
    if ($ask.Kind -eq 'asksome') { $exists = [pscustomobject]@{ Kind = 'askall'; Subject = $ask.Subject; Predicate = $ask.Predicate } }
    if ($ask.Kind -eq 'asksomenot') { $exists = [pscustomobject]@{ Kind = 'askno'; Subject = $ask.Subject; Predicate = $ask.Predicate } }
    if ($exists -and $null -ne [LambekCategories]::Smallest($statements, (Get-LambekCategoryOpposite -Item $exists -Atoms $atoms -Individual ''))) {
        $lines.Add(($data['Exist'] -f $ask.Written.Subject))
    }
    # The question that would settle it, kept until the next message: "oui" or "non" is then its answer
    $decide = Find-LambekCategoryQuestion -Ask $ask -Premises $premises.ToArray() -Statements $statements -Atoms $atoms -Language $Language
    if ($decide) {
        foreach ($line in $decide.Lines) { $lines.Add($line) }
        Set-LambekCategoryPending -Pending ([pscustomobject]@{ Language = $Language; Question = $question[0].Sentence.Original; Yes = $decide.Yes; No = $decide.No })
    }
    Set-LambekLastProof
    return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
}
