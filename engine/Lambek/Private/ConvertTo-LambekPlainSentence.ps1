function ConvertTo-LambekPlainSentence {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # Two ways of speaking that say a sentence the grammar reads only in its plain order, said back in that order:
    #   "ma soeur en a 2": "en" stands for the thing counted just before ("j'ai 3 chats"), "ma soeur a 2 chats";
    #   "je fais quoi ?", "ma soeur habite ou ?": the word that asks at the end, "qu'est-ce que je fais ?".
    # The sentence is read as the plain one, and said back so: the user sees how it was understood.
    # Anything else is left as it was
    # "Combien Paul a-t-il de pommes ?": the pronoun that repeats the one named before the verb is left out,
    # "Combien Paul a de pommes ?" (only after "combien" and a name: "Combien a-t-il de pommes ?" keeps its subject)
    $Text = [regex]::Replace($Text, '(?<head>\b[Cc]ombien\s+(?:de\s+\p{L}+\s+)?\p{Lu}\p{L}*(?:\s+et\s+\p{Lu}\p{L}*)?\s+\p{L}+)(?:-t)?-(?:il|elle|ils|elles)\b', '${head}')

    # "Paul est-il grand ?", "ma soeur habite-t-elle a Lyon ?": a question said with the verb before a pronoun that
    # repeats the one named, said plain ("est-ce que Paul est grand ?"); only after a name or someone said with whose or
    # which it is, never after a word that asks ("ou habite-t-il ?" is left as it was)
    if ($Text -match '\p{L}-(?:t-)?\p{L}+(?:\s|[?!.]|$)') {
        $language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text)
        $dialogue = (Get-LambekLexicon -Language $language).Dialogue
        $general = $(if ($dialogue) { $dialogue['General'] })
        if ($general -and $general['Inverted'] -and @($general['Pronouns']).Count -gt 0) {
            $pronouns = (@($general['Pronouns']) | Where-Object { $_ } | ForEach-Object { [regex]::Escape("$_") }) -join '|'
            $inverted = [regex]::Match($Text, "^(?<subject>.+?)\s+(?<verb>\p{L}+)-(?:t-)?(?:$pronouns)(?<rest>(?:\s[^?!.]*)?)(?<mark>\s*[?!.]*\s*)$")
            if ($inverted.Success) {
                $subject = $inverted.Groups['subject'].Value.Trim()
                $first = ConvertTo-LambekNormalizedText -Text (@($subject -split '\s+')[0] -replace "['\u2019].*$", '')
                $asking = @(foreach ($key in 'What', 'WhatObject', 'WhatSubject', 'Where', 'Why', 'HowMany', 'Conditions', 'Unread') { @($general[$key]) | Where-Object { $_ } | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" } })
                $named = $subject -cmatch '^\p{Lu}' -and @(@($subject -split '\s+') | Where-Object { (ConvertTo-LambekNormalizedText -Text ($_ -replace "['\u2019].*$", '')) -in $asking }).Count -eq 0
                $said = $first -in (@($general['Owners']) + @($general['Determiners']))
                $dictionary = Get-LambekDictionary -Language $language
                $verb = $inverted.Groups['verb'].Value
                $isVerb = $dictionary -and @($dictionary.Lemmas((ConvertTo-LambekNormalizedText -Text $verb), $language) | Where-Object { $_.Pos -eq 'v' }).Count -gt 0
                if (($named -or $said) -and $isVerb) {
                    return "$($general['Inverted']) $subject $verb$($inverted.Groups['rest'].Value)$($inverted.Groups['mark'].Value)"
                }
            }
        }
    }

    $quick = '(?i)(?:(?<![\p{L}])en\s|[''\u2019]en\s|\s(?:quoi|o\u00f9)\s*[?!.]*\s*$)'
    if ($Text -notmatch $quick) { return $Text }
    $language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text)
    $dialogue = (Get-LambekLexicon -Language $language).Dialogue
    if (-not $dialogue -or -not $dialogue['General']) { return $Text }
    $general = $dialogue['General']
    if (-not $general['Partitive'] -and -not $general['InSitu']) { return $Text }
    $dictionary = Get-LambekDictionary -Language $language
    if (-not $dictionary) { return $Text }
    $isVerb = { param([string] $word) @($dictionary.Lemmas((ConvertTo-LambekNormalizedText -Text $word), $language) | Where-Object { $_.Pos -eq 'v' }).Count -gt 0 }
    $end = [regex]::Match($Text, '\s*[?!.]*\s*$')
    $body = $Text.Substring(0, $end.Index)
    $mark = $Text.Substring($end.Index)

    # "en" before the verb, a number after it, nothing after the number
    foreach ($word in @($general['Partitive'])) {
        if (-not $word) { continue }
        $found = [regex]::Match($body, "(?i)(?:(?<elided>(?<![\p{L}])\p{L}['\u2019])|(?<![\p{L}]))$([regex]::Escape($word))\s+(?<verb>\p{L}+)\s+(?<number>\S+)$")
        if (-not $found.Success -or -not (& $isVerb $found.Groups['verb'].Value)) { continue }
        $number = "$([LambekNumberWords]::Digitize($found.Groups['number'].Value, $language))".Trim()
        $ones = @($general['One']) | Where-Object { $_ }
        if ($number -in $ones) { $number = '1' }
        if ($number -notmatch '^\d+(?:[.,]\d+)?$') { continue }
        $noun = Get-LambekLastCounted -Language $language
        if (-not $noun) { continue }
        # ("j'en ai 3": the "j'" before "en" goes back to its verb, "j'ai 3 chats")
        $before = $body.Substring(0, $found.Index)
        if ($found.Groups['elided'].Success) { $before += $found.Groups['elided'].Value }
        return "$before$($found.Groups['verb'].Value) $($found.Groups['number'].Value) $noun$mark"
    }

    # The word that asks, at the end: "<qui> <verbe> quoi ?"
    $asks = $general['InSitu']
    if ($asks) {
        $last = [regex]::Match($body, '(?<rest>.+?)\s+(?<word>\p{L}+)$')
        if ($last.Success) {
            $word = $last.Groups['word'].Value.ToLowerInvariant()
            $rest = $last.Groups['rest'].Value
            $words = @($rest -split '\s+' | Where-Object { $_ })
            $first = ConvertTo-LambekNormalizedText -Text ($words[0] -replace "['\u2019].*$", '')
            $opens = $first -in (@($general['What']) + @($general['WhatObject']) + @($general['WhatSubject']) + @($general['Where']) + @($general['PolarMark']))
            if ($asks.Contains($word) -and $words.Count -ge 2 -and -not $opens -and (& $isVerb $words[-1])) {
                return "$($asks[$word]) $rest$mark"
            }
        }
    }
    return $Text
}

function Get-LambekLastCounted {
    param([string] $Language)

    # The thing counted in the last thing told with a number, in this conversation and then before it: "chats" in "j'ai 3 chats"
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    if (-not $dialogue -or -not $dialogue['General']) { return $null }
    $general = $dialogue['General']
    $ones = (@($general['One']) | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $here = @((Get-LambekTold).ToArray())
    $before = @((Get-LambekToldJournal).ToArray())
    foreach ($facts in @(, $here) + @(, $before)) {
        for ($i = $facts.Count - 1; $i -ge 0; $i--) {
            $fact = $facts[$i]
            if ("$($fact.Language)" -ne $Language) { continue }
            if ($fact.PSObject.Properties['Values'] -and $fact.Values) { $roles = $fact.Values } else { $roles = $fact.Parameters }
            if (-not $roles) { continue }
            foreach ($name in @($roles.Keys)) {
                $value = "$([LambekNumberWords]::Digitize((Format-LambekValue -Value $roles[$name]), $Language))"
                if ($ones) { $value = [regex]::Replace($value, "(?i)^(?:$ones)\s+", '1 ') }
                $match = [regex]::Match($value, '^\s*\d+(?:[.,]\d+)?\s+(?<noun>\p{L}[\p{L}\s-]*)$')
                if ($match.Success) { return $match.Groups['noun'].Value.Trim() }
            }
        }
    }
    return $null
}
