function Get-LambekLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens
    )

    # Count stop words per language
    $english = Get-LambekLexicon -Language 'en'
    $french = Get-LambekLexicon -Language 'fr'
    $englishScore = 0
    $frenchScore = 0

    foreach ($token in $Tokens) {
        if ($english.StopWords.Contains($token)) { $englishScore++ }
        if ($french.StopWords.Contains($token)) { $frenchScore++ }
    }

    if ($frenchScore -gt $englishScore) {
        return 'fr'
    }
    return 'en'
}
