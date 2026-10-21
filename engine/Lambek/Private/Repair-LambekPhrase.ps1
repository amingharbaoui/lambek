function Repair-LambekPhrase {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $key = "phrase`n$Text"
    $cached = $null
    if ($script:ReadCache.TryGetValue($key, [ref] $cached)) { return $cached }

    # A greeting before a request is only politeness: "salut, supprime les .tmp" is "supprime les .tmp"
    $result = $Text
    if ($null -eq $script:GreetingPattern) {
        $greetings = foreach ($language in Get-LambekAvailableLanguage) {
            $talk = (Get-LambekLexicon -Language $language).Talk
            if ($talk.Contains('Greeting')) { foreach ($phrase in $talk['Greeting'].Phrases) { $phrase -join ' ' } }
        }
        $script:GreetingPattern = ''
        if ($greetings) { $script:GreetingPattern = '(?i)^\s*(?:' + ((@($greetings) | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\s*[,!.]\s*(?=\S)' }
    }
    if ($script:GreetingPattern) { $result = [regex]::Replace($result, $script:GreetingPattern, '') }

    # Idioms of the packs, said the plain way: "mets les images dans X" is "deplace les images vers X"
    # A path or a quoted name is never rewritten: it is hidden while the idioms are read, then put back as typed
    $kept = [System.Collections.Generic.List[string]]::new()
    $open = [string] [char] 0xE000
    $close = [string] [char] 0xE001
    $result = [regex]::Replace($result, '"[^"]*"|\u00AB[^\u00BB]*\u00BB|\u201C[^\u201D]*\u201D|(?i)(?<![\w])[a-z]:[\\/][^\s"]*|\\\\[^\s"]+|(?<![\w/:.~])(?:~|\.{1,2})?/[^\s"]+|https?://\S+', {
            param($match)
            $kept.Add($match.Value)
            return "$open$($kept.Count - 1)$close"
        })
    $language = $null
    foreach ($pack in $script:Packs.Values) {
        foreach ($rewrite in @($pack.Rewrites)) {
            # The idioms of a language file are only read in a sentence of that language
            if ($rewrite -is [System.Collections.IDictionary] -and $rewrite.Contains('Language')) {
                if ($null -eq $language) { $language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) }
                if ($rewrite['Language'] -ne $language) { continue }
            }
            $result = [regex]::Replace($result, $rewrite.Pattern, $rewrite.Replacement)
        }
    }
    $result = [regex]::Replace($result, "$open(\d+)$close", { param($match) $kept[[int] $match.Groups[1].Value] })
    $script:ReadCache[$key] = $result
    return $result
}
