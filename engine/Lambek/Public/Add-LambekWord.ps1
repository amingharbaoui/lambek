function Add-LambekWord {
    <#
    .SYNOPSIS
        Teaches Lambek a new word: it is read as a word it already knows, with the same type.
    .EXAMPLE
        Add-LambekWord -Word purge -Meaning supprimer -Language fr
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateLength(2, 40)]
        [string] $Word,

        [Parameter(Mandatory)]
        [ValidateLength(1, 40)]
        [string] $Meaning,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z]{2}$')]
        [string] $Language
    )

    if ($Language -notin (Get-LambekAvailableLanguage)) {
        throw "Language '$Language' is not available."
    }
    Clear-LambekReadCache
    $new = ConvertTo-LambekNormalizedText -Text $Word
    $known = ConvertTo-LambekNormalizedText -Text $Meaning
    if ($new -notmatch '^\p{L}+$') {
        throw "'$Word' must be one word made of letters."
    }

    # The meaning is a word with a type in the grammar, the new word one the engine does not know yet
    $grammar = Get-LambekGrammarLexicon -Language $Language
    $lexicon = Get-LambekLexicon -Language $Language
    if ($lexicon.BaseForms.ContainsKey($known)) { $known = $lexicon.BaseForms[$known] }
    if (-not $grammar.Words.ContainsKey($known)) {
        throw "'$Meaning' is not a word Lambek knows in '$Language'."
    }
    $learned = Get-LambekLearnedWord
    $isLearned = $learned.ContainsKey($Language) -and $learned[$Language].ContainsKey($new)
    if (-not $isLearned -and ($grammar.Words.ContainsKey($new) -or $lexicon.StopWords.Contains($new) -or $lexicon.BaseForms.ContainsKey($new))) {
        throw "'$Word' is already a word Lambek knows in '$Language'."
    }

    if (-not $learned.ContainsKey($Language)) { $learned[$Language] = @{} }
    $learned[$Language][$new] = $known

    # Kept on disk, except in an incognito chat where it lasts for the session only
    if (-not $script:Incognito) { Save-LambekLearnedWord }
    $script:LexiconCache.Clear()
    $script:ActionIndexCache.Clear()

    [pscustomobject]@{ Language = $Language; Word = $new; Meaning = $known }
}

function Save-LambekLearnedWord {
    $folder = Split-Path -Path $script:LearnedPath -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }

    # Sorted, so the same words always give the same file
    $data = [ordered]@{}
    foreach ($language in @($script:LearnedWords.Keys | Sort-Object)) {
        $words = [ordered]@{}
        foreach ($word in @($script:LearnedWords[$language].Keys | Sort-Object)) { $words[$word] = $script:LearnedWords[$language][$word] }
        if ($words.Count -gt 0) { $data[$language] = $words }
    }
    Set-Content -LiteralPath $script:LearnedPath -Value ($data | ConvertTo-Json -Depth 3) -Encoding utf8
}
