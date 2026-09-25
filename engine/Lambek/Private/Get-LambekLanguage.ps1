function Get-LambekLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens
    )

    # Count stop words per language
    $bestLanguage = 'en'
    $bestScore = 0

    foreach ($language in Get-LambekAvailableLanguage) {
        $lexicon = Get-LambekLexicon -Language $language
        $score = 0
        foreach ($token in $Tokens) {
            if ($lexicon.StopWords.Contains($token)) { $score++ }
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestLanguage = $language
        }
    }

    return $bestLanguage
}
