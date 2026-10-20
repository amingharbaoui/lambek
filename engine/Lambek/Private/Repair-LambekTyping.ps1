function Repair-LambekTyping {
    # What was typed fast, read as it was meant before anything else reads the message:
    #   the shorthand of chats ("slt", "cmt", "thx"), as the language file writes it in full;
    #   a word written in small letters that no dictionary knows, in no language Lambek reads, and that is one typing
    #   slip from exactly one form it knows ("capitalle": capitale).
    # A word with a capital may be a name ("Pingu" is not "ping"), and is never changed; nor are paths, file names,
    # extensions, numbers, words joined by an apostrophe or a hyphen, and every word Lambek or a dictionary knows.
    # When two forms are as close, nothing is changed: Lambek does not choose for the user. What was changed is
    # returned with the text, to be said
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [string] $Language
    )

    $changes = [System.Collections.Generic.List[object]]::new()
    $none = [pscustomobject]@{ Text = $Text; Changes = @() }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $none }
    if (-not $Language) { $Language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) }
    if ($Language -notin (Get-LambekAvailableLanguage)) { return $none }
    $lexicon = Get-LambekLexicon -Language $Language
    $shorthand = $lexicon.Shorthand
    $dictionary = Get-LambekDictionary -Language $Language
    # (a word of another language is no slip: "combien" is not "combine" when the language was not told)
    $others = @(@($Language, 'fr', 'en') | Where-Object { $_ -in (Get-LambekAvailableLanguage) } | Select-Object -Unique)

    # A word on its own: letters only, nothing of a path, a file name, an extension, an elision or a compound around it
    $pattern = "(?<![\p{L}\p{N}_\\/:.'\u2019-])\p{L}+(?![\p{L}\p{N}_\\/:'\u2019-])(?!\.\p{L})"
    $repaired = [regex]::Replace($Text, $pattern, {
            param($match)
            $word = $match.Value
            $lower = $word.ToLowerInvariant()
            $plain = ConvertTo-LambekNormalizedText -Text $lower

            # Shorthand, whatever its length
            if ($shorthand -and $shorthand.Contains($plain)) {
                $with = [string] $shorthand[$plain]
                if ($word -cmatch '^\p{Lu}') { $with = $with.Substring(0, 1).ToUpperInvariant() + $with.Substring(1) }
                $changes.Add([pscustomobject]@{ From = $word; To = $with; Sense = 'shorthand' })
                return $with
            }

            # A slip in a word: long enough to be one, in small letters (a capital may be a name), known to nobody
            if (-not $dictionary -or $word.Length -lt 4 -or $word -cmatch '\p{Lu}') { return $word }
            foreach ($other in $others) {
                $known = Get-LambekLexicon -Language $other
                if ($known.StopWords.Contains($plain) -or $known.Vocabulary.Contains($plain) -or $known.BaseForms.ContainsKey($plain) -or $known.TalkWords.Contains($plain)) { return $word }
                if ($known.Negations -contains $plain -or $known.Exclusions -contains $plain) { return $word }
                $words = Get-LambekDictionary -Language $other
                if ($words -and @($words.Lemmas($lower, $other)).Count -gt 0) { return $word }
            }
            $near = @($dictionary.Near($lower, $Language, 1))
            if ($near.Count -ne 1) { return $word }
            $changes.Add([pscustomobject]@{ From = $word; To = $near[0]; Sense = 'spelling' })
            return $near[0]
        })
    if ($changes.Count -eq 0) { return $none }
    return [pscustomobject]@{ Text = $repaired; Changes = $changes.ToArray() }
}
