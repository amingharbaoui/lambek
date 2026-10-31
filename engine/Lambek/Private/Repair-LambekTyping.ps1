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

    # Where the text quotes something (a name to give, a phrase to find): each letter there
    $quoted = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($span in [regex]::Matches($Text, '"[^"]*"|\u00AB[^\u00BB]*\u00BB|\u201C[^\u201D]*\u201D')) {
        for ($i = $span.Index; $i -lt $span.Index + $span.Length; $i++) { [void] $quoted.Add($i) }
    }

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

            # A slip in a word: long enough to be one, known to nobody. A word with a capital may be a name: it is only
            # read again below, and never changed into a word that is no name, except the first word of a sentence
            if (-not $dictionary -or $word.Length -lt 4) { return $word }
            $capital = $word -cmatch '\p{Lu}'
            # (nothing in capitals only, "JPEG", and nothing quoted: what is quoted is said as it is)
            if ($capital -and ($word -cnotmatch '\p{Ll}' -or $quoted.Contains($match.Index))) { return $word }
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
            if ($capital) { return (Repair-LambekCapital -Word $word -Index $match.Index -Text $Text -Language $Language -Lexicon $lexicon -Dictionary $dictionary -Changes $changes -Shift $shift) }
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

function Repair-LambekCapital {
    # A word with a capital that no dictionary knows ("Frahce", "Bressil", "Clmbien"), read again:
    #   a name Lambek knows (Data/Knowledge), alone or in a longer name of the sentence, is never changed ("Pau" is
    #   not "Paul", "Madame Bovary" stays);
    #   the first word of a sentence may be a small word of the language: one slip from exactly one of its question
    #   words, the words its questions start with, or its small words ("Clmbien": Combien), it is that word;
    #   in a question about the world (as the router of acts reads it), one slip from exactly one name of one word
    #   Lambek knows, or from one far better known than any other (ten times the pages telling of it), it is that name,
    #   as it is written in the language ("Frahce": France). Elsewhere a name may be new ("Tweety est un oiseau" is not
    #   "Twenty"): it stays as it was typed. The known names come from Wikidata, never from what users typed
    param([string] $Word, [int] $Index, [string] $Text, [string] $Language, [object] $Lexicon, [object] $Dictionary,
        [System.Collections.Generic.List[object]] $Changes, [ref] $Shift)

    $facts = Get-LambekFactBase
    $plain = $(if ($facts) { [LambekFacts]::Plain($Word) } else { '' })
    if ($facts -and @($facts.Find($plain) | Where-Object { $_.Start -eq 0 -and $_.Length -eq 1 }).Count -gt 0) { return $Word }
    # (nor a word of a longer name the sentence holds: "Bovary" in "Madame Bovary" is no slip of "Brovary")
    if ($facts -and @($facts.Find([LambekFacts]::Plain($Text)) | Where-Object { $_.Length -gt 1 -and ($_.Name -split ' ') -contains $plain }).Count -gt 0) { return $Word }

    $with = $null
    $first = $Index -eq 0 -or $Text.Substring(0, $Index) -match '(^|[.!?]\s+)[^\p{L}\p{N}]*$'
    if ($first) {
        $lower = $Word.ToLowerInvariant()
        $starts = @(if ($Lexicon.Dialogue -and $Lexicon.Dialogue['QuestionStarts']) { $Lexicon.Dialogue['QuestionStarts'] })
        $small = @(@($Lexicon.Interrogatives) + @($Lexicon.StopWords) + $starts | Where-Object { $_ -match '^\p{L}+$' -and [LambekDictionary]::Slip($_, $lower) } | Select-Object -Unique)
        if ($small.Count -eq 1) { $with = $small[0].Substring(0, 1).ToUpperInvariant() + $small[0].Substring(1) }
    }
    if (-not $with -and $facts) {
        $route = Get-LambekRoute -Text $Text -Language $Language
        if (-not $route -or $route.Act -ne 'World') { $facts = $null }
    }
    if (-not $with -and $facts) {
        $near = @($facts.Near($plain))
        $best = $(if ($near.Count -eq 1) { $near[0] } elseif ($near.Count -gt 1 -and $near[0].Things[0].Links -ge 10 * [math]::Max(1, $near[1].Things[0].Links)) { $near[0] })
        if ($best) {
            $label = $best.Things[0].Label($Language)
            $with = $(if ($label -and [LambekFacts]::Plain($label) -eq $best.Name) { $label } else { $best.Name.Substring(0, 1).ToUpperInvariant() + $best.Name.Substring(1) })
        }
    }
    if (-not $with) { return $Word }
    $Changes.Add([pscustomobject]@{ From = $Word; To = $with; Sense = 'spelling' })
    $Shift.Value += $with.Length - $Word.Length
    return $with
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
