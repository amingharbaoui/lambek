function Find-LambekWord {
    <#
    .SYNOPSIS
        Looks a word up in the free dictionaries: its lemma, its senses with their definitions, synonyms and broader words.
    .EXAMPLE
        Find-LambekWord -Word relocate -Language en
    .EXAMPLE
        Find-LambekWord -Word supprimons -Language fr -First 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateLength(1, 80)]
        [string] $Word,

        [ValidatePattern('^[a-z]{2}$')]
        [string] $Language = 'en',

        # The most frequent senses only
        [ValidateRange(1, 50)]
        [int] $First = 5
    )

    $dictionary = Get-LambekDictionary -Language $Language -Glosses
    if (-not $dictionary) { throw "No dictionary is available for '$Language'." }
    # The English words of each sense, to see which one looks like the word
    if ($Language -ne 'en') { $null = Get-LambekDictionary -Language 'en' }

    # A phrase is looked up with "_" for its spaces, as WordNet writes it
    $key = ($Word.Trim() -replace '\s+', '_')
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($lemma in $dictionary.Lemmas($key, $Language)) {
        if ($lemma.Pos -notin 'n', 'v', 'a', 'r') { continue }
        if (-not $seen.Add("$($lemma.Lemma)|$($lemma.Pos)")) { continue }
        $senses = @($dictionary.Senses($lemma.Lemma, $Language, $lemma.Pos))
        for ($i = 0; $i -lt $senses.Count; $i++) {
            $synset = $senses[$i]
            # WOLF was built from translations: a sense whose English words look like the French one ("purger", "purge")
            # is the one it most likely means
            $cognate = 0.0
            if ($Language -ne 'en') {
                foreach ($english in @(if ($dictionary.Languages.Contains('en')) { $dictionary.Members($synset, 'en') })) {
                    $similar = [LambekMeasure]::EditSimilarity($lemma.Lemma, $english)
                    if ($similar -gt $cognate) { $cognate = $similar }
                }
            }
            $broader = foreach ($link in $dictionary.Links($synset)) {
                if ($link.StartsWith('hyper:')) { @($dictionary.Members($link.Substring(6), $Language)) | Select-Object -First 2 }
            }
            $found.Add([pscustomobject]@{
                    PSTypeName = 'Lambek.Word'
                    Word       = $Word
                    Lemma      = $lemma.Shown
                    Pos        = $lemma.Pos
                    Features   = $lemma.Tag
                    Sense      = $i + 1
                    Synset     = $synset
                    Definition = $dictionary.Gloss($synset)
                    Synonyms   = @($dictionary.Written($synset, $Language) | Where-Object { [LambekDictionary]::Normalize($_) -ne $lemma.Lemma } | ForEach-Object { $_ -replace '_', ' ' })
                    Broader    = @($broader | ForEach-Object { $_ -replace '_', ' ' })
                    Rank       = $i
                    Cognate    = [math]::Round($cognate, 1)
                })
        }
    }

    # The senses that look most like the word first, then the most frequent ones; numbered in that order
    $ordered = @($found | Sort-Object @{ Expression = { $_.Cognate -ge 0.6 }; Descending = $true }, Rank, Pos, Lemma | Select-Object -First $First)
    for ($i = 0; $i -lt $ordered.Count; $i++) { $ordered[$i].Sense = $i + 1 }
    $ordered
}
