function Resolve-LambekToldQuestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # Two questions about what was told that the grammar of a sentence does not read as they stand:
    # "pourquoi ?" alone, about the answer just given, and "combien de chats avons-nous ?", a number to work out
    if ($null -eq $script:ToldQuestionWords) {
        $script:ToldQuestionWords = [pscustomobject]@{ Why = @{}; HowMany = [System.Collections.Generic.List[string]]::new() }
        foreach ($language in Get-LambekAvailableLanguage) {
            $dialogue = (Get-LambekLexicon -Language $language).Dialogue
            if (-not $dialogue -or -not $dialogue['General']) { continue }
            foreach ($phrase in @($dialogue['General']['WhyAlone'])) { if ($phrase) { $script:ToldQuestionWords.Why[(ConvertTo-LambekNormalizedText -Text "$phrase")] = $language } }
            foreach ($phrase in @($dialogue['General']['HowMany'])) { if ($phrase) { $script:ToldQuestionWords.HowMany.Add((ConvertTo-LambekNormalizedText -Text "$phrase")) } }
        }
    }
    $plain = ((ConvertTo-LambekNormalizedText -Text $Text) -replace '[^\p{L}\p{N}\s]', ' ' -replace '\s+', ' ').Trim()
    # ("pourquoi ?" with no answer of this kind just before is about something else: the plan in progress, said elsewhere)
    if ($script:ToldQuestionWords.Why.ContainsKey($plain) -and (Get-LambekLastProof)) {
        return [pscustomobject]@{ Language = $script:ToldQuestionWords.Why[$plain]; Asked = [pscustomobject]@{ Kind = 'why'; All = $false; Actions = @() } }
    }
    if (@($script:ToldQuestionWords.HowMany | Where-Object { " $plain ".Contains(" $_ ") }).Count -eq 0) { return $null }
    $request = ConvertTo-LambekRequest -Text $Text
    $asked = Get-LambekCountQuestion -Request $request
    if (-not $asked) { return $null }
    return [pscustomobject]@{ Language = $request.Language; Asked = $asked }
}

function Find-LambekPhrase {
    param([string[]] $Tokens, [object[]] $Phrases, [int] $From = 0)

    # Where one of the phrases starts among the words, and how many words it has; the longest first
    foreach ($phrase in @($Phrases | Where-Object { $_ } | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" } | Sort-Object { -($_ -split ' ').Count })) {
        $words = @($phrase -split '\s+' | Where-Object { $_ })
        for ($i = $From; $i -le $Tokens.Count - $words.Count; $i++) {
            if (($Tokens[$i..($i + $words.Count - 1)] -join ' ') -eq ($words -join ' ')) { return [pscustomobject]@{ At = $i; Length = $words.Count } }
        }
    }
    return $null
}

function Get-LambekCountQuestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request
    )

    # "combien de chats avons-nous en tout", "how many more cats do I have than my sister": the thing counted, then the
    # rest of the question read by the grammar as "what do we have", "qu'est-ce que j'ai". Who is asked about comes
    # from that reading; "en tout", "de plus que" and their like say how the numbers are put together
    $general = (Get-LambekLexicon -Language $Request.Language).Dialogue['General']
    if (-not $general -or -not $general['HowMany']) { return $null }
    # The words as they were typed: a word corrected towards a word of a pack ("frere" read as "creer") is not the word said
    $Request = Read-LambekRequest -Text (Repair-LambekPhrase -Text "$($Request.Original)") -Original "$($Request.Original)" -Language $Request.Language
    $tokens = [string[]] @($Request.Tokens)
    $how = Find-LambekPhrase -Tokens $tokens -Phrases @($general['HowMany'])
    if (-not $how) { return $null }
    $removed = [System.Collections.Generic.HashSet[int]]::new()
    for ($i = $how.At; $i -lt $how.At + $how.Length; $i++) { [void] $removed.Add($i) }
    $direction = $null
    $at = $how.At + $how.Length
    # ("how many more cats")
    if ($at -lt $tokens.Count -and $tokens[$at] -in @($general['More'])) { $direction = 'more'; [void] $removed.Add($at); $at++ }
    elseif ($at -lt $tokens.Count -and $tokens[$at] -in @($general['Fewer'])) { $direction = 'fewer'; [void] $removed.Add($at); $at++ }
    # The thing counted: after "de" in French ("combien ... de chats"), at once in English ("how many cats")
    $noun = -1
    if (@($general['CountOf']).Count -gt 0) {
        for ($j = $at; $j -lt $tokens.Count - 1; $j++) {
            if ($tokens[$j] -in @($general['CountOf'])) { $noun = $j + 1; [void] $removed.Add($j); break }
        }
    }
    else { $noun = $at }
    if ($noun -lt 0 -or $noun -ge $tokens.Count -or $tokens[$noun] -notmatch '^\p{L}+$') { return $null }
    [void] $removed.Add($noun)

    # "de plus que ma soeur", "than my sister": who the number is compared with, to the end of the question
    $compare = $null
    $kinds = @(
        @{ Direction = 'more'; Phrases = @($general['More']) + @() }
        @{ Direction = 'fewer'; Phrases = @($general['Fewer']) }
        @{ Direction = $direction; Phrases = @($general['Than']) }
    )
    foreach ($kind in $kinds) {
        if (-not $kind.Direction -or @($kind.Phrases).Count -eq 0) { continue }
        $found = Find-LambekPhrase -Tokens $tokens -Phrases $kind.Phrases -From ($noun + 1)
        if (-not $found -or $removed.Contains($found.At)) { continue }
        $direction = $kind.Direction
        $end = $tokens.Count
        $total = Find-LambekPhrase -Tokens $tokens -Phrases @($general['Total']) -From ($found.At + $found.Length)
        if ($total) { $end = $total.At }
        $who = @(for ($k = $found.At + $found.Length; $k -lt $end; $k++) { $tokens[$k] })
        if ($who.Count -eq 0) { return $null }
        for ($k = $found.At; $k -lt $end; $k++) { [void] $removed.Add($k) }
        $compare = Get-LambekWritten -Request $Request -Words $who
        break
    }
    $sum = $false
    $total = Find-LambekPhrase -Tokens $tokens -Phrases @($general['Total'])
    if ($total) { $sum = $true; for ($k = $total.At; $k -lt $total.At + $total.Length; $k++) { [void] $removed.Add($k) } }
    if ($direction -and -not $compare) { return $null }

    # The rest is a question of what: "qu'est-ce que j'ai", "que avons-nous", "what do we have"
    $rest = @(for ($k = 0; $k -lt $tokens.Count; $k++) { if (-not $removed.Contains($k)) { $tokens[$k] } })
    if ($rest.Count -eq 0) { return $null }
    $written = Get-LambekWritten -Request $Request -Words $rest
    # (each word that asks what, before the rest, and "est-ce que" after it where the language has it)
    $tries = @(@($general['WhatObject']) + @($general['What']) | Where-Object { $_ -and $_.Length -gt 2 } | ForEach-Object { "$_ $written" })
    if ($Request.Language -eq 'fr') {
        $tries = @("qu'est-ce que $written", "que $written")
        # "combien de chiens a ma voisine": the verb before its subject, read as "qu'est-ce que ma voisine a"
        $dictionary = Get-LambekDictionary -Language $Request.Language
        if ($rest.Count -gt 1 -and $dictionary -and @($dictionary.Lemmas($rest[0], $Request.Language) | Where-Object { $_.Pos -eq 'v' }).Count -gt 0) {
            $tries += "qu'est-ce que $(Get-LambekWritten -Request $Request -Words @($rest | Select-Object -Skip 1)) $(Get-LambekWritten -Request $Request -Words @($rest[0]))"
        }
    }
    $reading = $null
    foreach ($try in $tries) {
        try { $asked = ConvertTo-LambekRequest -Text $try -Language $Request.Language } catch { continue }
        $reading = Get-LambekGeneralReading -Request $asked
        if ($reading -and $reading.Kind -eq 'question' -and $reading.Asked -eq 'object' -and $reading.Roles.Count -eq 0) { break }
        $reading = $null
    }
    if (-not $reading) { return $null }
    # "nous", "we": everyone told about, added up
    $holder = $reading.Agent
    if ($holder -eq 'speaker' -and @($rest | Where-Object { $_ -in @($general['Together']) }).Count -gt 0) { $holder = 'all'; $sum = $true }
    [pscustomobject]@{
        Kind      = 'count'
        All       = $false
        Actions   = @("verb:$($reading.Verb)")
        Verb      = $reading.Verb
        Noun      = Get-LambekWritten -Request $Request -Words @($tokens[$noun])
        Holder    = $holder
        Name      = $reading.Name
        Total     = $sum
        Direction = $direction
        Compare   = $compare
    }
}

function Get-LambekCountAnswer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Asked,

        # Everything held, the oldest first: things told and things deduced
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Facts,

        [Parameter(Mandatory)]
        [string] $Language,

        [string] $Register = 'vous'
    )

    # The numbers told with the thing counted ("j'ai 3 chats", "ma soeur a deux chats"), the last one told for each one,
    # put together as the question says: added up, compared, or said as it is. Every number used is said with the
    # sentence it was told in, and the calculation is written out: the answer can be checked by hand
    $lexicon = Get-LambekLexicon -Language $Language
    $say = $lexicon.Dialogue.Say
    $general = $lexicon.Dialogue['General']
    $dictionary = Get-LambekDictionary -Language $Language
    $lemmas = {
        param([string] $word)
        $plain = ConvertTo-LambekNormalizedText -Text $word
        $set = [System.Collections.Generic.HashSet[string]]::new()
        [void] $set.Add($plain)
        if ($dictionary) { foreach ($lemma in @($dictionary.Lemmas($plain, $Language) | Where-Object { $_.Pos -eq 'n' })) { [void] $set.Add((ConvertTo-LambekNormalizedText -Text "$($lemma.Lemma)")) } }
        return , $set
    }
    $wanted = & $lemmas $Asked.Noun
    $owner = { param($text) (((ConvertTo-LambekNormalizedText -Text "$text") -split '[^\p{L}\p{N}]+' | Where-Object { $_ }) | ForEach-Object { if ($_ -in @($general['Owners'])) { '@' } else { $_ } }) -join ' ' }
    $key = {
        param($agent, $name)
        if ($agent -eq 'speaker') { return 'speaker' }
        if (@($general['Me']) -contains (ConvertTo-LambekNormalizedText -Text "$name") -or @($general['Speakers']) -contains (ConvertTo-LambekNormalizedText -Text "$name")) { return 'speaker' }
        return "other:$(& $owner $name)"
    }
    $verb = "verb:$(ConvertTo-LambekNormalizedText -Text "$($Asked.Verb)")"
    $numbers = [ordered]@{}
    foreach ($fact in $Facts) {
        if ($fact.PSObject.Properties['Condition'] -and $fact.Condition) { continue }
        if ($fact.PSObject.Properties['Negated'] -and $fact.Negated) { continue }
        if ((ConvertTo-LambekNormalizedText -Text "$($fact.Action)") -ne $verb) { continue }
        if ($fact.PSObject.Properties['Values']) { $roles = $fact.Values } else { $roles = $fact.Parameters }
        foreach ($name in @($roles.Keys)) {
            $value = [LambekNumberWords]::Digitize((Format-LambekValue -Value $roles[$name]), $Language)
            # ("une voiture", "an apple": one)
            $ones = (@($general['One']) | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) }) -join '|'
            if ($ones) { $value = [regex]::Replace("$value", "(?i)^(?:$ones)\s+", '1 ') }
            $match = [regex]::Match("$value", '(?<![\p{L}\p{N}])(\d+(?:[.,]\d+)?)\s+(\S.*)$')
            if (-not $match.Success) { continue }
            $words = @($match.Groups[2].Value -split '[^\p{L}]+' | Where-Object { $_ })
            if (@($words | Where-Object { (& $lemmas $_).Overlaps($wanted) }).Count -eq 0) { continue }
            $number = [decimal]::Parse($match.Groups[1].Value.Replace(',', '.'), [cultureinfo]::InvariantCulture)
            # The last told for each one is the one that holds
            $numbers[(& $key $fact.Agent $fact.Name)] = [pscustomobject]@{ Fact = $fact; Number = $number }
            break
        }
    }
    $pick = {
        param($holder, $name)
        if ($holder -eq 'all') { return @($numbers.Values) }
        $wantedKey = & $key $holder $name
        if ($numbers.Contains($wantedKey)) { return @($numbers[$wantedKey]) }
        return @()
    }
    $mine = @(& $pick $Asked.Holder $Asked.Name)
    if ($mine.Count -eq 0) { return $null }
    $culture = [cultureinfo]::InvariantCulture
    try { $culture = [cultureinfo]::GetCultureInfo($Language) } catch { $culture = [cultureinfo]::InvariantCulture }
    $show = { param([decimal] $n) $n.ToString('0.##', $culture) }
    $form = {
        param([decimal] $n)
        # One cat, two cats: the thing counted as the question says it, or as the dictionary has it for one
        $singular = @($general['Singular']) -contains [int] [math]::Abs($n) -and [math]::Abs($n) -eq [math]::Floor([math]::Abs($n))
        if (-not $singular) { return $Asked.Noun }
        $one = @($dictionary.Lemmas((ConvertTo-LambekNormalizedText -Text $Asked.Noun), $Language) | Where-Object { $_.Pos -eq 'n' } | Select-Object -First 1)
        if ($one.Count -gt 0) { return "$($one[0].Lemma)" }
        return $Asked.Noun
    }
    $used = [System.Collections.Generic.List[object]]::new()
    $calculation = ''
    if ($Asked.Direction) {
        $other = @(& $pick 'other' $Asked.Compare)
        if ($other.Count -eq 0) { return $null }
        $a = ($mine | Measure-Object -Property Number -Sum).Sum
        $b = $other[0].Number
        $difference = $a - $b
        # (the larger first: "3 de moins" is 9 - 6 = 3, never 6 - 9 = -3)
        if ($difference -ge 0) { $calculation = "$(& $show $a) - $(& $show $b) = $(& $show $difference)" }
        else { $calculation = "$(& $show $b) - $(& $show $a) = $(& $show (-$difference))" }
        if ($difference -eq 0) { $first = $say['CountSame'] -f (& $show $a), (& $form $a) }
        else {
            $more = $difference -gt 0
            $size = [math]::Abs($difference)
            $first = $say[$(if ($more) { 'CountMore' } else { 'CountFewer' })] -f (& $show $size), (& $form $size)
        }
        foreach ($item in @($mine) + @($other)) { $used.Add($item.Fact) }
    }
    elseif ($mine.Count -eq 1 -and -not $Asked.Total) {
        $first = $say['Count'] -f (& $show $mine[0].Number), (& $form $mine[0].Number)
        $used.Add($mine[0].Fact)
    }
    else {
        $total = ($mine | Measure-Object -Property Number -Sum).Sum
        $first = $say['CountTotal'] -f (& $show $total), (& $form $total)
        if ($mine.Count -gt 1) { $calculation = "$(@($mine | ForEach-Object { & $show $_.Number }) -join ' + ') = $(& $show $total)" }
        foreach ($item in $mine) { $used.Add($item.Fact) }
    }
    $first = $first.Substring(0, 1).ToUpperInvariant() + $first.Substring(1)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($first)
    foreach ($fact in $used) { $lines.Add("- $(Format-LambekFact -Fact $fact -Language $Language -Register $Register)") }
    if ($calculation) { $lines.Add($calculation) }
    # What the answer rests on, for "pourquoi ?": what was told, down to the rules a number was deduced with
    $leaves = [System.Collections.Generic.List[object]]::new()
    foreach ($fact in $used) { foreach ($leaf in Get-LambekProofLeaf -Fact $fact) { if (-not $leaves.Contains($leaf)) { $leaves.Add($leaf) } } }
    Set-LambekLastProof -Facts $leaves.ToArray() -Calculation $calculation
    return ($lines -join "`n")
}

function Get-LambekWhyAnswer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language,

        [string] $Register = 'vous'
    )

    # "pourquoi ?" after an answer: what it rested on, each thing as it was told, and the calculation when there was one
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    $proof = Get-LambekLastProof
    if (-not $proof) { return $say['WhyNothing'] }
    $lines = [System.Collections.Generic.List[string]]::new()
    # Read, not told: where it was read, and the day the data was read
    if ($proof.PSObject.Properties['Read'] -and @($proof.Read).Count -gt 0 -and $say['WhyRead']) {
        foreach ($source in @($proof.Read | Group-Object { "$($_.Source)|$($_.Day)" })) {
            $read = $source.Group[0]
            $facts = (Get-LambekLexicon -Language $Language).Facts
            $day = $null
            if ($facts) { $day = Format-LambekFactDate -Value "$($read.Day)" -Precision '11' -Facts $facts }
            if (-not $day) { $day = "$($read.Day)" }
            $lines.Add(($say['WhyRead'] -f $read.Source, $day))
            foreach ($line in $source.Group) { $lines.Add("- $($line.Line) ($($line.Id))") }
        }
        return ($lines -join "`n")
    }
    $lines.Add($say['Why'])
    foreach ($fact in @($proof.Facts)) { $lines.Add("- $(Format-LambekFact -Fact $fact -Language $Language -Register $Register -Bare)") }
    # (what was told of a problem, as it was said back)
    if ($proof.PSObject.Properties['Said']) { foreach ($line in @($proof.Said)) { if ($line) { $lines.Add("- $line") } } }
    if ($proof.Calculation) { $lines.Add($say['WhyCalculated'] -f $proof.Calculation) }
    return ($lines -join "`n")
}
