function Get-LambekSpellingCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Token,

        [Parameter(Mandatory)]
        [string] $Language,

        [ValidateRange(1, 10)]
        [int] $Count = 3
    )

    # Short words are too close to everything
    if ($Token.Length -lt 4 -or $Token -notmatch '^\p{L}+$') { return @() }

    # Known words and folder names, within one typing edit, found once per word. Longer words allow more:
    # a slip on a key next to the right one on top of it from 7 letters ("restart" is not "restore"), two edits from 9
    $lexicon = Get-LambekLexicon -Language $Language
    if ($lexicon.Spelling.ContainsKey($Token)) { return $lexicon.Spelling[$Token] }
    $limit = 1.0
    if ($Token.Length -ge 7) { $limit = 1.5 }
    if ($Token.Length -ge 9) { $limit = 2.0 }

    $words = [System.Collections.Generic.HashSet[string]]::new($lexicon.Vocabulary)
    foreach ($name in (Get-LambekKnownFolder).Keys) { if ($name -notmatch '\s') { [void] $words.Add($name) } }

    $neighbors = Get-LambekKeyNeighbor
    $found = foreach ($word in $words) {
        if ($word -notmatch '^\p{L}+$' -or [math]::Abs($word.Length - $Token.Length) -gt [math]::Ceiling($limit)) { continue }
        $cost = [LambekMeasure]::KeyDistance($Token, $word, $neighbors)
        if ($cost -gt 0 -and $cost -le $limit) {
            [pscustomobject]@{ Word = $word; Cost = $cost }
        }
    }

    $lexicon.Spelling[$Token] = @($found | Sort-Object Cost, Word | Select-Object -First $Count)
    return $lexicon.Spelling[$Token]
}
