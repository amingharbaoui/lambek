function Get-LambekLexicon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    # Cache
    if ($script:LexiconCache.ContainsKey($Language)) {
        return $script:LexiconCache[$Language]
    }

    # Language file
    $path = Join-Path $PSScriptRoot "../Data/Languages/$Language.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Language '$Language' is not available."
    }

    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in 'StopWords', 'BaseForms', 'SentenceQuestion', 'AmbiguityQuestion', 'RephraseQuestion',
        'Negations', 'Exclusions', 'NegationQuestion', 'ExclusionQuestion', 'UnusedQuestion', 'GuessQuestion', 'GuessOpenQuestion', 'Protected', 'Answer', 'FollowUp') {
        if (-not $data.ContainsKey($key)) {
            throw "Language file '$Language' must contain $key."
        }
    }

    # A negation or an exception in any language stops or limits an action, whatever the language of the sentence
    $guards = Get-LambekGuardWord

    $stopWords = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($word in $data.StopWords) {
        [void] $stopWords.Add($word)
    }

    $baseForms = [System.Collections.Generic.Dictionary[string, string]]::new()
    foreach ($key in $data.BaseForms.Keys) {
        $baseForms[$key] = $data.BaseForms[$key]
    }

    # Pack vocabulary
    foreach ($pack in $script:Packs.Values) {
        if ($pack.BaseForms.ContainsKey($Language)) {
            $packForms = $pack.BaseForms[$Language]
            foreach ($key in $packForms.Keys) {
                $baseForms[$key] = $packForms[$key]
            }
        }
    }

    # PowerShell's own words for the commands (del, ren, gci), when no pack already uses them, then the words learned
    $packWords = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($pack in $script:Packs.Values) {
        foreach ($key in $pack.Words.Keys) { $packWords.UnionWith([string[]] @($pack.Words[$key].Keys)) }
        foreach ($key in $pack.BaseForms.Keys) { $packWords.UnionWith([string[]] @($pack.BaseForms[$key].Keys)) }
    }
    $taught = @{}
    $learned = Get-LambekLearnedWord
    if ($learned.ContainsKey($Language)) { $taught = $learned[$Language] }
    foreach ($words in (Get-LambekCommandWord -Language $Language), $taught) {
        foreach ($word in $words.Keys) {
            if (-not $packWords.Contains($word) -and -not $stopWords.Contains($word) -and -not $baseForms.ContainsKey($word)) {
                $baseForms[$word] = $words[$word]
            }
        }
    }

    # Known words (for spelling correction)
    $vocabulary = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($key in $baseForms.Keys) {
        [void] $vocabulary.Add($key)
        [void] $vocabulary.Add($baseForms[$key])
    }
    foreach ($pack in $script:Packs.Values) {
        foreach ($key in '*', $Language) {
            if (-not $pack.Words.ContainsKey($key)) { continue }
            foreach ($word in $pack.Words[$key].Keys) {
                if ($word -notmatch '^_[a-z]+_$') { [void] $vocabulary.Add($word) }
            }
        }
    }

    # Small talk: phrases as word lists, and every word for language detection
    $talk = [ordered]@{}
    $talkWords = [System.Collections.Generic.HashSet[string]]::new()
    if ($data.ContainsKey('Talk')) {
        foreach ($name in $data.Talk.Keys) {
            $phrases = @($data.Talk[$name].Phrases | ForEach-Object { , @($_ -split ' ') })
            $talk[$name] = [pscustomobject]@{ Phrases = $phrases; Reply = $data.Talk[$name].Reply; ReplyOff = $data.Talk[$name]['ReplyOff'] }
            foreach ($phrase in $phrases) {
                foreach ($word in $phrase) { [void] $talkWords.Add($word) }
            }
        }
    }

    # Words that only make sense in this language: small words, base forms, and pack words
    $signals = [System.Collections.Generic.HashSet[string]]::new($stopWords)
    $signals.UnionWith($talkWords)
    foreach ($key in $baseForms.Keys) {
        [void] $signals.Add($key)
    }
    foreach ($pack in $script:Packs.Values) {
        if (-not $pack.Words.ContainsKey($Language)) { continue }
        foreach ($word in $pack.Words[$Language].Keys) { [void] $signals.Add($word) }
    }

    $lexicon = [pscustomobject]@{
        Language          = $Language
        StopWords         = $stopWords
        BaseForms         = $baseForms
        Vocabulary        = $vocabulary
        SentenceQuestion  = $data.SentenceQuestion
        AmbiguityQuestion = $data.AmbiguityQuestion
        AmbiguityQuestion3 = $data['AmbiguityQuestion3']
        RephraseQuestion  = $data.RephraseQuestion
        Negations         = @(@($data.Negations) + @($guards.Negations) | Select-Object -Unique)
        Exclusions        = @(@($data.Exclusions) + @($guards.Exclusions) | Select-Object -Unique)
        MannerSuffixes    = @($data['MannerSuffixes'])
        Interrogatives    = @($data['Interrogatives'])
        Numbers           = $data['Numbers']
        HowMany           = @($data['HowMany'])
        Again             = @($data['Again'])
        Define            = $data['Define']
        Calculate         = $data['Calculate']
        Dialogue          = $data['Dialogue']
        NegationQuestion  = $data.NegationQuestion
        ExclusionQuestion = $data.ExclusionQuestion
        UnusedQuestion    = $data.UnusedQuestion
        GuessQuestion     = $data.GuessQuestion
        GuessOpenQuestion = $data.GuessOpenQuestion
        Protected         = $data.Protected
        Answer            = $data.Answer
        FollowUp          = $data.FollowUp
        Talk              = $talk
        TalkWords         = $talkWords
        Signals           = $signals
        Spelling          = @{}
    }

    $script:LexiconCache[$Language] = $lexicon
    return $lexicon
}

function Get-LambekGuardWord {
    # The negations and exceptions of every language file, read once
    if ($script:GuardWords) { return $script:GuardWords }
    $negations = [System.Collections.Generic.List[string]]::new()
    $exclusions = [System.Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot '../Data/Languages') -Filter '*.json' | Sort-Object Name) {
        $data = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        foreach ($word in @($data['Negations'])) { if ($word -and -not $negations.Contains($word)) { $negations.Add($word) } }
        foreach ($word in @($data['Exclusions'])) { if ($word -and -not $exclusions.Contains($word)) { $exclusions.Add($word) } }
    }
    $script:GuardWords = [pscustomobject]@{ Negations = $negations.ToArray(); Exclusions = $exclusions.ToArray() }
    return $script:GuardWords
}
