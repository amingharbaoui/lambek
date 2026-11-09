function Get-LambekSpellingCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Token,

        [Parameter(Mandatory)]
        [string] $Language,

        [ValidateRange(1, 10)]
        [int] $Count = 3,

        # The words as the user wrote them, when no message is being planned (the one planned is read as typed): a word
        # they did not write (one a repair before made of what they wrote, "more" of "mobe") is no word to keep as it is
        [string] $Original
    )

    # Short words are too close to everything
    if ($Token.Length -lt 4 -or $Token -notmatch '^\p{L}+$') { return @() }

    # Known words and folder names, within one typing edit, found once per word. Longer words allow more:
    # a slip on a key next to the right one on top of it from 7 letters ("restart" is not "restore"), two edits from 9
    $lexicon = Get-LambekLexicon -Language $Language
    # A word the treebanks of the language write is a slip only for a word they write more often ("mora", "lives", is
    # no slip of "mova", "move": the treebanks of Portuguese write it, and "mova" less)
    $written = Get-LambekWrittenWord -Language $Language
    $often = $(if ($written) { $written.Counts.Count([LambekForms]::Bare($Token)) } else { 0 })
    $typed = $(if ($script:Typed) { $script:Typed } else { $Original })
    if ($typed -and $often -gt 0) {
        $wrote = @(([LambekForms]::Bare($typed)) -split '[^\p{L}]+')
        if ([LambekForms]::Bare($Token) -notin $wrote) { $often = 0 }
    }

    # (found once per word, and per whether it is kept as it was written)
    $key = "$Token`t$($often -gt 0)"
    if ($lexicon.Spelling.ContainsKey($key)) { return $lexicon.Spelling[$key] }
    $limit = 1.0
    if ($Token.Length -ge 7) { $limit = 1.5 }
    if ($Token.Length -ge 9) { $limit = 2.0 }

    $words = [System.Collections.Generic.HashSet[string]]::new($lexicon.Vocabulary)
    foreach ($name in (Get-LambekKnownFolder).Keys) { if ($name -notmatch '\s') { [void] $words.Add($name) } }

    $neighbors = Get-LambekKeyNeighbor
    $found = foreach ($word in $words) {
        if ($word -notmatch '^\p{L}+$' -or [math]::Abs($word.Length - $Token.Length) -gt [math]::Ceiling($limit)) { continue }
        if ($often -gt 0 -and $written.Counts.Count([LambekForms]::Bare($word)) -le $often) { continue }
        $cost = [LambekMeasure]::KeyDistance($Token, $word, $neighbors)
        if ($cost -gt 0 -and $cost -le $limit) {
            [pscustomobject]@{ Word = $word; Cost = $cost }
        }
    }

    $lexicon.Spelling[$key] = @($found | Sort-Object Cost, Word | Select-Object -First $Count)
    return $lexicon.Spelling[$key]
}
