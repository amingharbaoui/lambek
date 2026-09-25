function Repair-LambekSpelling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens,

        [Parameter(Mandatory)]
        [string] $Language
    )

    $lexicon = Get-LambekLexicon -Language $Language
    $repaired = [System.Collections.Generic.List[string]]::new()
    $corrections = [System.Collections.Generic.List[object]]::new()

    foreach ($token in $Tokens) {
        $isTag = $token -match '^_[a-z]+_$'
        $isGuard = $token -in $lexicon.Negations -or $token -in $lexicon.Exclusions
        $isPlural = $token.EndsWith('s') -and $lexicon.Vocabulary.Contains($token.Substring(0, $token.Length - 1))
        $isKnown = $isTag -or $isGuard -or $isPlural -or $lexicon.StopWords.Contains($token) -or $lexicon.Vocabulary.Contains($token)

        if ($isKnown -or $token.Length -lt 4) {
            $repaired.Add($token)
            continue
        }

        # Closest known word: 1 edit for short words, 2 edits for long words
        $maxDistance = 1
        if ($token.Length -ge 7) { $maxDistance = 2 }

        $bestWord = $null
        $bestDistance = $maxDistance + 1
        foreach ($word in $lexicon.Vocabulary) {
            if ([math]::Abs($word.Length - $token.Length) -gt $maxDistance) { continue }

            $distance = (Measure-LambekEditDistance -Source $token -Target $word).Distance
            if ($distance -lt $bestDistance) {
                $bestDistance = $distance
                $bestWord = $word
            }
        }

        if ($null -ne $bestWord) {
            $repaired.Add($bestWord)
            $corrections.Add([pscustomobject]@{ From = $token; To = $bestWord; Distance = $bestDistance })
        }
        else {
            $repaired.Add($token)
        }
    }

    return [pscustomobject]@{
        Tokens      = $repaired.ToArray()
        Corrections = $corrections.ToArray()
    }
}
