function Resolve-LambekCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # How many of a kind are so, exactly: "au moins trois chats sont noirs" -> "au moins deux chats sont-ils noirs ?"
    # yes; "au plus deux chats sont noirs" -> "au moins trois chats sont-ils noirs ?" no. At least so many of a kind
    # being so are at least as many of any wider kind, being anything wider ("au moins trois chats noirs dorment" ->
    # "au moins trois chats dorment"); at most so many of a kind being so are at most as many of any narrower kind,
    # being anything narrower. What is wider is what the rules told say ("tous les siamois sont des chats") or a part
    # of what is said ("chats noirs" is narrower than "chats"). Read by the tags and the words learned to say how many
    # (Read-LambekCategoryTagged -Counting); a message of things told is taken only when one says at most so many
    # (the rest is read as "certains" by the reasoning on kinds); a question, only alone
    if ($Text -notmatch '\p{L}') { return $null }
    $detected = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) -Text $Text -Forms -Letters
    $languages = @(@($detected) + @(Get-LambekAvailableLanguage | Where-Object { $_ -ne $detected } | Sort-Object))
    foreach ($language in $languages) {
        $dialogue = (Get-LambekLexicon -Language $language).Dialogue
        if (-not $dialogue -or -not $dialogue['General'] -or -not $dialogue['General'].Contains('Counting')) { continue }
        $sentences = @(Split-LambekCategorySentence -Text $Text -Language $language)
        if ($sentences.Count -eq 0) { continue }
        $items = @(foreach ($sentence in $sentences) {
                $item = Read-LambekCategoryTagged -Sentence $sentence.Text -Language $language -Question:$sentence.Question -Counting
                if (-not $item -or -not $item.PSObject.Properties['Count']) { break }
                [pscustomobject]@{ Sentence = $sentence; Item = $item }
            })
        if ($items.Count -ne $sentences.Count) { continue }
        $asks = @($items | Where-Object { $_.Item.Kind -eq 'askcount' })
        if ($asks.Count -eq 1 -and $items.Count -eq 1) { return Resolve-LambekCountQuestion -Ask $asks[0] -Language $language }
        if ($asks.Count -eq 0 -and @($items | Where-Object { $_.Item.Kind -eq 'count' }).Count -gt 0) { return Resolve-LambekCountTold -Items $items -Language $language }
        return $null
    }
    return $null
}

function ConvertTo-LambekCountForm {
    param([pscustomobject] $Item, [string] $Way = '')

    # How many, in the shape the checker reads: count(least|3|chat|noir), count(most|2|...), count(exactly|2|...);
    # asked and answered no: notleast (fewer than so many), notmost (more than so many), notexactly
    $subject = (@($Item.Subject.Atoms) | Sort-Object) -join '+'
    $predicate = (@($Item.Predicate.Atoms) | Sort-Object) -join '+'
    $least = $Item.Count.Least
    $most = $Item.Count.Most
    if (-not $Way) { $Way = $(if ($null -ne $least -and $null -ne $most -and $least -eq $most) { 'exactly' } elseif ($null -ne $least) { 'least' } else { 'most' }) }
    $value = $(if ($Way -match 'most') { $most } else { $least })
    return "count($Way|$value|$subject|$predicate)"
}

function ConvertTo-LambekCountFact {
    param([pscustomobject] $Sentence, [pscustomobject] $Item, [string] $Language)

    # A sentence of the message saying how many, kept as a thing told and said back as it was said
    $form = ConvertTo-LambekCountForm -Item $Item
    return [pscustomobject]@{
        Action     = 'verb:count'
        Parameters = [ordered]@{}
        What       = $Sentence.Original
        Agent      = 'other'
        Name       = ''
        Wish       = $false
        Time       = $null
        Day        = $null
        Told       = $null
        Text       = $Sentence.Original
        Said       = $null
        Language   = $Language
        Hash       = $null
        Negated    = $false
        Core       = "$form|"
        Form       = $form
        Joined     = $Sentence.Original
    }
}

function Resolve-LambekCountTold {
    param([object[]] $Items, [string] $Language)

    # Told: said back; what says at most so many is kept here, the rest as the reasoning on kinds keeps it, read again
    # with how many when asked
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    $facts = @(foreach ($entry in $Items) { ConvertTo-LambekCountFact -Sentence $entry.Sentence -Item $entry.Item -Language $Language })
    $shape = 'Noted'
    if ($script:Incognito) { $shape += 'Here' }
    Set-LambekLastProof
    return [pscustomobject]@{ Language = $Language; Reply = ($say[$shape] -f (@($facts | ForEach-Object { Format-LambekFact -Fact $_ -Language $Language -Register 'vous' }) -join ' ')); Facts = $facts }
}

function Get-LambekCountKnown {
    param([string] $Language)

    # What was told of how many, in the language: each thing told read again with how many (its own words)
    $told = @((Get-LambekTold).ToArray())
    $here = @($told | Where-Object { $_.PSObject.Properties['Hash'] -and $_.Hash } | ForEach-Object { $_.Hash })
    $before = @((Get-LambekToldJournal).ToArray() | Where-Object { $_.Hash -notin $here })
    foreach ($fact in @($before) + @($told)) {
        if (-not $fact -or "$($fact.Language)" -ne $Language -or -not $fact.Text) { continue }
        if ($fact.PSObject.Properties['Replaced'] -and $fact.Replaced) { continue }
        $core = $(if ($fact.PSObject.Properties['Core']) { "$($fact.Core)" } else { '' })
        if ($core -and -not ($core.StartsWith('count(') -or $core.StartsWith('category(some|'))) { continue }
        $item = Read-LambekCategoryTagged -Sentence (("$($fact.Text)".Trim()) -replace '[.!;]+\s*$', '') -Language $Language -Counting
        if (-not $item -or -not $item.PSObject.Properties['Count'] -or $item.Kind -notin 'some', 'count') { continue }
        [pscustomobject]@{ Fact = $fact; Item = $item }
    }
}

function Test-LambekCountWithin {
    param([string[]] $Narrow, [string[]] $Wide, [object[]] $Known)

    # Whether every one of the narrow is one of the wide, and what it rests on: nothing when the wide is a part of the
    # narrow ("chats noirs" are "chats"); else the fewest rules told that say it (the reasoning on kinds); $null when
    # nothing told says it
    if (@($Wide | Where-Object { $_ -notin $Narrow }).Count -eq 0) { return , @() }
    if ($Known.Count -eq 0) { return $null }
    $table = @{}
    $statements = [LambekCategoryStatement[]] @($Known | ForEach-Object { ConvertTo-LambekCategoryStatement -Item $_.Item -Atoms $table })
    $index = { param($atom) if (-not $table.ContainsKey($atom)) { $table[$atom] = $table.Count + 1 }; [int] $table[$atom] }
    $opposite = [LambekCategoryStatement]::new()
    $witness = $opposite.AddWitness()
    foreach ($atom in $Narrow) { $opposite.AddToWitness($witness, [int[]] @(& $index $atom)) }
    foreach ($clause in (ConvertTo-LambekCategoryClause -Atoms $Wide -Index $index -Not)) { $opposite.AddToWitness($witness, [int[]] $clause) }
    $keys = [string[]] @($Known | ForEach-Object { Get-LambekCategorySignature -Item $_.Item })
    $found = [LambekCategories]::Shortest($statements, $opposite, $keys, [LambekCategories]::DefaultBudget)
    if (-not $found) { return $null }
    return , @($found.Indices | ForEach-Object { $Known[$_] })
}

function Resolve-LambekCountQuestion {
    param([pscustomobject] $Ask, [string] $Language)

    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    $ask = $Ask.Item
    $counted = @(Get-LambekCountKnown -Language $Language)
    $rules = @(Get-LambekCategoryKnown -Language $Language | Where-Object { $_.Item.Kind -in 'all', 'no' -and -not ($_.Item.PSObject.Properties['Default'] -and $_.Item.Default) })
    $subject = [string[]] @($ask.Subject.Atoms)
    $predicate = [string[]] @($ask.Predicate.Atoms)
    # (one told: at least so many of a kind narrower than the one asked of, being something narrower, say at least as
    # many of it; at most so many of a kind wider, being something wider, say at most as many)
    $upward = {
        param($told)
        $s = Test-LambekCountWithin -Narrow ([string[]] @($told.Item.Subject.Atoms)) -Wide $subject -Known $rules
        if ($null -eq $s) { return $null }
        $p = Test-LambekCountWithin -Narrow ([string[]] @($told.Item.Predicate.Atoms)) -Wide $predicate -Known $rules
        if ($null -eq $p) { return $null }
        , @(@($s) + @($p))
    }
    $downward = {
        param($told)
        $s = Test-LambekCountWithin -Narrow $subject -Wide ([string[]] @($told.Item.Subject.Atoms)) -Known $rules
        if ($null -eq $s) { return $null }
        $p = Test-LambekCountWithin -Narrow $predicate -Wide ([string[]] @($told.Item.Predicate.Atoms)) -Known $rules
        if ($null -eq $p) { return $null }
        , @(@($s) + @($p))
    }
    # (the first that does, the fewest things it rests on first)
    $first = {
        param([scriptblock] $fits, [scriptblock] $way)
        $best = $null
        foreach ($told in $counted) {
            if (-not (& $fits $told.Item.Count)) { continue }
            $rests = & $way $told
            if ($null -eq $rests) { continue }
            if ($null -eq $best -or @($rests).Count -lt @($best.Rests).Count) { $best = [pscustomobject]@{ Told = $told; Rests = @($rests) } }
        }
        $best
    }
    $least = $ask.Count.Least
    $most = $ask.Count.Most
    $yes = @()
    $no = @()
    if ($null -ne $least) {
        $over = & $first { param($c) $null -ne $c.Least -and $c.Least -ge $least } $upward
        $under = & $first { param($c) $null -ne $c.Most -and $c.Most -lt $least } $downward
        if ($over) { $yes += $over }
        if ($under) { $no += $under }
    }
    if ($null -ne $most) {
        $within = & $first { param($c) $null -ne $c.Most -and $c.Most -le $most } $downward
        $beyond = & $first { param($c) $null -ne $c.Least -and $c.Least -gt $most } $upward
        if ($within) { $yes += $within }
        if ($beyond) { $no += $beyond }
    }
    $asked = @(@($least, $most) | Where-Object { $null -ne $_ }).Count
    $lines = [System.Collections.Generic.List[string]]::new()
    $list = {
        param($found)
        $shown = @{}
        $steps = @(foreach ($one in $found) { $one.Told.Fact; foreach ($rule in $one.Rests) { $rule.Fact } })
        foreach ($fact in $steps) {
            if (-not $fact) { continue }
            $line = "- $(Format-LambekFact -Fact $fact -Language $Language -Register 'vous' -Bare)"
            if (-not $shown.ContainsKey($line)) { $shown[$line] = $true; $lines.Add($line) }
        }
        , $steps
    }
    $forms = {
        param($found)
        @(foreach ($one in $found) {
                ConvertTo-LambekCountForm -Item $one.Told.Item
                foreach ($rule in $one.Rests) { "category($(Get-LambekCategorySignature -Item $rule.Item))" }
            }) | Select-Object -Unique
    }
    if ($no.Count -gt 0) {
        $lines.Add($data['NoShort'])
        if ($data['Because']) { $lines.Add($data['Because']) }
        $steps = & $list @($no[0])
        $way = $(if ($null -ne $least -and $null -ne $no[0].Told.Item.Count.Most -and $no[0].Told.Item.Count.Most -lt $least) { 'notleast' } else { 'notmost' })
        Set-LambekLastProof -Facts @($steps | Where-Object { $_ } | Select-Object -Unique) -Conclusion @(ConvertTo-LambekCountForm -Item $ask -Way $way) -Forms @(& $forms @($no[0]))
    }
    elseif ($yes.Count -eq $asked) {
        $lines.Add($data['YesShort'])
        if ($data['Because']) { $lines.Add($data['Because']) }
        $steps = & $list $yes
        $concluded = @(if ($null -ne $least) { ConvertTo-LambekCountForm -Item $ask -Way 'least' }; if ($null -ne $most) { ConvertTo-LambekCountForm -Item $ask -Way 'most' })
        Set-LambekLastProof -Facts @($steps | Where-Object { $_ } | Select-Object -Unique) -Conclusion $concluded -Forms @(& $forms $yes)
    }
    else {
        Set-LambekLastProof
        $said = ConvertTo-LambekOtherSide -Text $ask.Statement -Language $Language -Register 'vous'
        if (-not $said) { $said = $ask.Statement }
        $said = $said.Trim().TrimEnd('.')
        # (with a small letter where the question had one: "au moins quatre chats sont noirs")
        if ("$($ask.Statement)" -cmatch '^\p{Ll}' -and $said) { $said = $said.Substring(0, 1).ToLowerInvariant() + $said.Substring(1) }
        $lines.Add(($data['Unknown'] -f ($say['Quote'] -f $said)))
    }
    return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = @() }
}
