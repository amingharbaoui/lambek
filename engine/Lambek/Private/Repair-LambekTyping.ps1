function Repair-LambekTyping {
    # What was typed fast, read as it was meant before anything else reads the message:
    #   the shorthand of chats ("slt", "cmt", "thx"), as the language file writes it in full;
    #   a word written in small letters that no dictionary knows, in no language Lambek reads, and that is one typing
    #   slip from exactly one form it knows ("capitalle": capitale);
    #   such a word one slip from several forms, read in its sentence: the form of the likeliest reading of the whole
    #   sentence (Viterbi over the model of how the language sounds, the words Lambek is spoken with first), when that
    #   reading is far likelier than any with another form there ("suprime les .tmp dahs C:\Temp": dans).
    # A word with a capital may be a name ("Pingu" is not "ping"), and is never changed; nor are paths, file names,
    # extensions, numbers, words joined by an apostrophe or a hyphen, and every word Lambek or a dictionary knows.
    # When the forms stay as likely, nothing is changed: Lambek does not choose for the user. What was changed is
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
    $doubtful = [System.Collections.Generic.List[object]]::new()
    $shift = [ref] 0
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
                $shift.Value += $with.Length - $word.Length
                return $with
            }

            # A slip in a word: long enough to be one, in small letters (a capital may be a name), known to nobody
            if (-not $dictionary -or $word.Length -lt 4 -or $word -cmatch '\p{Lu}') { return $word }
            foreach ($other in $others) {
                $known = Get-LambekLexicon -Language $other
                if ($known.StopWords.Contains($plain) -or $known.Vocabulary.Contains($plain) -or $known.BaseForms.ContainsKey($plain) -or $known.TalkWords.Contains($plain)) { return $word }
                if ($known.Negations -contains $plain -or $known.Exclusions -contains $plain) { return $word }
                # (nor is a frequent word of the language, which a dictionary of meanings may not have: "when")
                $heardOften = Get-LambekFluency -Language $other
                if ($heardOften -and $heardOften.Knows($lower)) { return $word }
                $words = Get-LambekDictionary -Language $other
                if ($words -and @($words.Lemmas($lower, $other)).Count -gt 0) { return $word }
            }
            $near = @($dictionary.Near($lower, $Language, 1))
            if ($near.Count -eq 1) {
                $changes.Add([pscustomobject]@{ From = $word; To = $near[0]; Sense = 'spelling' })
                $shift.Value += $near[0].Length - $word.Length
                return $near[0]
            }
            # Several forms (or none in the dictionary, but a small word of the language): read in the sentence after
            # (a word of any language Lambek has a dictionary of may be meant as it is: "suprime" is Spanish)
            foreach ($other in @(Get-LambekAvailableLanguage)) {
                $words = Get-LambekDictionary -Language $other
                if ($words -and @($words.Lemmas($lower, $other)).Count -gt 0) { return $word }
            }
            $forms = @(Get-LambekSlipForm -Word $lower -Language $Language -Lexicon $lexicon -Dictionary $dictionary)
            if ($forms.Count -ge 2 -or ($forms.Count -eq 1 -and $near.Count -eq 0)) {
                $doubtful.Add([pscustomobject]@{ Start = $match.Index + $shift.Value; Word = $word; Forms = $forms })
            }
            return $word
        })

    # The doubtful words read in their sentence: the form of the likeliest reading, when it is far likelier
    if ($doubtful.Count -gt 0) {
        $model = Get-LambekFluency -Language $Language
        if ($model) {
            # (the word as it was typed is one of the readings: a word no dictionary has may still be meant, "parce qu'")
            $words = @($doubtful | ForEach-Object { , [string[]] @(@($_.Word.ToLowerInvariant()) + @($_.Forms | ForEach-Object Form)) })
            $priors = @($doubtful | ForEach-Object { , [double[]] @(@(0.0) + @($_.Forms | ForEach-Object Prior)) })
            # (a path, a file name or an extension is no sentence the model heard: each is read as a name, of the same
            # length so the words keep their place)
            $heard = [regex]::Replace($repaired, '(?<!\S)\S*(?:[\\/:]|\.\p{L})\S*', { param($m) 'X' + [string]::new('x', $m.Value.Length - 1) })
            $read = $model.Decode($heard, [int[]] @($doubtful | ForEach-Object Start), [string[][]] $words, [double[][]] $priors, $dictionary)
            for ($w = $doubtful.Count - 1; $w -ge 0; $w--) {
                if ($read[$w][0] -eq 0 -or $read[$w][1] -lt $script:SlipMargin) { continue }
                $with = $words[$w][[int] $read[$w][0]]
                $at = $doubtful[$w]
                $repaired = $repaired.Substring(0, $at.Start) + $with + $repaired.Substring($at.Start + $at.Word.Length)
                $changes.Insert(0, [pscustomobject]@{ From = $at.Word; To = $with; Sense = 'spelling' })
            }
        }
    }
    if ($changes.Count -eq 0) { return $none }
    return [pscustomobject]@{ Text = $repaired; Changes = $changes.ToArray() }
}

function Get-LambekSlipForm {
    # The forms a word typed with one slip may have been meant as, each with how likely it is to be said to Lambek
    # (log10): the words Lambek is spoken with (its small words, the words of its packs, of talk) and the frequent
    # words of the language first, then the other forms of the dictionary, a hundred times less likely
    param([string] $Word, [string] $Language, [object] $Lexicon, [object] $Dictionary)

    $forms = [ordered]@{}
    $model = Get-LambekFluency -Language $Language
    $frequent = @()
    if ($model) { $frequent = @($model.Symbols | Where-Object { $_ -match '^\p{L}+$' }) }
    foreach ($known in @($Lexicon.StopWords) + @($Lexicon.Vocabulary) + @($Lexicon.TalkWords) + $frequent) {
        if ($known -match '^\p{L}+$' -and -not $forms.Contains($known) -and [LambekDictionary]::Slip($known, $Word)) { $forms[$known] = 0.0 }
    }
    $near = @($Dictionary.Near($Word, $Language, 8))
    if ($near.Count -gt 8) { $near = @() }
    foreach ($form in $near) {
        $plain = ConvertTo-LambekNormalizedText -Text $form
        if (-not $forms.Contains($form) -and -not $forms.Contains($plain)) { $forms[$form] = -2.0 }
    }
    foreach ($form in $forms.Keys) { [pscustomobject]@{ Form = $form; Prior = $forms[$form] } }
}
