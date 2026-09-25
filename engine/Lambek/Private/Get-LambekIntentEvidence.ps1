function Get-LambekIntentEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request
    )

    $language = $Request.Language
    $grammar = Resolve-LambekGrammar -Request $Request
    $index = Get-LambekActionIndex -Language $language

    # Similarity to every example, grouped by action
    $byAction = [ordered]@{}
    foreach ($entry in $index.Entries) {
        $similarity = Measure-LambekTermSimilarity -Terms $Request.Terms -NGrams $Request.CharNGrams `
            -ReferenceTerms $entry.Terms -ReferenceNGrams $entry.NGrams -Model $index.Model

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

    # Grammar score: the verb of the action is typed by its own pack
    foreach ($candidate in $byAction.Values) {
        foreach ($item in $grammar.Assignment) {
            if ($item.Word -notin $candidate.Action.Verbs) { continue }

            $packTypes = @()
            foreach ($key in '*', $language) {
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

    return [pscustomobject]@{
        Request    = $Request
        Grammar    = $grammar
        Candidates = @($byAction.Values)
    }
}
