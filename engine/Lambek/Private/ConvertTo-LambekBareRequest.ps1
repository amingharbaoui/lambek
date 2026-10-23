function ConvertTo-LambekBareRequest {
    # The words said around a request that are not the request: a hesitation or a greeting before it ("euh",
    # "bonjour,", "um", "hi,"), a way of asking ("est-ce que tu peux", "could you"), thanks or "please" after it ("stp",
    # "merci", "thanks"). Left out before the request is read, so that "euh, efface les fichiers .tmp" is read as
    # "efface les fichiers .tmp". Taken from every language (a request may mix them), at the start and at the end only;
    # nothing is left out when the rest would be less than two words ("salut", "merci" alone stay what they are), nor a
    # way of asking before "me", "nous" or "tell" ("peux-tu me dire" asks a question about the world)
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    if (-not $script:CourtesyPatterns) {
        $before = [System.Collections.Generic.List[string]]::new()
        $after = [System.Collections.Generic.List[string]]::new()
        $asking = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($language in Get-LambekAvailableLanguage) {
            $courtesy = (Get-LambekLexicon -Language $language).Courtesy
            if (-not $courtesy) { continue }
            foreach ($phrase in @($courtesy['Before'])) { $before.Add("$phrase") }
            foreach ($phrase in @($courtesy['After'])) { $after.Add("$phrase") }
            foreach ($phrase in @($courtesy['Asking'])) { [void] $asking.Add("$phrase") }
        }
        # (each phrase as written, its apostrophe straight or curly; the longest first)
        $alternatives = {
            param([System.Collections.Generic.IEnumerable[string]] $Phrases, [bool] $Ask)
            $parts = foreach ($phrase in @($Phrases | Sort-Object -Unique | Sort-Object { - $_.Length })) {
                $regex = [regex]::Escape($phrase).Replace("'", "['\u2019]").Replace('\ ', '\s+').Replace('-', '[-\s]')
                if ($Ask -and $asking.Contains($phrase)) { $regex += '(?![\s,]+(?:me|m[''\u2019]|nous|tell|let)\b)' }
                $regex
            }
            return ($parts -join '|')
        }
        $script:CourtesyPatterns = @(
            [regex]::new("^\s*(?:$(& $alternatives $before $true))(?=[\s,!.]|$)[\s,!.]*", 'IgnoreCase')
            [regex]::new("[\s,]+(?:$(& $alternatives $after $false))\s*(?<mark>[?!.]*)\s*$", 'IgnoreCase')
        )
    }
    $kept = $Text
    # (one after the other: "euh, bonjour, est-ce que tu peux ...")
    for ($pass = 0; $pass -lt 4; $pass++) {
        $next = $script:CourtesyPatterns[0].Replace($kept, '', 1)
        $next = $script:CourtesyPatterns[1].Replace($next, '${mark}', 1)
        if ($next -ceq $kept) { break }
        $kept = $next
    }
    if (@($kept.Trim() -split '\s+' | Where-Object { $_ -match '\p{L}|\p{N}' }).Count -lt 2) { return $Text }
    return $kept.Trim()
}
