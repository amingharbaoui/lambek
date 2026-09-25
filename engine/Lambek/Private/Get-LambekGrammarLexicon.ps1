function Get-LambekGrammarLexicon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    $words = @{}
    $questions = @{}

    foreach ($pack in $script:Packs.Values) {
        # Word types for all languages, then for this language
        foreach ($key in '*', $Language) {
            if (-not $pack.Words.ContainsKey($key)) { continue }

            $packWords = $pack.Words[$key]
            foreach ($word in $packWords.Keys) {
                if (-not $words.ContainsKey($word)) {
                    $words[$word] = [System.Collections.Generic.List[string]]::new()
                }
                foreach ($type in $packWords[$word]) {
                    if (-not $words[$word].Contains($type)) {
                        $words[$word].Add($type)
                    }
                }
            }
        }

        # Questions for missing types
        foreach ($base in $pack.Types.Keys) {
            if ($questions.ContainsKey($base)) { continue }

            $texts = $pack.Types[$base]
            if ($texts.ContainsKey($Language)) {
                $questions[$base] = $texts[$Language]
            }
            elseif ($texts.ContainsKey('en')) {
                $questions[$base] = $texts['en']
            }
        }
    }

    return [pscustomobject]@{
        Words     = $words
        Questions = $questions
    }
}
