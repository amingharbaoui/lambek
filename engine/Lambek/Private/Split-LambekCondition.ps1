function Split-LambekCondition {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # "s'il pleut, je prends le bus", "je prends le bus s'il pleut", "if it rains then I take the bus": a thing told
    # that holds only when another one does. Read as two sentences, the condition first, marked so the plan keeps it
    # as the condition of the other one and never as something told. Both sides must read as sentences told,
    # with the same grammar as everything else; otherwise nothing is split and the sentence stays as it was
    if (-not $script:ConditionWords) {
        # The words of condition of every language, to see at once a sentence that has none
        $script:ConditionWords = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($language in Get-LambekAvailableLanguage) {
            $dialogue = (Get-LambekLexicon -Language $language).Dialogue
            if (-not $dialogue -or -not $dialogue['General'] -or -not $dialogue['General']['Conditions']) { continue }
            foreach ($word in @($dialogue['General']['Conditions'])) { [void] $script:ConditionWords.Add((ConvertTo-LambekNormalizedText -Text "$word").TrimEnd("'")) }
        }
    }
    $words = @([regex]::Matches((ConvertTo-LambekNormalizedText -Text $Text), '[\p{L}]+') | ForEach-Object { $_.Value })
    if (@($words | Where-Object { $script:ConditionWords.Contains($_) }).Count -eq 0) { return $null }

    $request = ConvertTo-LambekRequest -Text $Text
    $language = $request.Language
    $general = (Get-LambekLexicon -Language $language).Dialogue['General']
    if (-not $general -or -not $general['Conditions']) { return $null }
    # Never about files or code: "si le fichier existe, supprime-le" is an order, and an order is never split here
    if (@($request.Entities | Where-Object { $_.Type -ne 'number' }).Count -gt 0) { return $null }

    $reads = {
        param([string] $clause)
        if (-not $clause.Trim()) { return $false }
        try { $asked = ConvertTo-LambekRequest -Text $clause -Language $language } catch { return $false }
        $reading = Get-LambekGeneralReading -Request $asked
        return [bool] ($reading -and $reading.Kind -eq 'statement')
    }
    # "alors", "then" may open what follows the condition
    $then = (@($general['Then']) | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $after = { param([string] $clause) $clause = $clause.Trim(' ', ','); if ($then) { $clause = [regex]::Replace($clause, "(?i)^(?:$then)\s+", '') }; $clause.Trim() }
    # A word of condition, as a word ("si", "if") or elided ("s'il")
    $marks = (@($general['Conditions']) | Where-Object { $_ } | Sort-Object { -$_.Length } | ForEach-Object {
            if ($_ -match "'$") { [regex]::Escape($_.TrimEnd("'")) + "['’]" } else { [regex]::Escape($_) + '\s+' }
        }) -join '|'
    $found = [regex]::Match($Text, "(?i)(?:^|(?<=[\s,]))(?:$marks)")
    if (-not $found.Success) { return $null }
    $before = $Text.Substring(0, $found.Index).Trim(' ', ',')
    $rest = $Text.Substring($found.Index + $found.Length).Trim().TrimEnd('.', '!')

    if ($before) {
        # The condition last: "je prends le bus s'il pleut"
        $condition = $rest.Trim(' ', ',')
        if ((& $reads $condition) -and (& $reads $before)) { return , [string[]] @("$([char] 2)$condition", $before) }
        return $null
    }
    # The condition first: up to the comma, or as long as both sides still read
    $comma = $rest.IndexOf(',')
    if ($comma -gt 0) {
        $condition = $rest.Substring(0, $comma).Trim()
        $consequence = & $after $rest.Substring($comma + 1)
        if ((& $reads $condition) -and (& $reads $consequence)) { return , [string[]] @("$([char] 2)$condition", $consequence) }
        return $null
    }
    $parts = @($rest -split '\s+' | Where-Object { $_ })
    for ($k = $parts.Count - 1; $k -ge 1; $k--) {
        $condition = ($parts[0..($k - 1)] -join ' ')
        $consequence = & $after ($parts[$k..($parts.Count - 1)] -join ' ')
        if ((& $reads $condition) -and (& $reads $consequence)) { return , [string[]] @("$([char] 2)$condition", $consequence) }
    }
    return $null
}
