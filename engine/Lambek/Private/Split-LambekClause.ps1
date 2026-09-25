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

    # Sequence words: then, after that, puis, ensuite, and ";"
    $separator = '\s*(?:;|,?\s*\b(?:and then|then|after that|et ensuite|ensuite|puis)\b)\s*'
    $clauses = [regex]::Split($masked, $separator, 'IgnoreCase')

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($clause in $clauses) {
        # Put the quoted text back
        $restored = [regex]::Replace($clause, "`0(\d+)`0", {
                param($match)
                return $quotes[[int] $match.Groups[1].Value]
            })

        $clean = $restored.Trim(' ', ',', '.')
        if ($clean.Length -gt 0) {
            $result.Add($clean)
        }
    }

    return $result.ToArray()
}
