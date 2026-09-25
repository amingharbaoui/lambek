function Select-LambekTerm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens,

        [Parameter(Mandatory)]
        [ValidateSet('en', 'fr')]
        [string] $Language
    )

    $lexicon = Get-LambekLexicon -Language $Language
    $terms = [System.Collections.Generic.List[string]]::new()

    foreach ($token in $Tokens) {
        # Entity tags
        if ($token -match '^_[a-z]+_$') {
            $terms.Add($token)
        }
        # Stop words
        elseif ($lexicon.StopWords.Contains($token)) {
            continue
        }
        # Base forms
        elseif ($lexicon.BaseForms.ContainsKey($token)) {
            $terms.Add($lexicon.BaseForms[$token])
        }
        # Plurals
        elseif ($token.Length -gt 4 -and $token.EndsWith('s') -and -not $token.EndsWith('ss')) {
            $terms.Add($token.Substring(0, $token.Length - 1))
        }
        else {
            $terms.Add($token)
        }
    }

    return $terms.ToArray()
}
