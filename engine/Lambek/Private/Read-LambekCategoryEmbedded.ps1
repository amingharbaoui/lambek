function Get-LambekCategoryEmbeddingWord {
    param([string] $Language)

    # The words that put one sentence inside another, learned for each language (Dialogue.General): the verbs that say
    # what someone believes ("croire", "glauben") or knows ("savoir", "wissen"), as lemmas; the word that opens what is
    # believed ("que", "dass"); the words of a condition ("si", "wenn"); and those that may open what follows it ("alors")
    if ($null -eq $script:CategoryEmbeddingWords) { $script:CategoryEmbeddingWords = @{} }
    if ($script:CategoryEmbeddingWords.ContainsKey($Language)) { return $script:CategoryEmbeddingWords[$Language] }
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $set = {
        param($words)
        $out = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($word in @($words)) { if ($word) { [void] $out.Add((ConvertTo-LambekNormalizedText -Text "$word").TrimEnd("'")) } }
        , $out
    }
    $attitudes = $(if ($general -and $general['Attitudes']) { $general['Attitudes'] } else { @{} })
    $words = [pscustomobject]@{
        Believing  = & $set $attitudes['Believing']
        Knowing    = & $set $attitudes['Knowing']
        That       = & $set $attitudes['That']
        Conditions = & $set $(if ($general) { $general['Conditions'] })
        Then       = & $set $(if ($general) { $general['Then'] })
    }
    $script:CategoryEmbeddingWords[$Language] = $words
    return $words
}

function Read-LambekCategoryClause {
    param(
        [string] $Sentence,
        [string] $Language,
        # Said after a condition, with its verb first: "wenn Rex ein Hund ist, bellt Rex"
        [switch] $Fronted
    )

    # One sentence inside another, as a thing told: read as it is; else, its verb said last ("dass Rex eine Katze ist",
    # "als Rex een hond is") is read where a sentence alone says it, after the one it is about; else, said after a
    # condition with its verb first, read as the question it is written as, and taken as told
    $told = 'is', 'isnot', 'does', 'doesnot', 'all', 'no', 'some', 'somenot'
    $sentence = ($Sentence.Trim() -replace '[.!?;]+$', '').Trim()
    if (-not $sentence) { return $null }
    $read = Read-LambekCategoryTagged -Sentence $sentence -Language $Language
    if ($read -and $read.Kind -in $told) { return $read }
    $words = @($sentence -split '\s+' | Where-Object { $_ })
    if ($words.Count -ge 3) {
        $model = Get-LambekFormModel -Language $Language
        $last = $(if ($model) { @($model.Read([string[]] $words))[-1] } else { $null })
        if ($last -and "$($last.Upos)" -in 'VERB', 'AUX') {
            for ($k = 1; $k -lt $words.Count - 1; $k++) {
                $moved = @($words[0..($k - 1)]) + @($words[-1]) + @($words[$k..($words.Count - 2)])
                $read = Read-LambekCategoryTagged -Sentence ($moved -join ' ') -Language $Language
                if ($read -and $read.Kind -in $told) { return $read }
            }
        }
    }
    if ($Fronted) {
        $read = Read-LambekCategoryTagged -Sentence $sentence -Language $Language -Question
        if ($read -and $read.Kind -in 'askis', 'askdoes' -and $read.Individual) {
            $read.Kind = $read.Kind.Substring(3)
            return $read
        }
    }
    return $null
}

function Read-LambekCategoryEmbedded {
    param(
        [string] $Sentence,
        [string] $Language,
        [switch] $Question,
        [switch] $Shape
    )

    # A sentence with another inside it:
    #   "si Rex est un chien, Rex aboie", "Rex aboie si Rex est un chien": a rule about ones named, kind "if", with the
    #   condition (If) and what follows from it (Then), each about one named, the same or another;
    #   "Alice croit que Rex est un chat": what Alice believes, kind "believe", kept apart from what is so (Content);
    #   "Alice sait que Rex est un chien": what is so, read as the sentence inside, with who knows it (Holder);
    #   "Alice croit-elle que Tom est noir ?": asked of what Alice believes, kind "askbelieve".
    # Each part must read as a sentence of its own; otherwise nothing is read
    $words = Get-LambekCategoryEmbeddingWord -Language $Language
    $tokens = @($Sentence -split '\s+' | Where-Object { $_ })
    if ($tokens.Count -lt 3) { return $null }
    $plain = @($tokens | ForEach-Object { (ConvertTo-LambekNormalizedText -Text ($_ -replace '[,.;:!?]+$', '')) })
    $item = {
        param([string] $kind)
        [pscustomobject]@{
            Kind       = $kind
            Member     = $false
            Default    = $false
            Quantifier = ''
            Subject    = $null
            Individual = $null
            Predicate  = $null
            Verb       = $false
            Written    = [pscustomobject]@{ Subject = ''; Predicate = ''; Object = '' }
        }
    }
    $named = 'is', 'isnot', 'does', 'doesnot'

    # A condition: first ("si Rex est un chien, Rex aboie"), up to its comma or where both parts read; or last ("Rex
    # aboie si Rex est un chien")
    if (-not $Question -and $words.Conditions.Count -gt 0) {
        $at = @(for ($i = 0; $i -lt $plain.Count; $i++) { if ($words.Conditions.Contains($plain[$i])) { $i } })
        foreach ($i in $at) {
            $pairs = [System.Collections.Generic.List[object]]::new()
            if ($i -eq 0) {
                $comma = @(for ($j = 1; $j -lt $tokens.Count - 1; $j++) { if ($tokens[$j].EndsWith(',')) { $j } })
                $cuts = $(if ($comma.Count -gt 0) { @($comma[0] + 1) } else { @(($tokens.Count - 1)..2) })
                foreach ($cut in $cuts) {
                    $rest = @($tokens[$cut..($tokens.Count - 1)])
                    if ($rest.Count -gt 1 -and $words.Then.Contains((ConvertTo-LambekNormalizedText -Text $rest[0]))) { $rest = @($rest | Select-Object -Skip 1) }
                    $pairs.Add([pscustomobject]@{ If = ($tokens[1..($cut - 1)] -join ' ').TrimEnd(','); Then = ($rest -join ' '); Fronted = $true })
                }
            }
            elseif ($i -ge 2 -and $i -le $tokens.Count - 3) {
                $pairs.Add([pscustomobject]@{ If = ($tokens[($i + 1)..($tokens.Count - 1)] -join ' '); Then = ($tokens[0..($i - 1)] -join ' ').TrimEnd(','); Fronted = $false })
            }
            foreach ($pair in $pairs) {
                # (about ones named only: "si je suis fatigue, je dors" and "s'il pleut, ..." are for the memory, which
                # reasons with what is told of the one who speaks, and with what is told with no one)
                $condition = Read-LambekCategoryClause -Sentence $pair.If -Language $Language
                if (-not $condition -or $condition.Kind -notin $named -or -not $condition.Individual -or -not "$($condition.Individual.Key)".StartsWith('name:')) { continue }
                $then = Read-LambekCategoryClause -Sentence $pair.Then -Language $Language -Fronted:$pair.Fronted
                if (-not $then -or $then.Kind -notin $named) { continue }
                # ("si Rex est un chien, il aboie": the one the condition is about)
                if ($then.PSObject.Properties['Pronoun'] -and $then.Pronoun) { $then.Individual = $condition.Individual }
                if (-not $then.Individual -or -not "$($then.Individual.Key)".StartsWith('name:')) { continue }
                if ($Shape) { return [pscustomobject]@{ Kind = 'if' } }
                $rule = & $item 'if'
                $rule | Add-Member -NotePropertyName If -NotePropertyValue $condition
                $rule | Add-Member -NotePropertyName Then -NotePropertyValue $then
                # (what it is about, for what reads the kinds a message speaks of)
                $rule.Predicate = [pscustomobject]@{ Atoms = @(@($condition.Predicate.Atoms) + @($then.Predicate.Atoms) | Select-Object -Unique) }
                return $rule
            }
        }
    }

    # What someone believes or knows: who and the verb before the word that opens it, the sentence after it
    if ($words.That.Count -eq 0 -or ($words.Believing.Count -eq 0 -and $words.Knowing.Count -eq 0)) { return $null }
    for ($i = 2; $i -lt $plain.Count - 1; $i++) {
        if (-not $words.That.Contains($plain[$i])) { continue }
        $main = ($tokens[0..($i - 1)] -join ' ').TrimEnd(',')
        $content = $tokens[($i + 1)..($tokens.Count - 1)] -join ' '
        $who = Read-LambekCategoryTagged -Sentence $main -Language $Language -Question:$Question
        if (-not $who -or -not $who.Individual -or $who.Kind -notin 'does', 'askdoes') { continue }
        $atoms = @($who.Predicate.Atoms)
        if ($atoms.Count -ne 1 -or -not "$($atoms[0])".StartsWith('v:')) { continue }
        $lemma = "$($atoms[0])".Substring(2)
        $believes = $words.Believing.Contains($lemma)
        $knows = $words.Knowing.Contains($lemma)
        if (-not $believes -and -not $knows) { continue }
        # (asked: only what one believes; "Alice sait-elle que..." asks of what is so too)
        if ($Question -and -not $believes) { return $null }
        $said = Read-LambekCategoryClause -Sentence $content -Language $Language
        if (-not $said) { continue }
        $kind = $(if ($Question) { 'askbelieve' } elseif ($believes) { 'believe' } else { 'know' })
        if ($Shape) { return [pscustomobject]@{ Kind = $kind } }
        $holder = [pscustomobject]@{ Individual = $who.Individual; Written = "$($who.Written.Subject)".Trim(); Verb = $lemma; Said = $tokens[$i] }
        if ($kind -eq 'know') {
            # Known is so: the sentence inside, with who knows it
            $said | Add-Member -NotePropertyName Holder -NotePropertyValue $holder -Force
            $said | Add-Member -NotePropertyName Attitude -NotePropertyValue 'know' -Force
            return $said
        }
        $belief = & $item $kind
        $belief | Add-Member -NotePropertyName Holder -NotePropertyValue $holder
        $belief | Add-Member -NotePropertyName Content -NotePropertyValue $said
        $belief | Add-Member -NotePropertyName Attitude -NotePropertyValue 'believe'
        $belief | Add-Member -NotePropertyName Inner -NotePropertyValue $content.Trim().TrimEnd('?', '.', '!').Trim()
        return $belief
    }
    return $null
}
