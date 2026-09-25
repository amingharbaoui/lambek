function Select-LambekTerm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Words,

        [Parameter(Mandatory)]
        [string] $Language
    )

    $lexicon = Get-LambekLexicon -Language $Language
    $terms = [System.Collections.Generic.List[string]]::new()

    # Remove stop words
    foreach ($word in $Words) {
        if (-not $lexicon.StopWords.Contains($word)) {
            $terms.Add($word)
        }
    }

    return $terms.ToArray()
}
