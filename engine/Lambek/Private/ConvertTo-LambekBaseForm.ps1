function ConvertTo-LambekBaseForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens,

        [Parameter(Mandatory)]
        [string] $Language,

        # Words of another language in the sentence: token -> its language
        [System.Collections.IDictionary] $Borrowed
    )

    $lexicon = Get-LambekLexicon -Language $Language
    $words = [System.Collections.Generic.List[string]]::new()

    foreach ($token in $Tokens) {
        # A word of another language takes its base form there ("files" in a French sentence is "file")
        if ($Borrowed -and $Borrowed.Contains($token)) {
            $other = Get-LambekLexicon -Language $Borrowed[$token]
            if ($other.BaseForms.ContainsKey($token)) { $words.Add($other.BaseForms[$token]) } else { $words.Add($token) }
            continue
        }
        # Entity tags, stop words, guard words, and known words stay as they are
        $isTag = $token -match '^_[a-z]+_$'
        $isGuard = $token -in $lexicon.Negations -or $token -in $lexicon.Exclusions
        $isKnown = $lexicon.StopWords.Contains($token) -or ($lexicon.Vocabulary.Contains($token) -and -not $lexicon.BaseForms.ContainsKey($token))
        if ($isTag -or $isGuard -or $isKnown) {
            $words.Add($token)
        }
        # Base forms
        elseif ($lexicon.BaseForms.ContainsKey($token)) {
            $words.Add($lexicon.BaseForms[$token])
        }
        # A form of a known word, read in the dictionary ("supprimons": supprimer, "copied": copy)
        elseif ($known = Get-LambekKnownLemma -Token $token -Language $Language -Lexicon $lexicon) {
            $words.Add($known)
        }
        # Plurals
        elseif ($token.Length -gt 4 -and $token.EndsWith('s') -and -not $token.EndsWith('ss')) {
            $words.Add($token.Substring(0, $token.Length - 1))
        }
        else {
            $words.Add($token)
        }
    }

    return $words.ToArray()
}

function Get-LambekKnownLemma {
    param([string] $Token, [string] $Language, [pscustomobject] $Lexicon)

    # Only words: never a number, a tag or a name with digits
    if ($Token.Length -lt 3 -or $Token -notmatch '^\p{L}+$') { return $null }
    $dictionary = Get-LambekDictionary -Language $Language
    if (-not $dictionary) { return $null }

    # Verbs first (a command starts with one), then nouns, adjectives and adverbs; the lemma must be a word Lambek knows
    $order = @{ v = 0; n = 1; a = 2; r = 3 }
    $found = foreach ($lemma in $dictionary.Lemmas($Token, $Language)) {
        $word = $lemma.Lemma
        if ($word -eq $Token -or -not $Lexicon.Vocabulary.Contains($word)) { continue }
        if ($Lexicon.BaseForms.ContainsKey($word)) { $word = $Lexicon.BaseForms[$word] }
        $rank = 9
        if ($order.ContainsKey($lemma.Pos)) { $rank = $order[$lemma.Pos] }
        [pscustomobject]@{ Word = $word; Rank = $rank }
    }
    $best = @($found | Sort-Object Rank, @{ Expression = { $_.Word }; Descending = $false } | Select-Object -First 1)
    if ($best.Count -eq 0) { return $null }
    return $best[0].Word
}
