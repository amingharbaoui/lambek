function Get-LambekIntentEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request
    )

    $language = $Request.Language
    # The reading already checked when the request was repaired
    $grammar = $null
    if ($Request.PSObject.Properties['Grammar']) { $grammar = $Request.Grammar }
    if (-not $grammar) { $grammar = Resolve-LambekGrammar -Request $Request }
    $index = Get-LambekActionIndex -Language $language

    # Similarity to every example, grouped by action, on the predicate only (one call to Native/Lambek.cs per example)
    # A word of another language is compared in the language of the sentence, through the glosses of the packs
    $said = @($Request.Terms)
    if ($Request.PSObject.Properties['Borrowed'] -and $Request.Borrowed -and $Request.Borrowed.Count -gt 0) {
        $said = @($said | ForEach-Object { if ($Request.Borrowed.Contains($_)) { ConvertTo-LambekMatrixWord -Word $_ -From $Request.Borrowed[$_] -To $language } else { $_ } })
    }
    $terms = Get-LambekCoreTerm -Terms $said -Known $index.Known
    $nGrams = [string[]] @(Get-LambekCharNGram -Terms $terms)
    $byAction = [ordered]@{}
    foreach ($entry in $index.Entries) {
        $scores = [LambekMeasure]::Similarity($terms, $nGrams, [string[]] @($entry.Terms), [string[]] @($entry.NGrams), $index.Model.Idf, $index.Model.UnknownIdf)
        $similarity = [pscustomobject]@{ EditSimilarity = $scores[0]; WordJaccard = $scores[1]; NGramJaccard = $scores[2]; Cosine = $scores[3] }

        $id = $entry.Action.Id
        if (-not $byAction.Contains($id)) {
            $byAction[$id] = [pscustomobject]@{
                Action       = $entry.Action
                Pack         = $entry.Pack
                GrammarScore = 0.0
                Examples     = [System.Collections.Generic.List[object]]::new()
            }
        }
        $byAction[$id].Examples.Add($similarity)
    }

    # Grammar score: the verb of the action is typed by its own pack; in a sentence, only the head verb counts in full
    $head = $null
    if ($grammar.PSObject.Properties['Head']) { $head = $grammar.Head }
    foreach ($candidate in $byAction.Values) {
        foreach ($item in $grammar.Assignment) {
            if ($item.Word -notin $candidate.Action.Verbs) { continue }
            if ($head -and $item.Position -ne $head.Position) {
                if ($candidate.GrammarScore -lt 0.5) { $candidate.GrammarScore = 0.5 }
                continue
            }

            $packTypes = @()
            # A verb of another language in the sentence is typed in its own language
            $keys = @('*', $language)
            if ($Request.PSObject.Properties['Borrowed'] -and $Request.Borrowed -and $Request.Borrowed.Contains($item.Word)) { $keys += $Request.Borrowed[$item.Word] }
            foreach ($key in $keys) {
                $words = $candidate.Pack.Words
                if ($words.ContainsKey($key) -and $words[$key].ContainsKey($item.Word)) {
                    $packTypes += $words[$key][$item.Word]
                }
            }

            # When the sentence is incomplete, every pack that knows the verb gets the same score
            if ($item.Type -in $packTypes -or (-not $grammar.IsSentence -and $packTypes.Count -gt 0)) {
                $candidate.GrammarScore = 1.0
            }
            elseif ($candidate.GrammarScore -lt 0.5) {
                $candidate.GrammarScore = 0.5
            }
        }
    }

    # The second structural satellite: DisCoCat says which actions the reduction itself allows.
    # Without a whole sentence it says nothing (one half for each)
    $meaning = @(Get-LambekMeaning -Grammar $grammar -Language $language)
    foreach ($candidate in $byAction.Values) {
        $structure = 0.5
        if ($grammar.IsSentence) { $structure = [double] ($candidate.Action.Id -in $meaning) }
        $candidate | Add-Member -NotePropertyName StructureScore -NotePropertyValue $structure -Force
    }

    return [pscustomobject]@{
        Request    = $Request
        Grammar    = $grammar
        Meaning    = $meaning
        Candidates = @($byAction.Values)
        Guess      = Get-LambekTypeGuess -Request $Request -Grammar $grammar
    }
}
