function ConvertTo-LambekBaseForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens,

        [Parameter(Mandatory)]
        [string] $Language
    )

    $lexicon = Get-LambekLexicon -Language $Language
    $words = [System.Collections.Generic.List[string]]::new()

    foreach ($token in $Tokens) {
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
