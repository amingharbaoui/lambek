function Get-LambekLexicon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('en', 'fr')]
        [string] $Language
    )

    # Cache
    if ($script:LexiconCache.ContainsKey($Language)) {
        return $script:LexiconCache[$Language]
    }

    # Load file
    $path = Join-Path $PSScriptRoot "../Data/lexicon.$Language.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Lexicon file not found: $path"
    }

    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    if (-not $data.ContainsKey('StopWords') -or -not $data.ContainsKey('BaseForms')) {
        throw "Lexicon '$Language' must contain StopWords and BaseForms."
    }

    # Build lookups
    $stopWords = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($word in $data.StopWords) {
        [void] $stopWords.Add($word)
    }

    $baseForms = [System.Collections.Generic.Dictionary[string, string]]::new()
    foreach ($key in $data.BaseForms.Keys) {
        $baseForms[$key] = $data.BaseForms[$key]
    }

    $lexicon = [pscustomobject]@{
        Language  = $Language
        StopWords = $stopWords
        BaseForms = $baseForms
    }

    $script:LexiconCache[$Language] = $lexicon
    return $lexicon
}
