function Get-LambekReferent {
    [CmdletBinding()]
    param(
        # The pronoun said: "elle", "he"
        [Parameter(Mandatory)]
        [string] $Pronoun,

        [Parameter(Mandatory)]
        [string] $Language,

        # The verb of the sentence the pronoun is the subject of: "be", "habiter"
        [string] $Verb
    )

    # Who or what a pronoun stands for, among what was told in the conversation, as Lambek already does for files:
    # the salience of Lappin and Leass (1994) - recency 100, subject 80, direct object 50, head noun 80, not in an
    # adverbial 50 - halved for each thing told since; then agreement, from the dictionaries: gender and number,
    # and for "it" something that is not a person. Two candidates as salient as each other: nobody is chosen
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    if (-not $general -or -not $general['PronounFeatures'] -or -not $general['PronounFeatures'].Contains($Pronoun)) { return $null }
    $wanted = @("$($general['PronounFeatures'][$Pronoun])" -split ' ')
    $told = @((Get-LambekTold).ToArray() | Where-Object { $_.PSObject.Properties['Language'] -and $_.Language -eq $Language })
    # A place: what was only told after a word of place ("in Lyon", "a Paris"). A place is what "it" stands for,
    # or what "il"/"elle" stands for when the sentence says where it is ("elle est en France"); never someone who
    # lives or works ("he lives in Paris" after "my sister lives in Lyon" is not about Lyon)
    $logic = $general['Logic']
    $places = @{}
    foreach ($fact in $told) {
        $where = $fact.Parameters
        if ($fact.PSObject.Properties['Values']) { $where = $fact.Values }
        if (-not $where -or -not $logic) { continue }
        foreach ($name in @($where.Keys)) {
            if ($name -in @($logic['place'])) { $places[(ConvertTo-LambekNormalizedText -Text "$($where[$name])")] = $true }
        }
    }
    $plain = if ($Verb) { ConvertTo-LambekNormalizedText -Text $Verb } else { '' }
    $copula = $plain -and ("verb:$plain" -in @($logic['copula']) -or $plain -in @($logic['copula']))
    $placeAgrees = $wanted.Count -gt 2 -and $wanted[2] -eq 'thing'
    if ($wanted.Count -le 2 -and $copula) { $placeAgrees = $true }
    $scores = [ordered]@{}
    for ($i = 0; $i -lt $told.Count; $i++) {
        $fact = $told[$i]
        $age = $told.Count - 1 - $i
        $phrases = [System.Collections.Generic.List[object]]::new()
        if ($fact.Agent -ne 'speaker' -and $fact.Name) { $phrases.Add(@($fact.Name, (100 + 80 + 80 + 50))) }
        $roles = $fact.Parameters
        if ($fact.PSObject.Properties['Values']) { $roles = $fact.Values }
        if ($roles) {
            foreach ($name in @($roles.Keys)) {
                if ("$($fact.Action)".StartsWith('verb:') -eq $false) { continue }
                $weight = 100 + 80
                if ($name -eq 'object') { $weight += 50 + 50 }
                $phrases.Add(@("$($roles[$name])", $weight))
            }
        }
        foreach ($phrase in $phrases) {
            $text = "$($phrase[0])"
            if (-not $text -or -not (Test-LambekAgreement -Phrase $text -Wanted $wanted -Language $Language)) { continue }
            $key = ConvertTo-LambekNormalizedText -Text $text
            # ("il pleut": the "il" that stands for nobody is no one a pronoun can stand for)
            if ($key -in @($general['Pronouns'])) { continue }
            if ($places.ContainsKey($key) -and -not $placeAgrees) { continue }
            $score = [double] $phrase[1] / [math]::Pow(2, $age)
            if (-not $scores.Contains($key)) { $scores[$key] = [pscustomobject]@{ Text = $text; Score = 0.0 } }
            $scores[$key].Score += $score
        }
    }
    $ranked = @($scores.Values | Sort-Object -Property Score -Descending)
    if ($ranked.Count -eq 0) { return $null }
    if ($ranked.Count -gt 1 -and $ranked[1].Score -eq $ranked[0].Score) { return $null }
    return $ranked[0].Text
}

function Test-LambekAgreement {
    param([string] $Phrase, [string[]] $Wanted, [string] $Language)

    # Gender, number and kind of a noun phrase against what the pronoun wants ("f s person", "n s thing", "x p any")
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $dictionary = Get-LambekDictionary -Language $Language
    $words = @((ConvertTo-LambekNormalizedText -Text $Phrase) -split '[^\p{L}\p{N}]+' | Where-Object { $_ })
    if ($words.Count -eq 0) { return $false }
    $head = $words[-1]
    $written = @([regex]::Matches($Phrase, '[\p{L}\p{N}]+') | ForEach-Object { $_.Value })
    $name = $written.Count -gt 0 -and $written[-1] -cmatch '^\p{Lu}'

    # Number: a plural article, or a noun that is not its own lemma
    $plural = @($words | Where-Object { $_ -in @($general['PluralDeterminers']) }).Count -gt 0
    if (-not $plural -and -not $name -and $dictionary) {
        $nouns = @($dictionary.Lemmas($head, $Language) | Where-Object { $_.Pos -eq 'n' })
        if ($nouns.Count -gt 0 -and @($nouns | Where-Object { $_.Lemma -eq $head }).Count -eq 0) { $plural = $true }
        if (@($nouns | Where-Object { "$($_.Tag)" -match 'p$' }).Count -gt 0 -and @($nouns | Where-Object { "$($_.Tag)" -match 's$' }).Count -eq 0) { $plural = $true }
    }
    $number = if ($plural) { 'p' } else { 's' }
    if ($Wanted.Count -gt 1 -and $Wanted[1] -ne $number) { return $false }

    # Gender: the noun in the dictionary (Lefff), then its article ("mon amie" is feminine whatever "mon" says),
    # then whether it is a woman or a man (WordNet and WOLF)
    $gender = $null
    if (-not $name -and $dictionary) {
        $tags = @($dictionary.Lemmas($head, $Language) | Where-Object { $_.Pos -eq 'n' } | ForEach-Object { "$($_.Tag)" })
        if (@($tags | Where-Object { $_ -match '^f' }).Count -gt 0 -and @($tags | Where-Object { $_ -match '^m' }).Count -eq 0) { $gender = 'f' }
        elseif (@($tags | Where-Object { $_ -match '^m' }).Count -gt 0 -and @($tags | Where-Object { $_ -match '^f' }).Count -eq 0) { $gender = 'm' }
    }
    if (-not $gender) {
        foreach ($word in $words) {
            if ($general['Feminine'] -and $word -in @($general['Feminine'])) { $gender = 'f' }
            elseif ($general['Masculine'] -and $word -in @($general['Masculine'])) { $gender = 'm' }
        }
    }
    $kind = $null
    if ($Language -eq 'en' -and -not $name) { $kind = Get-LambekNounKind -Noun $head }
    # A name may be a person or a place ("Paul", "Paris"): it agrees with both
    if (-not $gender -and $kind -in 'female', 'male') { $gender = @{ female = 'f'; male = 'm' }[$kind] }
    if ($Wanted[0] -in 'f', 'm' -and $gender -and $gender -ne $Wanted[0]) { return $false }
    # "he", "she": a person or a name; "it": not a person
    if ($Wanted.Count -gt 2 -and $kind) {
        $person = $kind -in 'person', 'female', 'male'
        if ($Wanted[2] -eq 'person' -and -not $person) { return $false }
        if ($Wanted[2] -eq 'thing' -and $person) { return $false }
    }
    return $true
}

function Get-LambekNounKind {
    param([string] $Noun)

    # A woman, a man, a person, or something else. A person: the first sense of the noun has "person" among its
    # hypernyms in WordNet. A woman or a man: the French words of that same sense (WOLF) are feminine or masculine
    # in Lefff ("sister" is "soeur", feminine). The two dictionaries answer together what neither says alone
    if ($null -eq $script:NounKinds) { $script:NounKinds = @{} }
    if ($script:NounKinds.ContainsKey($Noun)) { return $script:NounKinds[$Noun] }
    $dictionary = Get-LambekDictionary -Language 'en'
    $kind = 'thing'
    $first = @()
    if ($dictionary) { $first = @($dictionary.Senses($Noun, 'en', 'n') | Select-Object -First 1) }
    if ($first.Count -gt 0) {
        $people = @{}
        foreach ($word in 'person', 'female', 'male') { foreach ($synset in @($dictionary.Senses($word, 'en', 'n'))) { $people[$synset] = $true } }
        $seen = @{}
        $todo = [System.Collections.Generic.Queue[object]]::new()
        $todo.Enqueue(@($first[0], 0))
        $person = $false
        while ($todo.Count -gt 0 -and -not $person) {
            $item = $todo.Dequeue()
            if ($seen.ContainsKey($item[0]) -or $item[1] -gt 12) { continue }
            $seen[$item[0]] = $true
            if ($people.ContainsKey($item[0])) { $person = $true; break }
            foreach ($link in @($dictionary.Links($item[0]))) {
                if ($link -like 'hyper:*' -or $link -like 'inst:*') { $todo.Enqueue(@($link.Substring($link.IndexOf(':') + 1), $item[1] + 1)) }
            }
        }
        if ($person) {
            $kind = 'person'
            $french = Get-LambekDictionary -Language 'fr'
            if ($french) {
                $tags = @(foreach ($member in @($dictionary.Members($first[0], 'fr'))) {
                        $french.Lemmas($member, 'fr') | Where-Object { $_.Pos -eq 'n' } | ForEach-Object { "$($_.Tag)" }
                    })
                $feminine = @($tags | Where-Object { $_ -match '^f' }).Count
                $masculine = @($tags | Where-Object { $_ -match '^m' }).Count
                if ($feminine -gt 0 -and $masculine -eq 0) { $kind = 'female' }
                elseif ($masculine -gt 0 -and $feminine -eq 0) {
                    # French says the masculine for anyone ("le patron", "le professeur"): a man only when WordNet
                    # gives the sense an opposite that is a woman ("brother" and "sister", "man" and "woman")
                    foreach ($link in @($dictionary.Links($first[0]) | Where-Object { $_ -like 'anti:*' })) {
                        $other = $link.Substring($link.IndexOf(':') + 1)
                        $opposite = @(foreach ($member in @($dictionary.Members($other, 'fr'))) { $french.Lemmas($member, 'fr') | Where-Object { $_.Pos -eq 'n' } | ForEach-Object { "$($_.Tag)" } })
                        if (@($opposite | Where-Object { $_ -match '^f' }).Count -gt 0 -and @($opposite | Where-Object { $_ -match '^m' }).Count -eq 0) { $kind = 'male' }
                    }
                }
            }
        }
    }
    $script:NounKinds[$Noun] = $kind
    return $kind
}
