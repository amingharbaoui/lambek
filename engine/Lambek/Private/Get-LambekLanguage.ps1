function Get-LambekLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens,

        # The text as it was typed, when there is one (its accents tell languages apart)
        [string] $Text,

        # A tie told apart by the words the forms of each language hold (for the readers of general rules; the router
        # was measured without it)
        [switch] $Forms
    )

    # The frame language of the sentence: one clear winner, otherwise the language the chat is in, otherwise English
    $scores = Get-LambekLanguageScore -Tokens $Tokens -Text $Text
    $best = ($scores.Values | Measure-Object -Maximum).Maximum
    $winners = @($scores.Keys | Where-Object { $scores[$_] -eq $best })
    if ($best -gt 0 -and $winners.Count -eq 1) { return $winners[0] }
    # A tie with the language the chat is in: the chat's ("ma tante a 9 poules", in a chat in French, is not Italian
    # because "tante" is also an Italian word)
    # (without the app to say it, the chat is in the language of the last thing told in it)
    $chat = $script:LanguageHint
    if (-not $chat -and $script:Told -and $script:Told.Count -gt 0) {
        $last = $script:Told[$script:Told.Count - 1]
        if ($last.PSObject.Properties['Language']) { $chat = "$($last.Language)" }
    }
    if ($best -gt 0 -and $chat -and $chat -in $winners) { return $chat }
    # A tie: the language whose forms, learned from its treebanks, hold the most words of the sentence ("Rex es un
    # perro": "perro" is a word of Spanish, not of French)
    if ($Forms -and $best -gt 0 -and $winners.Count -gt 1) {
        # (as typed when the text is given, with its accents; else its words)
        $written = @($(if ($Text) { "$Text" -split '[^\p{L}]+' } else { $Tokens }) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
        $held = @{}
        foreach ($winner in $winners) {
            $model = Get-LambekFormModel -Language $winner
            if (-not $model) { break }
            $held[$winner] = @($written | Where-Object { $model.Knows($_) }).Count
        }
        if ($written.Count -gt 0 -and $held.Count -eq $winners.Count) {
            $most = ($held.Values | Measure-Object -Maximum).Maximum
            $first = @($winners | Where-Object { $held[$_] -eq $most })
            if ($first.Count -eq 1) { return $first[0] }
        }
    }
    # A tie: the language of the first word only one of them has (the verb that opens a command carries its frame)
    if ($best -gt 0) {
        foreach ($token in $Tokens) {
            $lower = $token.ToLowerInvariant()
            $in = @($winners | Where-Object { (Get-LambekLexicon -Language $_).Signals.Contains($lower) })
            if ($in.Count -eq 1) { return $in[0] }
        }
    }
    if ($script:LanguageHint -and ($best -eq 0 -or $script:LanguageHint -in $winners)) { return $script:LanguageHint }
    if ($best -gt 0) {
        # A tie: English first, then French, then by name (a stable order)
        foreach ($first in 'en', 'fr') { if ($first -in $winners) { return $first } }
        return @($winners | Sort-Object)[0]
    }
    return 'en'
}

function Get-LambekLanguageToken {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # The words that can tell a language: paths, addresses, quoted names and extensions are the same in every language
    # ("C:\Data" is not the Italian "data", nor "c" the French "c'")
    $plain = $Text -replace '"[^"]*"|\u00AB[^\u00BB]*\u00BB|\u201C[^\u201D]*\u201D', ' '
    $plain = $plain -replace '(?i)\b[a-z]:[\\/]\S*|\\\\\S+|(?<!\w)/\S+|https?://\S+|(?<!\w)~[\\/]\S*|(?<![\w.])\.[a-z0-9]{1,10}\b', ' '
    return [string[]] @((ConvertTo-LambekNormalizedText -Text $plain) -split '[^\p{L}\p{N}]+' | Where-Object { $_ })
}

function Get-LambekLanguageScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens,

        # The text as it was typed, with its accents: a letter a language does not write is evidence against it
        [string] $Text
    )

    # Matrix Language Frame (Myers-Scotton): the small words of grammar (articles, prepositions, pronouns) come from the
    # language that frames the sentence, the content words may come from another. A small word counts two, any other
    # word of the language one; words every language shares count for none of them
    $key = "languages`n" + ($Tokens -join "`n") + "`n" + $Text
    $kept = $null
    if ($script:ReadCache.TryGetValue($key, [ref] $kept)) { return $kept }
    $lower = @($Tokens | ForEach-Object { $_.ToLowerInvariant() })
    $languages = @(Get-LambekAvailableLanguage)
    $lexicons = @{}
    foreach ($language in $languages) { $lexicons[$language] = Get-LambekLexicon -Language $language }
    $scores = [ordered]@{}
    foreach ($language in $languages) { $scores[$language] = 0 }
    foreach ($token in $lower) {
        $in = @($languages | Where-Object { $lexicons[$_].Signals.Contains($token) })
        if ($in.Count -eq 0 -or $in.Count -eq $languages.Count) { continue }
        foreach ($language in $in) {
            $weight = 1
            if ($lexicons[$language].StopWords.Contains($token) -or $lexicons[$language].GrammarWords.Contains($token)) { $weight = 2 }
            $scores[$language] += $weight
        }
    }
    # A word written with a letter a language never writes ("a" with a grave accent is no English) counts two against
    # it: the letters of each language come from the texts it was learned from (its word counts), none written here; a
    # language without them is left as it is. Only a word some language knows is such evidence: a name or a word cut
    # in two ("Les Miserab les") says nothing of the language of the sentence
    if ($Text) {
        $alphabets = @{}
        foreach ($language in $languages) {
            $counted = Get-LambekWordCount -Language $language
            if ($counted) {
                if ($null -eq $script:Alphabets) { $script:Alphabets = @{} }
                if (-not $script:Alphabets.ContainsKey($language)) { $script:Alphabets[$language] = [System.Collections.Generic.HashSet[char]]::new([char[]] $counted.Counts.Alphabet(0.9999)) }
                $alphabets[$language] = $script:Alphabets[$language]
            }
        }
        $plain = $Text -replace '"[^"]*"|\u00AB[^\u00BB]*\u00BB|\u201C[^\u201D]*\u201D', ' '
        $plain = $plain -replace '(?i)\b[a-z]:[\\/]\S*|\\\\\S+|(?<!\w)/\S+|https?://\S+', ' '
        foreach ($word in [regex]::Matches($plain.Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant(), '\p{L}+')) {
            $bare = ConvertTo-LambekNormalizedText -Text $word.Value
            if (-not @($languages | Where-Object { $lexicons[$_].Signals.Contains($bare) })) { continue }
            foreach ($language in $alphabets.Keys) {
                if (@($word.Value.ToCharArray() | Where-Object { -not $alphabets[$language].Contains($_) }).Count -gt 0) { $scores[$language] -= 2 }
            }
        }
    }
    $script:ReadCache[$key] = $scores
    return $scores
}

function Get-LambekBorrowedWord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens,

        [Parameter(Mandatory)]
        [string] $Language
    )

    # Code-switching: a word the frame language does not know, but another language does ("supprime les files"),
    # is read in that language; the other languages are tried from the one most present in the sentence
    $borrowed = [ordered]@{}
    $matrix = Get-LambekLexicon -Language $Language
    $scores = Get-LambekLanguageScore -Tokens $Tokens
    $others = @($scores.Keys | Where-Object { $_ -ne $Language } | Sort-Object @{ Expression = { $scores[$_] }; Descending = $true }, { $_ })
    foreach ($token in $Tokens) {
        if ($token -notmatch '^\p{L}{2,}$' -or $borrowed.Contains($token)) { continue }
        if ($matrix.StopWords.Contains($token) -or $matrix.Vocabulary.Contains($token) -or $matrix.BaseForms.ContainsKey($token) -or $matrix.TalkWords.Contains($token)) { continue }
        if ($token -in $matrix.Negations -or $token -in $matrix.Exclusions) { continue }
        foreach ($other in $others) {
            $lexicon = Get-LambekLexicon -Language $other
            if ($lexicon.Vocabulary.Contains($token) -or $lexicon.BaseForms.ContainsKey($token)) {
                $borrowed[$token] = $other
                break
            }
        }
    }
    return $borrowed
}

function Test-LambekLanguageSignal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # True when the words point to one language more than to the others
    $words = @((ConvertTo-LambekNormalizedText -Text $Text) -split '[^\p{L}\p{N}]+' | Where-Object { $_ })
    $scores = Get-LambekLanguageScore -Tokens $words
    $best = ($scores.Values | Measure-Object -Maximum).Maximum
    return $best -gt 0 -and @($scores.Values | Where-Object { $_ -eq $best }).Count -eq 1
}

function Get-LambekLanguageBelief {
    [CmdletBinding()]
    param(
        # The belief after the turns before (language -> probability), or nothing for a new chat
        [hashtable] $Belief,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens,

        # The text as it was typed (its accents tell languages apart)
        [string] $Text
    )

    # A hidden Markov model over the languages of a chat, filtered forward one turn at a time: the user mostly stays
    # in a language (0.9), and each word known in one language only is evidence for it (a word of another language
    # is ten times less likely). "ok" or a path says nothing, so the chat keeps its language; a full sentence in
    # another language moves it at once
    $languages = @(Get-LambekAvailableLanguage)
    $count = $languages.Count
    $stay = 0.9
    $switch = (1 - $stay) / [math]::Max(1, $count - 1)
    $prior = @{}
    foreach ($language in $languages) {
        $prior[$language] = 1.0 / $count
        if ($Belief) {
            $prior[$language] = 0.0
            foreach ($from in $languages) {
                $mass = 0.0
                if ($Belief.ContainsKey($from)) { $mass = [double] $Belief[$from] }
                $prior[$language] += $mass * $(if ($from -eq $language) { $stay } else { $switch })
            }
        }
    }
    $scores = Get-LambekLanguageScore -Tokens $Tokens -Text $Text
    $best = ($scores.Values | Measure-Object -Maximum).Maximum
    $posterior = @{}
    $total = 0.0
    foreach ($language in $languages) {
        # Likelihood ratio 10 per point of score behind the best language (in logs, to stay exact enough)
        $posterior[$language] = $prior[$language] * [math]::Pow(10, $scores[$language] - $best)
        $total += $posterior[$language]
    }
    foreach ($language in $languages) { $posterior[$language] = $posterior[$language] / $total }
    return $posterior
}

function Select-LambekLanguage {
    param([hashtable] $Belief)

    # The most probable language, English first on a tie
    $best = $null
    foreach ($language in @(Get-LambekAvailableLanguage | Sort-Object { $_ -ne 'en' }, { $_ })) {
        if ($null -eq $best -or $Belief[$language] -gt $Belief[$best] + 1e-12) { $best = $language }
    }
    return $best
}

function ConvertTo-LambekMatrixWord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Word,

        # The language the word comes from, and the language of the sentence
        [Parameter(Mandatory)]
        [string] $From,

        [Parameter(Mandatory)]
        [string] $To
    )

    # Through English, the pivot of the glosses of the packs: "files" in a French sentence is "fichier".
    # A word with no gloss stays as it is
    $english = $Word
    if ($From -ne 'en') {
        $english = $null
        foreach ($pack in $script:Packs.Values) {
            if ($pack.Gloss.ContainsKey($From) -and $pack.Gloss[$From].ContainsKey($Word)) { $english = $pack.Gloss[$From][$Word]; break }
        }
        if (-not $english) { return $Word }
    }
    if ($To -eq 'en') { return $english }
    # Back from English: the words of the sentence's language glossed that way, the one the pack types first (sorted)
    $found = foreach ($pack in $script:Packs.Values) {
        if (-not $pack.Gloss.ContainsKey($To)) { continue }
        foreach ($entry in $pack.Gloss[$To].GetEnumerator()) {
            if ($entry.Value -eq $english) { [pscustomobject]@{ Word = $entry.Key; Typed = $pack.Words.ContainsKey($To) -and $pack.Words[$To].ContainsKey($entry.Key) } }
        }
    }
    $best = @($found | Sort-Object @{ Expression = 'Typed'; Descending = $true }, Word | Select-Object -First 1)
    if ($best.Count -eq 0) { return $Word }
    return $best[0].Word
}
