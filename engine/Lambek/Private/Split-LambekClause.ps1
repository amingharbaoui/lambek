function Split-LambekClause {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # Hide quoted text so a separator inside quotes never splits it
    $quotes = [System.Collections.Generic.List[string]]::new()
    $quotePattern = '"[^"]*"|\u00AB[^\u00BB]*\u00BB|\u201C[^\u201D]*\u201D'
    $masked = [regex]::Replace($Text, $quotePattern, {
            param($match)
            $quotes.Add($match.Value)
            return "`0$($quotes.Count - 1)`0"
        })

    # Sequence words in the seven languages, and ";" ("despues de" and "depois de" are "after", not "then";
    # Dutch "dan" alone is also "than", so only "en dan")
    $separator = '\s*(?:;|,?\s*\b(?:and then|then|after that|et ensuite|ensuite|puis|y luego|luego|y despu[e\u00E9]s(?!\s+de\b)|despu[e\u00E9]s(?!\s+de\b)|und dann|dann|danach|e poi|poi|quindi|en dan|daarna|vervolgens|e depois(?!\s+de\b)|depois(?!\s+de\b)|em seguida)\b)\s*'
    $clauses = [regex]::Split($masked, $separator, 'IgnoreCase')

    # "and" or "et" before an action word starts a new step: "list the files in C:\A and delete the .tmp files";
    # before a pronoun it goes on with the same files: "move them and put them in D:\B"
    $verbs = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($pack in $script:Packs.Values) {
        foreach ($language in $pack.Words.Keys) {
            # (a word of place that opens or ends a sentence, "in C:\A, ...", is no action: "...and in Paris")
            $actionWords = @($pack.Words[$language].Keys | Where-Object { @(@($pack.Words[$language][$_]) | Where-Object { $_ -match '(^|\s)s(\s|$)' -and $_ -notmatch 's\^r s|^s s\^l d\^l$' }).Count -gt 0 })
            foreach ($word in $actionWords) { [void] $verbs.Add($word) }
            if ($pack.BaseForms.ContainsKey($language)) {
                foreach ($form in $pack.BaseForms[$language].Keys) {
                    if ($pack.BaseForms[$language][$form] -in $actionWords) { [void] $verbs.Add($form) }
                }
            }
        }
    }
    $clauses = @(foreach ($clause in $clauses) {
            $start = 0
            foreach ($match in [regex]::Matches($clause, '\s*,?\s*\b(?:and|et|y|und|e|ed|en)\s+(\p{L}+)\b(?!\s+(?:it|them)\b|[\s-]+(?:le|la|les|l)(?:\s*$|\s+(?:dans|sur|vers|ailleurs)\b))', 'IgnoreCase')) {
                if (-not $verbs.Contains((ConvertTo-LambekNormalizedText -Text $match.Groups[1].Value))) { continue }
                $clause.Substring($start, $match.Index - $start)
                $start = $match.Groups[1].Index
            }
            $clause.Substring($start)
        })

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($clause in $clauses) {
        # Put the quoted text back
        $restored = [regex]::Replace($clause, "`0(\d+)`0", {
                param($match)
                return $quotes[[int] $match.Groups[1].Value]
            })

        $clean = $restored.Trim(' ', ',', '.')
        if ($clean.Length -gt 0) {
            # Two things told in one sentence ("...and my brother lives in Paris") are two clauses as well
            $parts = Split-LambekCoordination -Text $clean
            foreach ($part in $parts) { $result.Add($part) }
        }
    }

    return $result.ToArray()
}
