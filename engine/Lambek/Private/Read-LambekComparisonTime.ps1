function Get-LambekTimeWord {
    param([string] $Language)

    # The words of a language that put one thing done before or after another (Dialogue.General.Time: "avant",
    # "apres", "vor", "nach"), and those of the days counted from today (Dialogue.Times, "day" only: "hier", "gestern"),
    # each as its words; nothing when it has none
    if ($null -eq $script:TimeWords) { $script:TimeWords = @{} }
    if ($script:TimeWords.ContainsKey($Language)) { return $script:TimeWords[$Language] }
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $general = $(if ($dialogue -and $dialogue['General']) { $dialogue['General'] } else { $null })
    # (each run of words written as one string, its words apart by one space)
    $runs = { param($list) @(@($list) | Where-Object { $_ } | ForEach-Object { (@((ConvertTo-LambekNormalizedText -Text ("$_" -replace "['\u2019]", "' ")) -split '\s+' | Where-Object { $_ }) -join ' ') }) }
    $time = $(if ($general -and $general.Contains('Time')) { $general['Time'] } else { $null })
    $days = [System.Collections.Generic.List[object]]::new()
    if ($dialogue -and $dialogue['Times'] -is [System.Collections.IDictionary]) {
        foreach ($phrase in @($dialogue['Times'].Keys)) {
            $unit, $offset = "$($dialogue['Times'][$phrase])" -split ':'
            if ($unit -ne 'day') { continue }
            $days.Add([pscustomobject]@{ Words = (@((ConvertTo-LambekNormalizedText -Text ("$phrase" -replace "['\u2019]", "' ")) -split '\s+' | Where-Object { $_ }) -join ' '); Offset = [int] $offset })
        }
    }
    $words = $null
    if ($time -or $days.Count -gt 0) {
        $words = [pscustomobject]@{
            Before = $(if ($time) { @(& $runs $time['Before']) } else { @() })
            After  = $(if ($time) { @(& $runs $time['After']) } else { @() })
            Days   = @($days | Sort-Object { - @($_.Words -split ' ').Count })
        }
    }
    $script:TimeWords[$Language] = $words
    return $words
}

function Read-LambekComparisonTime {
    param([string] $Sentence, [string] $Language, [switch] $Question)

    # One thing done before or after another ("Rex est arrive avant Max", "ist Rex vor Max angekommen?"), read as one
    # compared with another: of what is done and how ("time:before:arriver"), the one said first the greater. And one thing done
    # on a day counted from today ("Rex est arrive hier", "gestern hat Rex gegessen"): kind "dated", with its day.
    # The one before or after another is one named; nothing is read when the sentence says not
    $words = Get-LambekTimeWord -Language $Language
    $model = Get-LambekFormModel -Language $Language
    if (-not $words -or -not $model) { return $null }
    $text = ($Sentence.Trim() -replace '^\p{P}+', '' -replace '\p{P}+$', '')
    # (asked as the language asks before the sentence, "est-ce que": what follows is asked)
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $lead = $(if ($dialogue -and $dialogue['General']) { "$($dialogue['General']['Inverted'])" } else { '' })
    if ($lead) {
        $parts = @(($lead -replace '-', ' ') -split '\s+' | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) })
        $last = $parts[-1]
        $pattern = '(?i)^' + ((@($parts | Select-Object -SkipLast 1) + @("$($last.Substring(0, $last.Length - 1))(?:$($last.Substring($last.Length - 1))\s+|['\u2019])")) -join '[\s-]+')
        $match = [regex]::Match($text, $pattern)
        if ($match.Success) { $text = $text.Substring($match.Length).Trim(); $Question = $true }
    }
    # The words, a pronoun joined to its verb left out ("est-il" is "est"), and what the language writes with an
    # apostrophe cut after it, as its words of time were learned ("aujourd' hui")
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($word in @(($text -replace ',', ' ') -split '\s+' | Where-Object { $_ })) {
        $cut = [regex]::Match($word, '^(?<verb>\p{L}+)-(?:t-)?(?<pronoun>\p{L}+)$')
        if ($cut.Success) {
            $tags = $null
            if ($model.Tags.TryGetValue($cut.Groups['pronoun'].Value.ToLowerInvariant(), [ref] $tags) -and @($tags | Where-Object { "$_".StartsWith('PRON|') }).Count -gt 0) { $tokens.Add($cut.Groups['verb'].Value); continue }
        }
        $tokens.Add($word)
    }
    $plain = @($tokens | ForEach-Object { ConvertTo-LambekNormalizedText -Text $_ })
    # (where a run of words is, counted in words: "aujourd' hui" is one word written, two learned)
    $at = {
        param([string] $words)
        $run = @($words -split ' ')
        for ($i = 0; $i -le $plain.Count - 1; $i++) {
            $from = @($plain[$i..($plain.Count - 1)] | ForEach-Object { @(($_ -replace "['\u2019]", "' ") -split '\s+' | Where-Object { $_ }) })
            if ($from.Count -lt $run.Count) { continue }
            if ((@($from[0..($run.Count - 1)]) -join ' ') -ne ($run -join ' ')) { continue }
            # (how many words written the run takes)
            $taken = 0; $n = 0
            while ($n -lt $run.Count) { $n += @(($plain[$i + $taken] -replace "['\u2019]", "' ") -split '\s+' | Where-Object { $_ }).Count; $taken++ }
            if ($n -ne $run.Count) { continue }
            return [pscustomobject]@{ At = $i; Length = $taken }
        }
        return $null
    }
    $readings = @($model.Read([string[]] $tokens.ToArray()))
    if ($readings.Count -ne $tokens.Count) { return $null }
    $not = @(Get-LambekNotWord -Language $Language)
    if (@($readings | Where-Object { "|$($_.Feats)|" -match '\|(Polarity|PronType)=Neg\|' -or (ConvertTo-LambekNormalizedText -Text "$($_.Form)") -in $not }).Count -gt 0) { return $null }

    # What is done, and by whom: the words left, read as one named doing something; what is done is the lemma of its
    # last verb ("arrive" in "est arrive", "angekommen" in "ist angekommen"), the same told or asked
    $done = {
        param([int[]] $keep)
        $left = @($keep | ForEach-Object { $tokens[$_] })
        if ($left.Count -lt 2) { return $null }
        $item = Read-LambekCategoryTagged -Sentence ($left -join ' ') -Language $Language -Question:$Question
        # (told with its verb first after the word of time, "gestern hat Rex gegessen": read as it is written, told)
        if (-not $item -and -not $Question) {
            $item = Read-LambekCategoryTagged -Sentence ($left -join ' ') -Language $Language -Question
            if ($item -and $item.Kind -in 'askis', 'askdoes') { $item.Kind = $item.Kind.Substring(3) } else { $item = $null }
        }
        if (-not $item -or -not $item.Individual -or "$($item.Individual.Key)" -notlike 'name:*') { return $null }
        if ($item.Kind -notin 'is', 'does', 'askis', 'askdoes') { return $null }
        $verbs = @($keep | Where-Object { "$($readings[$_].Upos)" -eq 'VERB' -or ("$($readings[$_].Upos)" -eq 'ADJ' -and "|$($readings[$_].Feats)|" -match '\|VerbForm=Part\|') })
        if ($verbs.Count -eq 0) { return $null }
        $last = $verbs[-1]
        $lemma = "$(if ($readings[$last].Lemma) { $readings[$last].Lemma } else { $tokens[$last] })"
        # (a participle read as an adjective in one sentence and as a verb in another, "angekommen": the lemma of the
        # verb, as its treebanks tag it, so that it is the same told or asked)
        if ("$($readings[$last].Upos)" -ne 'VERB') {
            $tags = $null
            if ($model.Tags.TryGetValue($tokens[$last].ToLowerInvariant(), [ref] $tags)) {
                $verb = @($tags | Where-Object { "$_".StartsWith('VERB|') } | Select-Object -First 1)
                if ($verb.Count -gt 0) { $lemma = $model.LemmaFor($tokens[$last], "$($verb[0])") }
            }
        }
        $lemma = ConvertTo-LambekNormalizedText -Text $lemma
        if (-not $lemma) { return $null }
        # (said as told, the one named first: "ist Rex angekommen" is said "Rex ist angekommen")
        $name = @(($item.Written.Subject -split '\s+') | Where-Object { $_ })
        $first = -1
        for ($i = 0; $i -le $keep.Count - $name.Count; $i++) { if ((@($keep[$i..($i + $name.Count - 1)] | ForEach-Object { $tokens[$_] }) -join ' ') -eq ($name -join ' ')) { $first = $i; break } }
        if ($first -lt 0) { return $null }
        [pscustomobject]@{ Item = $item; Of = "time:$lemma"; Asked = $item.Kind.StartsWith('ask'); Name = $first; Length = $name.Count }
    }
    # (the words in the order they are said back: the one named first)
    $told = {
        param([int[]] $order, [int] $nameAt, [int] $nameLength)
        $named = @($order[$nameAt..($nameAt + $nameLength - 1)])
        $rest = @($order | Where-Object { $_ -notin $named })
        $out = @(@($named) + @($rest) | ForEach-Object { $tokens[$_] })
        if ($nameAt -gt 0 -and $out.Count -gt $nameLength) { $out[$nameLength] = $out[$nameLength].Substring(0, 1).ToLowerInvariant() + $out[$nameLength].Substring(1) }
        $out -join ' '
    }

    # One before or after another: "avant", "nach", then a word that joins it to the other ("antes de", "prima di"),
    # then the other, named; what follows it is of what is done ("vor Max angekommen")
    foreach ($way in @([pscustomobject]@{ Runs = $words.Before; Before = $true }, [pscustomobject]@{ Runs = $words.After; Before = $false })) {
        foreach ($run in @($way.Runs | Sort-Object { - @("$_" -split ' ').Count })) {
            $found = & $at $run
            if (-not $found -or $found.At -lt 1) { continue }
            $next = $found.At + $found.Length
            if ($next -lt $tokens.Count - 1 -and "$($readings[$next].Upos)" -in 'ADP', 'SCONJ' -and "$($readings[$next].Upos)" -ne 'PROPN') { $next++ }
            $lemmas = @{}
            $other = $null
            $end = $next
            for ($j = $next; $j -lt $tokens.Count -and -not $other; $j++) {
                $one = ConvertTo-LambekCategoryIndividual -Text (@($tokens[$next..$j]) -join ' ') -Language $Language -Lemmas $lemmas
                if ($one -and "$($one.Key)" -like 'name:*') { $other = $one; $end = $j }
            }
            if (-not $other) { continue }
            $keep = @(@(0..($found.At - 1)) + @(if ($end + 1 -le $tokens.Count - 1) { ($end + 1)..($tokens.Count - 1) }))
            $did = & $done $keep
            if (-not $did -or $did.Item.Individual.Key -eq $other.Key) { continue }
            $order = @(0..($tokens.Count - 1))
            $nameAt = [array]::IndexOf($order, $keep[$did.Name])
            $said = & $told $order $nameAt $did.Length
            # (the other way round: the two named swapped, said the same way)
            $mine = @($keep[$did.Name..($did.Name + $did.Length - 1)])
            $theirs = @($next..$end)
            $swapped = [System.Collections.Generic.List[int]]::new()
            for ($i = 0; $i -lt $tokens.Count; $i++) {
                if ($i -eq $mine[0]) { foreach ($t in $theirs) { $swapped.Add($t) } }
                elseif ($i -eq $theirs[0]) { foreach ($t in $mine) { $swapped.Add($t) } }
                elseif ($i -notin $mine -and $i -notin $theirs) { $swapped.Add($i) }
            }
            $back = & $told $swapped.ToArray() ([array]::IndexOf($swapped.ToArray(), $theirs[0])) $theirs.Count
            # (before and after kept apart: "Smith swam before Jones swam" does not say Jones swam after Smith swam,
            # one may swim more than once; the one said first is the greater, of "time:before:nager")
            return [pscustomobject]@{
                Kind    = $(if ($did.Asked) { 'askcompare' } else { 'compare' })
                Of      = "time:$(if ($way.Before) { 'before' } else { 'after' }):$($did.Of.Substring(5))"
                Greater = $did.Item.Individual
                Smaller = $other
                Said    = $said
                Back    = $back
                Several = $false
            }
        }
    }

    # One done on a day counted from today: the day said, and what is done read from the words left
    foreach ($day in $words.Days) {
        $found = & $at $day.Words
        if (-not $found) { continue }
        $keep = @(for ($i = 0; $i -lt $tokens.Count; $i++) { if ($i -lt $found.At -or $i -ge $found.At + $found.Length) { $i } })
        $did = & $done $keep
        if (-not $did) { continue }
        $order = @(0..($tokens.Count - 1))
        $nameAt = [array]::IndexOf($order, $keep[$did.Name])
        return [pscustomobject]@{
            Kind    = $(if ($did.Asked) { 'askdated' } else { 'dated' })
            Of      = $did.Of
            Who     = $did.Item.Individual
            Day     = (Get-LambekNow).Date.AddDays($day.Offset).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
            Said    = & $told $order $nameAt $did.Length
            Several = $false
        }
    }
    return $null
}
