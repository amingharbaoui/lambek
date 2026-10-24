function Repair-LambekRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Original,

        [string] $Language = 'auto'
    )

    # The reading as typed
    $current = Test-LambekReading -Text $Text -Original $Original -Language $Language
    $corrections = [System.Collections.Generic.List[object]]::new()

    # A turn of phrase the user taught by saying it another way is read as that other way, with the values of now.
    # The grammar is the judge here too: it is kept only when the sentence explains more, and no value is lost
    $taught = Get-LambekFormReading -Request $current.Request
    if ($taught -and $taught -cne $current.Text) {
        $reading = Test-LambekReading -Text $taught -Original $Original -Language $Language
        if ($reading.Grammar.IsSentence -and $reading.Defects -lt $current.Defects -and (Test-LambekSameEntity -Before $current.Request -After $reading.Request)) {
            $corrections.Add([pscustomobject]@{ From = $Original; To = $taught; Distance = 0.0; Sense = 'form' })
            $current = $reading
        }
    }

    # Each word the grammar cannot place is tried against its closest known words, left to right.
    # The grammar is the judge: a correction is kept only when the sentence explains more with it,
    # the cheapest typing slip first. Paths, names and numbers never change.
    $done = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($token in @(Get-LambekUnplacedToken -Reading $current)) {
        if (-not $done.Add($token)) { continue }

        $best = $current
        $bestCost = 0.0
        $bestWord = $null
        foreach ($candidate in Get-LambekSpellingCandidate -Token $token -Language $current.Request.Language) {
            $changed = Get-LambekCorrectedText -Text $current.Text -Word $token -With $candidate.Word
            if ($changed -ceq $current.Text) { continue }

            $reading = Test-LambekReading -Text $changed -Original $Original -Language $Language
            if (-not (Test-LambekSameEntity -Before $current.Request -After $reading.Request)) { continue }

            # Candidates come cheapest first, so fewer defects is the only way to win
            if ($reading.Defects -lt $best.Defects) {
                $best = $reading
                $bestCost = $candidate.Cost
                $bestWord = $candidate.Word
            }
        }

        if ($best -ne $current) {
            $corrections.Add([pscustomobject]@{ From = $token; To = $bestWord; Distance = $bestCost })
            $current = $best
        }
    }

    # A word still unknown may be a word of the dictionary: a synonym of a word Lambek knows, a meaning just above
    # or just below one ("relocate" is a way to "move"), or a phrase ("get rid of"). The grammar judges again
    $proposals = [System.Collections.Generic.List[object]]::new()
    $current = Repair-LambekFromDictionary -Current $current -Original $Original -Language $Language -Corrections $corrections -Proposals $proposals

    # A word still unknown may be read from what it looks like, when the sentence is whole with that reading:
    # a word of manner ("rapidement", "quickly") changes no file, a word an extension shortens ("zippes": .zip) names one
    foreach ($token in @(Get-LambekUnplacedToken -Reading $current)) {
        foreach ($sense in @(Get-LambekWordSense -Token $token -Language $current.Request.Language)) {
            $changed = Get-LambekCorrectedText -Text $current.Text -Word $token -With $sense.With
            if ($changed -ceq $current.Text) { continue }
            $reading = Test-LambekReading -Text $changed -Original $Original -Language $Language
            if (-not $reading.Grammar.IsSentence -or $reading.Defects -ge $current.Defects) { continue }
            if (-not (Test-LambekSameEntity -Before $current.Request -After $reading.Request)) { continue }
            $corrections.Add([pscustomobject]@{ From = $token; To = $sense.With.Trim(); Distance = 0.0; Sense = $sense.Sense })
            $current = $reading
            break
        }
    }

    $request = $current.Request
    $request.Corrections = $corrections.ToArray()
    $proposal = $null
    if ($proposals.Count -gt 0 -and @(Get-LambekUnplacedToken -Reading $current | Where-Object { $_ -in $proposals[0].Word.Split(' ') }).Count -gt 0) { $proposal = $proposals[0] }
    $request | Add-Member -NotePropertyName Proposal -NotePropertyValue $proposal -Force
    $request | Add-Member -NotePropertyName Grammar -NotePropertyValue $current.Grammar -Force
    return $request
}

function Test-LambekReading {
    param([string] $Text, [string] $Original, [string] $Language)

    # A reading and its defects: the types left once the words cancel (none for a sentence), and the words it cannot place.
    # A word it cannot place counts two, the smallest type that could let it vanish (x^r x)
    $request = Read-LambekRequest -Text (Repair-LambekPhrase -Text $Text) -Original $Original -Language $Language
    $grammar = Resolve-LambekGrammar -Request $request
    return [pscustomobject]@{
        Text    = $Text
        Request = $request
        Grammar = $grammar
        Defects = $grammar.Distance + 2 * $grammar.Unknown.Count
    }
}

function Get-LambekUnplacedToken {
    param([pscustomobject] $Reading)

    # Tokens the grammar leaves unknown and no dictionary of the engine knows
    $lexicon = Get-LambekLexicon -Language $Reading.Request.Language
    $tokens = @($Reading.Request.Tokens)
    $words = @($Reading.Request.Words)
    # (a word written with a capital and small letters after the first one, that names a thing of the world Lambek read, is that name:
    # "la France" is not "la grande"; a folder typed with a capital may still be corrected, "Dowloads")
    $capitals = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $said = @([regex]::Matches("$($Reading.Request.Original)", '\p{L}[\p{L}\p{M}]*'))
    for ($k = 1; $k -lt $said.Count; $k++) {
        if ($said[$k].Value.Length -gt 1 -and [char]::IsUpper($said[$k].Value[0]) -and [char]::IsLower($said[$k].Value[1])) { [void] $capitals.Add((ConvertTo-LambekNormalizedText -Text $said[$k].Value)) }
    }
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        if ($words[$i] -notin $Reading.Grammar.Unknown) { continue }
        if ($capitals.Contains($token)) {
            $world = Get-LambekFactBase
            if ($world -and @($world.Find($token) | Where-Object { $_.Name -eq $token }).Count -gt 0) { continue }
        }
        if ($lexicon.Vocabulary.Contains($token) -or $lexicon.BaseForms.ContainsKey($token)) { continue }
        # Never "correct" a negation or an exception: "sans" is not "dans", "pas" is not "par"
        if ($token -in $lexicon.Negations -or $token -in $lexicon.Exclusions) { continue }
        if ($token.EndsWith('s') -and $lexicon.Vocabulary.Contains($token.Substring(0, $token.Length - 1))) { continue }
        $token
    }
}

function Repair-LambekFromDictionary {
    param(
        [pscustomobject] $Current,
        [string] $Original,
        [string] $Language,
        [System.Collections.Generic.List[object]] $Corrections,
        [System.Collections.Generic.List[object]] $Proposals
    )

    $unplaced = @(Get-LambekUnplacedToken -Reading $Current | Where-Object { $_ -match '^\p{L}{3,}$' })
    if ($unplaced.Count -eq 0) { return $Current }
    $language = $Current.Request.Language
    $dictionary = Get-LambekDictionary -Language $language
    if (-not $dictionary) { return $Current }
    $lexicon = Get-LambekLexicon -Language $language
    $domain = Get-LambekDomainSense -Language $language
    # A sentence that names no folder, file or extension is read as it was written: a synonym is then only proposed
    # ("Guns N' Roses a remporte son premier prix" is no order to list files, whatever "remporter" may mean)
    $named = @($Current.Request.Entities | Where-Object { $_.Type -in 'path', 'filename', 'extension' }).Count -gt 0

    # The words to look up: phrases of three or two words the dictionary knows together, then single words
    $tokens = @($Current.Request.Tokens)
    $spans = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -notin $unplaced) { continue }
        foreach ($size in 3, 2) {
            if ($i + $size -gt $tokens.Count) { continue }
            $words = [string[]] @($tokens[$i..($i + $size - 1)])
            if (@($words | Where-Object { $_ -notmatch '^\p{L}+$' }).Count -gt 0) { continue }
            if ($dictionary.Lemmas(($words -join '_'), $language).Count -gt 0) { $spans.Add($words) }
        }
        $spans.Add([string[]] @($tokens[$i]))
    }

    foreach ($words in $spans) {
        if (@($words | Where-Object { $_ -in @(Get-LambekUnplacedToken -Reading $Current) }).Count -eq 0) { continue }
        # Only the senses the words of an action agree on; the closest known words first (fewest links, most frequent senses)
        $related = @($dictionary.Related(($words -join '_'), $language, 'v', $lexicon.Vocabulary, $domain, 1) | Select-Object -First 4)
        foreach ($candidate in $related) {
            # The known word as the dictionary of forms writes it, with its accents
            $shown = @($dictionary.Lemmas($candidate.Word, $language) | Where-Object { $_.Pos -eq 'v' -and $_.Lemma -eq $candidate.Word } | ForEach-Object Shown | Select-Object -First 1)
            if ($shown.Count -eq 0) { $shown = @($candidate.Word) }
            $changed = Get-LambekCorrectedPhrase -Text $Current.Text -Words $words -With $shown[0]
            if ($changed -ceq $Current.Text) { continue }
            $reading = Test-LambekReading -Text $changed -Original $Original -Language $Language
            if (-not $reading.Grammar.IsSentence -or $reading.Defects -ge $Current.Defects) { continue }
            if (-not (Test-LambekSameEntity -Before $Current.Request -After $reading.Request)) { continue }

            $said = Get-LambekSurface -Text $Current.Text -Words $words
            $found = [pscustomobject]@{
                From     = $said
                To       = $shown[0]
                Distance = 0.0
                Sense    = 'dictionary'
                Relation = $candidate.Relation
                Hops     = $candidate.Hops
                Synset   = $candidate.Synset
                Lemma    = $candidate.From
                Word     = $words -join ' '
                Text     = $changed
            }

            # A synonym, or a form of a known word, is that word. A meaning next to it is only proposed:
            # the user says yes before anything is read that way, when the senses are frequent enough to ask
            # and only when the word can only lead to reading: a synonym of a change is asked first ("withdraw" is not always "remove")
            if (($candidate.Relation -eq 'form' -or ($named -and $candidate.Relation -eq 'synonym')) -and (Get-LambekVerbRisk -Word $candidate.Word -Lexicon $lexicon) -eq 'low') {
                $Corrections.Add($found)
                $Current = $reading
            }
            elseif (($candidate.Relation -in 'form', 'synonym' -or $candidate.Rank -le 3) -and $Proposals.Count -eq 0) {
                $Proposals.Add($found)
            }
            break
        }
    }
    return $Current
}

function Get-LambekVerbRisk {
    param([string] $Word, [object] $Lexicon)

    # The highest risk of the actions a verb names (itself or its base form); a verb of no action counts as high
    $names = @($Word)
    if ($Lexicon.BaseForms.ContainsKey($Word)) { $names += $Lexicon.BaseForms[$Word] }
    $order = @{ low = 0; medium = 1; high = 2 }
    $risk = $null
    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            if (@($action.Verbs | Where-Object { $_ -in $names }).Count -eq 0) { continue }
            if ($null -eq $risk -or $order[$action.Risk] -gt $order[$risk]) { $risk = $action.Risk }
        }
    }
    if ($null -eq $risk) { return 'high' }
    return $risk
}

function Get-LambekSurface {
    param([string] $Text, [string[]] $Words)

    # The words as the user typed them, with their accents and capitals
    $marker = [char] 0x2063
    $changed = Get-LambekCorrectedPhrase -Text $Text -Words $Words -With $marker
    $at = $changed.IndexOf($marker)
    if ($at -lt 0) { return $Words -join ' ' }
    $tail = $changed.Length - $at - 1
    return $Text.Substring($at, $Text.Length - $at - $tail)
}

function Get-LambekCorrectedPhrase {
    param([string] $Text, [string[]] $Words, [string] $With)

    if ($Words.Count -eq 1) { return Get-LambekCorrectedText -Text $Text -Word $Words[0] -With $With }

    # The words one after the other, with only spaces between them, never inside quotes
    $quotes = @([regex]::Matches($Text, '"[^"]*"|\u00AB[^\u00BB]*\u00BB|\u201C[^\u201D]*\u201D'))
    $found = @([regex]::Matches($Text, '(?<![\p{L}\p{M}\p{N}_\\/:.%$~@-])[\p{L}\p{M}]+(?![\p{L}\p{M}\p{N}_\\/:@-]|\.\w)'))
    for ($i = 0; $i -le $found.Count - $Words.Count; $i++) {
        $same = $true
        for ($k = 0; $k -lt $Words.Count; $k++) {
            $match = $found[$i + $k]
            if ((ConvertTo-LambekNormalizedText -Text $match.Value) -ne $Words[$k]) { $same = $false; break }
            if ($k -gt 0) {
                $before = $found[$i + $k - 1]
                if ($Text.Substring($before.Index + $before.Length, $match.Index - $before.Index - $before.Length) -notmatch '^\s+$') { $same = $false; break }
            }
        }
        if (-not $same) { continue }
        $start = $found[$i].Index
        $inside = @($quotes | Where-Object { $start -ge $_.Index -and $start -lt $_.Index + $_.Length }).Count -gt 0
        if ($inside) { continue }
        $last = $found[$i + $Words.Count - 1]
        return $Text.Substring(0, $start) + $With + $Text.Substring($last.Index + $last.Length)
    }
    return $Text
}

function Get-LambekCorrectedText {
    param([string] $Text, [string] $Word, [string] $With)

    # Only a word standing alone: never inside quotes, a path, a file name or an address
    $from = $Word
    $to = $With
    $quotes = @([regex]::Matches($Text, '"[^"]*"|\u00AB[^\u00BB]*\u00BB|\u201C[^\u201D]*\u201D'))
    return [regex]::Replace($Text, '(?<![\p{L}\p{M}\p{N}_\\/:.%$~@-])[\p{L}\p{M}]+(?![\p{L}\p{M}\p{N}_\\/:@-]|\.\w)', {
            param($match)
            foreach ($quote in $quotes) {
                if ($match.Index -ge $quote.Index -and $match.Index -lt $quote.Index + $quote.Length) { return $match.Value }
            }
            if ((ConvertTo-LambekNormalizedText -Text $match.Value) -ne $from) { return $match.Value }
            return $to
        })
}

function Test-LambekSameEntity {
    param([pscustomobject] $Before, [pscustomobject] $After)

    # Every value found before is still there, unchanged (a correction may only add a place)
    $left = [System.Collections.Generic.List[string]]::new()
    foreach ($entity in $After.Entities) { $left.Add("$($entity.Type)|$(Format-LambekValue -Value $entity.Value)") }
    foreach ($entity in $Before.Entities) {
        if (-not $left.Remove("$($entity.Type)|$(Format-LambekValue -Value $entity.Value)")) { return $false }
    }
    return $true
}

function Get-LambekWordSense {
    param([string] $Token, [string] $Language)

    $lexicon = Get-LambekLexicon -Language $Language

    # A word of manner: the suffix of the language on a long word that takes no plural ("rapidement", "quickly")
    foreach ($suffix in $lexicon.MannerSuffixes) {
        if ($Token.Length -ge $suffix.Length + 4 -and $Token.EndsWith($suffix)) {
            [pscustomobject]@{ Sense = 'manner'; With = ' ' }
        }
    }

    # An extension of the packs that shortens the word: its letters in order, the first one first, found early,
    # with only vowels and at most one consonant left out ("temporaires": t-m-p is .tmp, "backup": b-a-k is .bak).
    # Only one extension may fit best
    $found = foreach ($extension in Get-LambekPackExtension) {
        $letters = $extension.Substring(1)
        if ($letters.Length -lt 3 -or $letters.Length -ge $Token.Length -or $letters[0] -ne $Token[0]) { continue }
        $at = 0
        $last = -1
        $skipped = 0
        foreach ($letter in $letters.ToCharArray()) {
            $next = $Token.IndexOf($letter, $at)
            if ($next -lt 0) { $last = -1; break }
            $skipped += @($Token.Substring($at, $next - $at).ToCharArray() | Where-Object { $_ -notmatch '[aeiouy]' }).Count
            $last = $next
            $at = $next + 1
        }
        if ($last -lt 0 -or $skipped -gt 1) { continue }
        $spread = ($last + 1) / $Token.Length
        if ($spread -le 0.6) { [pscustomobject]@{ Extension = $extension; Spread = $spread + $skipped } }
    }
    $ranked = @($found | Sort-Object Spread, Extension)
    if ($ranked.Count -eq 1 -or ($ranked.Count -gt 1 -and $ranked[0].Spread -lt $ranked[1].Spread)) {
        [pscustomobject]@{ Sense = 'abbreviation'; With = $ranked[0].Extension }
    }
}

function Get-LambekPackExtension {
    # The extensions the packs name in their kinds: the common ones, never a rare one of the machine
    $list = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($pack in $script:Packs.Values) {
        foreach ($kind in $pack.Kinds.Values) { foreach ($extension in @($kind)) { [void] $list.Add($extension.ToLowerInvariant()) } }
    }
    return [string[]] @($list)
}
