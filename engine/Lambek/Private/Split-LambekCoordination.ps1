function Split-LambekCoordination {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        # The language the sentence is read in, when the one who asks knows it (the reader of general rules)
        [string] $Language = 'auto'
    )

    # "my sister lives in Lyon and my brother lives in Paris" is two things told, read one after the other.
    # Each side must read as a sentence; when one side lacks its subject ("...and works in Paris") it takes the
    # subject of the other, and when it lacks its verb ("my sister and my mother live in Lyon") it takes the verb
    # of the other, put in the singular. Anything else stays whole, as it was
    $request = ConvertTo-LambekRequest -Text $Text -Language $Language
    $general = $null
    $lexicon = Get-LambekLexicon -Language $request.Language
    if ($lexicon.Dialogue -and $lexicon.Dialogue['General']) { $general = $lexicon.Dialogue['General'] }
    if (-not $general -or -not $general['Conjunctions']) { return , [string[]] @($Text) }
    if (@($request.Entities | Where-Object { $_.Type -ne 'number' }).Count -gt 0) { return , [string[]] @($Text) }
    # "...because she works in Lyon": the second side is the reason of the first. It is marked, so the plan can link them
    $causes = (@($general['Causes']) | Where-Object { $_ } | ForEach-Object { if ($_ -match "'$") { [regex]::Escape($_) } else { [regex]::Escape($_) + '\s+' } }) -join '|'
    if ($causes) {
        $cause = [regex]::Match($Text, "(?i)\s*,?\s+(?:$causes)")
        if ($cause.Success) {
            $left = $Text.Substring(0, $cause.Index).Trim()
            $right = $Text.Substring($cause.Index + $cause.Length).Trim()
            $one = @(Split-LambekCoordination -Text $left -Language $Language)
            $two = @(Split-LambekCoordination -Text $right -Language $Language)
            $reads = {
                param([string] $clause)
                try { $asked = ConvertTo-LambekRequest -Text $clause -Language $request.Language } catch { return $false }
                $reading = Get-LambekGeneralReading -Request $asked
                return [bool] ($reading -and $reading.Kind -in 'statement', 'unresolved')
            }
            if ($left -and $right -and $one.Count -eq 1 -and $two.Count -eq 1 -and (& $reads $left) -and (& $reads $right)) {
                return , [string[]] @($left, "$([char] 1)$right")
            }
            return , [string[]] @($Text)
        }
    }
    $words = (@($general['Conjunctions']) | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $match = [regex]::Match($Text, "(?i)\s*,?\s+(?:$words)\s+")
    if (-not $match.Success) { return , [string[]] @($Text) }
    $left = $Text.Substring(0, $match.Index).Trim()
    $right = $Text.Substring($match.Index + $match.Length).Trim()
    if (-not $left -or -not $right) { return , [string[]] @($Text) }

    $read = {
        param([string] $clause)
        try { $asked = ConvertTo-LambekRequest -Text $clause -Language $request.Language } catch { return $null }
        $reading = Get-LambekGeneralReading -Request $asked
        if ($reading -and $reading.Kind -in 'statement', 'unresolved') { return $reading }
        return $null
    }
    $first = & $read $left
    $second = & $read $right
    if ($first -and $second) { $more = Split-LambekCoordination -Text $right -Language $Language; return , [string[]] (@($left) + $more) }

    # The first side reads and the second does not: it lacks what the first side has
    if ($first -and -not $second -and $first.Kind -eq 'statement') {
        # "I like tea and coffee", "j'ai vecu a Lyon et a Paris": the second side takes the place of what ends the first
        $values = @($first.Roles.Values)
        if ($values.Count -gt 0) {
            $last = "$($values[-1])"
            if ($last -and $left.EndsWith($last, [System.StringComparison]::OrdinalIgnoreCase)) {
                # what ends the first side, with the word of place before it or without ("in Lyon and in Paris")
                $head = $left.Substring(0, $left.Length - $last.Length).TrimEnd()
                $cut = [regex]::Match($head, '^(.*\S)\s+\S+$')
                # (without it first: "a habite a Lyon et a Paris" is not "a habite a a Paris")
                $keys = (@($first.Roles.Keys) | Sort-Object) -join '|'
                foreach ($start in @(if ($cut.Success) { $cut.Groups[1].Value }) + @($head)) {
                    $joined = "$start $right"
                    # ("tea and coffee and milk": what follows may be a list itself)
                    $more = Split-LambekCoordination -Text $joined -Language $Language
                    $same = @($more | Where-Object {
                            $again = & $read $_
                            $again -and $again.Verb -eq $first.Verb -and ((@($again.Roles.Keys) | Sort-Object) -join '|') -eq $keys
                        }).Count -eq $more.Count
                    if ($same) { return , [string[]] (@($left) + $more) }
                }
            }
        }
        # "...and works in Paris": the subject of the first side, said as it was
        $subject = $null
        if ($first.Agent -eq 'speaker') { $subject = @($general['Speakers'])[0] }
        elseif ($first.Name) { $subject = $first.Name }
        if ($subject) {
            $joined = "$subject $right"
            # (je + a vowel is j')
            if ($subject -eq 'je' -and $right -match '^[aeiouyh\u00E0-\u00FF]') { $joined = "j'$right" }
            if (& $read $joined) { $more = Split-LambekCoordination -Text $joined -Language $Language; return , [string[]] (@($left) + $more) }
        }
    }

    # "my sister and my mother live in Lyon": the verb and what follows it, for each one, in the singular
    if (-not $first -and $second -and $second.Kind -eq 'statement' -and $second.Name) {
        $rest = $null
        if ($right.StartsWith($second.Name, [System.StringComparison]::OrdinalIgnoreCase)) { $rest = $right.Substring($second.Name.Length).Trim() }
        if ($rest) {
            $one = Get-LambekSingular -Text $rest -Language $request.Language
            $clauses = @("$left $one", "$($second.Name) $one")
            if ((& $read $clauses[0]) -and (& $read $clauses[1])) { return , [string[]] $clauses }
        }
    }
    # "Rex en Max zijn honden": neither side reads, the verb in the plural ("zijn" is also "his"). When, said in the
    # singular after the name that opens the second side, both sides read ("Rex is honden", "Max is honden"), each name
    # takes the verb and what follows it as they were said ("Rex zijn honden", "Max zijn honden")
    if (-not $first -and -not $second) {
        $parts = @($right -split '\s+')
        for ($take = 1; $take -le [math]::Min(2, $parts.Count - 1); $take++) {
            $subject = $parts[0..($take - 1)] -join ' '
            $rest = $parts[$take..($parts.Count - 1)] -join ' '
            $one = Get-LambekSingular -Text $rest -Language $request.Language -Before $subject
            if ($one -ceq $rest) { continue }
            $readings = @("$left $one", "$subject $one" | ForEach-Object { & $read $_ })
            if (@($readings | Where-Object { $_ -and $_.Kind -eq 'statement' }).Count -eq 2) { return , [string[]] @("$left $rest", "$subject $rest") }
        }
    }
    # "I like tea, coffee and milk": the commas of a list are read as "and"
    if ($Text.Contains(',')) {
        $listed = [regex]::Replace($Text, '\s*,\s*', " $($match.Value.Trim().TrimStart(',').Trim()) ")
        $more = Split-LambekCoordination -Text $listed -Language $Language
        if ($more.Count -gt 1) { return , [string[]] $more }
    }
    return , [string[]] @($Text)
}

function Get-LambekSingular {
    # (what comes before the verb, read with it for the verb to be read in its place: "zijn" after a name is "are")
    param([string] $Text, [string] $Language, [string] $Before)

    # The first word of the predicate, a verb in the plural, said in the singular: "live" -> "lives", "habitent" -> "habite"
    $match = [regex]::Match($Text, '^\p{L}+')
    if (-not $match.Success) { return $Text }
    $verb = $match.Value
    $plain = ConvertTo-LambekNormalizedText -Text $verb
    $singular = $null
    if ($Language -eq 'en') {
        $irregular = @{ are = 'is'; were = 'was'; have = 'has'; do = 'does'; go = 'goes' }
        if ($irregular.ContainsKey($plain)) { $singular = $irregular[$plain] }
        elseif ($plain -match '(s|sh|ch|x|z|o)$') { $singular = "$($verb)es" }
        elseif ($plain -match '[^aeiou]y$') { $singular = $verb.Substring(0, $verb.Length - 1) + 'ies' }
        else { $singular = "$($verb)s" }
    }
    else {
        # The dictionary conjugates: the same verb, the same tense, third person singular
        $dictionary = Get-LambekDictionary -Language $Language
        if ($dictionary) {
            foreach ($lemma in @($dictionary.Lemmas($plain, $Language) | Where-Object { $_.Pos -eq 'v' -or $_.Pos -like 'aux*' })) {
                $tag = "$($lemma.Tag)"
                $mood = @('P', 'I', 'F', 'C', 'J', 'S', 'T' | Where-Object { $tag.Contains($_) } | Select-Object -First 1)
                $mood = $(if ($mood.Count -gt 0) { $mood[0] } else { $null })
                if (-not $mood -or $tag -notmatch '3p') { continue }
                $forms = @($dictionary.Forms($lemma.Lemma, $Language, $lemma.Pos, "$($mood)3s"))
                if ($forms.Count -gt 0) { $singular = $forms[0]; break }
            }
        }
    }
    # (or, read after what comes before it, the forms its treebanks wrote: the same lemma, the same features, but one)
    if (-not $singular -and $Before -and $Language -ne 'en') {
        $model = Get-LambekFormModel -Language $Language
        if ($model) {
            $reading = @(@($model.ReadText("$Before $Text".Trim())) | Where-Object { "$($_.Form)" -ieq $verb } | Select-Object -First 1)
            $reading = $(if ($reading.Count -gt 0) { $reading[0] } else { $null })
            $feats = $(if ($reading) { "$($reading.Feats)" } else { '' })
            if ($reading -and "$($reading.Upos)" -in 'AUX', 'VERB' -and $feats -match '(^|\|)Number=Plur(\||$)') {
                $said = @($model.Inflect("$($reading.Lemma)", "$($reading.Upos)", ($feats -replace 'Number=Plur', 'Number=Sing')))
                if ($said.Count -gt 0 -and $said[0]) { $singular = "$($said[0])" }
            }
        }
    }
    if (-not $singular) { return $Text }
    return $singular + $Text.Substring($verb.Length)
}
