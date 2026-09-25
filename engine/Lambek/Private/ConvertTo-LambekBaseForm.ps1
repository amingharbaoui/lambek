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
        # Entity tags and stop words stay as they are
        if ($token -match '^_[a-z]+_$' -or $lexicon.StopWords.Contains($token)) {
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
