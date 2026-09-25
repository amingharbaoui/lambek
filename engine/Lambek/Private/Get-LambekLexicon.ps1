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
    foreach ($key in 'StopWords', 'BaseForms', 'SentenceQuestion') {
        if (-not $data.ContainsKey($key)) {
            throw "Language file '$Language' must contain $key."
        }
    }

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

    $lexicon = [pscustomobject]@{
        Language         = $Language
        StopWords        = $stopWords
        BaseForms        = $baseForms
        SentenceQuestion = $data.SentenceQuestion
    }

    $script:LexiconCache[$Language] = $lexicon
    return $lexicon
}
