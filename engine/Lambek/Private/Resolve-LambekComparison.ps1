function Resolve-LambekComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # One compared with another, and what follows of it, exactly: "Rex est plus grand que Max", "Max est plus grand que
    # Tom", "Rex est-il plus grand que Tom ?" -> yes, and why; "Tom est-il plus grand que Rex ?" -> no, and why. Being
    # more of something than another goes on (what is more than one that is more than a third is more than the third)
    # and never back (what is more than another is not less than it). Read by the tags of the forms model of each
    # language and the words it learned for "more", "less" and "than" (Dialogue.General.Comparing); every
    # sentence of the message must read as one, or nothing is taken
    if ($Text -notmatch '\p{L}') { return $null }
    $detected = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) -Forms
    $languages = @(@($detected) + @(Get-LambekAvailableLanguage | Where-Object { $_ -ne $detected } | Sort-Object))
    foreach ($language in $languages) {
        if (-not (Get-LambekComparisonWord -Language $language)) { continue }
        $sentences = @(Split-LambekCategorySentence -Text $Text -Language $language)
        if ($sentences.Count -eq 0) { continue }
        $items = @(foreach ($sentence in $sentences) {
                $read = Read-LambekComparison -Sentence $sentence.Text -Language $language -Question:$sentence.Question
                if (-not $read) { break }
                [pscustomobject]@{ Sentence = $sentence; Item = $read }
            })
        if ($items.Count -ne $sentences.Count) { continue }
        return Resolve-LambekComparisonMessage -Items $items -Language $language
    }
    return $null
}

function Get-LambekComparisonWord {
    param([string] $Language)

    # The words of a language that say more, less and than (Dialogue.General.Comparing); nothing when it has none
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $general = $(if ($dialogue -and $dialogue['General']) { $dialogue['General'] } else { $null })
    if (-not $general -or -not $general.Contains('Comparing')) { return $null }
    $words = $general['Comparing']
    if (-not $words -or -not $words['Than'] -or @($words['Than']).Count -eq 0) { return $null }
    $plain = { param($list) @(@($list) | Where-Object { $_ } | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" }) }
    return [pscustomobject]@{ More = (& $plain $words['More']); Less = (& $plain $words['Less']); Than = (& $plain $words['Than']) }
}

function Read-LambekComparison {
    param([string] $Sentence, [string] $Language, [switch] $Question)

    # "Rex est plus grand que Max", "Rex is taller than Max", "ist Rex groesser als Max?": who is more, who is less, and
    # of what (the lemma of the adjective). Asked with the verb first ("is Rex taller than Max") or after it
    # ("Rex est-il plus grand que Max"); one said with "moins" or "less" is the other way round. Nothing when the
    # sentence says not, or when either side is not one named
    $words = Get-LambekComparisonWord -Language $Language
    $model = Get-LambekFormModel -Language $Language
    $logic = Get-LambekLogicWord -Language $Language
    if (-not $words -or -not $model -or -not $logic) { return $null }
    # (asked as the language asks before the sentence, "est-ce que", "est-ce qu'": what follows is asked)
    $text = ($Sentence.Trim() -replace '^\p{P}+', '' -replace '\p{P}+$', '')
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $lead = $(if ($dialogue -and $dialogue['General']) { "$($dialogue['General']['Inverted'])" } else { '' })
    if ($lead) {
        $parts = @(($lead -replace '-', ' ') -split '\s+' | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) })
        $last = $parts[-1]
        $pattern = '(?i)^' + ((@($parts | Select-Object -SkipLast 1) + @("$($last.Substring(0, $last.Length - 1))(?:$($last.Substring($last.Length - 1))\s+|['\u2019])")) -join '[\s-]+')
        $match = [regex]::Match($text, $pattern)
        if ($match.Success) { $text = $text.Substring($match.Length).Trim(); $Question = $true }
    }
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($token in @($text -split '\s+' | Where-Object { $_ })) {
        # (a pronoun after the verb, joined to it, is the one asked of said again: "est-il" is "est")
        $cut = [regex]::Match($token, '^(?<verb>\p{L}+)-(?:t-)?(?<pronoun>\p{L}+)$')
        if ($cut.Success) {
            $tags = $null
            if ($model.Tags.TryGetValue($cut.Groups['pronoun'].Value.ToLowerInvariant(), [ref] $tags) -and @($tags | Where-Object { "$_".StartsWith('PRON|') }).Count -gt 0) { $tokens.Add($cut.Groups['verb'].Value); continue }
        }
        # (the elided "than", "qu'": a word of its own)
        $elided = [regex]::Match($token, "^(?<than>\p{L}+['\u2019])(?<rest>\p{L}.*)$")
        if ($elided.Success -and (ConvertTo-LambekNormalizedText -Text $elided.Groups['than'].Value.TrimEnd("'", [char] 0x2019)) -in $words.Than) {
            $tokens.Add($elided.Groups['than'].Value.TrimEnd("'", [char] 0x2019)); $tokens.Add($elided.Groups['rest'].Value); continue
        }
        $tokens.Add($token)
    }
    $readings = @($model.Read([string[]] $tokens.ToArray()))
    if ($readings.Count -ne $tokens.Count) { return $null }
    $plain = @($tokens | ForEach-Object { ConvertTo-LambekNormalizedText -Text $_ })
    # (nothing said not: "Rex n'est pas plus grand que Max" says less than it seems)
    if (@($readings | Where-Object { "|$($_.Feats)|" -match '\|(Polarity|PronType)=Neg\|' }).Count -gt 0) { return $null }
    $than = @(for ($i = 0; $i -lt $plain.Count; $i++) { if ($plain[$i] -in $words.Than) { $i } })
    if ($than.Count -ne 1 -or $than[0] -lt 2 -or $than[0] -ge $tokens.Count - 1) { return $null }
    $t = $than[0]
    # How it is compared: "plus grand", "more beautiful", or one adjective said in its comparative ("taller", "groesser")
    $adjective = $t - 1
    if ("$($readings[$adjective].Upos)" -ne 'ADJ') {
        $known = $null
        $listed = $model.Lexicon -and $model.Lexicon.Forms.ContainsKey($plain[$adjective]) -and @($model.Lexicon.Forms[$plain[$adjective]] | Where-Object { "$($_.Upos)" -eq 'ADJ' }).Count -gt 0
        $tagged = $model.Tags.TryGetValue($tokens[$adjective].ToLowerInvariant(), [ref] $known) -and @($known | Where-Object { "$_".StartsWith('ADJ|') }).Count -gt 0
        if (-not ($listed -or $tagged)) { return $null }
    }
    $more = $null
    $start = $adjective
    if ($plain[$adjective - 1] -in $words.More) { $more = $true; $start = $adjective - 1 }
    elseif ($plain[$adjective - 1] -in $words.Less) { $more = $false; $start = $adjective - 1 }
    elseif ("|$($readings[$adjective].Feats)|" -match '\|Degree=Cmp\|') { $more = $true }
    if ($null -eq $more) { return $null }
    $lemma = ConvertTo-LambekNormalizedText -Text "$(if ($readings[$adjective].Lemma) { $readings[$adjective].Lemma } else { $tokens[$adjective] })"
    if (-not $lemma) { return $null }
    # The copula, and who is compared: before it when told, after it when it is asked first
    $isCopula = { param($i) $i -ge 0 -and "$($readings[$i].Lemma)".ToLowerInvariant() -in $logic.Copulas }
    $asking = $Question
    $copula = $null
    if (& $isCopula 0) { $copula = 0; $asking = $true; $who = @($tokens[1..($start - 1)]) }
    else {
        $copula = $start - 1
        if (-not (& $isCopula $copula)) { return $null }
        $who = @($tokens[0..($copula - 1)])
    }
    if ($who.Count -eq 0) { return $null }
    $other = @($tokens[($t + 1)..($tokens.Count - 1)])
    $one = ConvertTo-LambekCategoryIndividual -Text ($who -join ' ') -Language $Language
    $two = ConvertTo-LambekCategoryIndividual -Text ($other -join ' ') -Language $Language
    if (-not $one -or -not $two -or "$($one.Key)" -eq "$($two.Key)") { return $null }
    $greater = $(if ($more) { $one } else { $two })
    $smaller = $(if ($more) { $two } else { $one })
    return [pscustomobject]@{
        Kind     = $(if ($asking) { 'askcompare' } else { 'compare' })
        Of       = $lemma
        Greater  = $greater
        Smaller  = $smaller
        # (said again with the words of the sentence: the one, the verb, how, than, the other)
        Said     = ((@($who) + @($(if ($copula -eq 0) { $tokens[$copula].ToLowerInvariant() } else { $tokens[$copula] })) + @($tokens[$start..$t]) + @($other)) -join ' ')
        # (and the other way round, for an answer no: "Rex est plus grand que Tom" when "Tom" was asked of)
        Back     = ((@($other) + @($(if ($copula -eq 0) { $tokens[$copula].ToLowerInvariant() } else { $tokens[$copula] })) + @($tokens[$start..$t]) + @($who)) -join ' ')
    }
}

function Get-LambekComparisonForm {
    param([pscustomobject] $Item, [switch] $Not)

    # The shape the checker reads: compare(more|grand|name:rex|name:max), "notmore" for what is not more
    return "compare($(if ($Not) { 'notmore' } else { 'more' })|$($Item.Of)|$($Item.Greater.Key)|$($Item.Smaller.Key))"
}

function Get-LambekComparisonKnown {
    param([string] $Language)

    # What was told, here and before, read as one compared with another
    $told = @((Get-LambekTold).ToArray())
    $here = @($told | Where-Object { $_.PSObject.Properties['Hash'] -and $_.Hash } | ForEach-Object { $_.Hash })
    $before = @((Get-LambekToldJournal).ToArray() | Where-Object { $_.Hash -notin $here })
    foreach ($fact in @($before) + @($told)) {
        if ("$($fact.Language)" -ne $Language -or -not $fact.Text) { continue }
        if ($fact.PSObject.Properties['Replaced'] -and $fact.Replaced) { continue }
        $read = Read-LambekComparison -Sentence (("$($fact.Text)".Trim()) -replace '[.!;]+\s*$', '') -Language $Language
        if ($read -and $read.Kind -eq 'compare') { [pscustomobject]@{ Fact = $fact; Item = $read } }
    }
}

function Find-LambekComparisonPath {
    param([object[]] $Known, [string] $Of, [string] $From, [string] $To)

    # The things told that lead from one more to another less, one after the other: what is more than one that is
    # more than a third is more than the third. The shortest way, found breadth first; nothing when there is none
    $edges = @($Known | Where-Object { $_.Item.Of -eq $Of })
    $came = @{ $From = $null }
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($From)
    while ($queue.Count -gt 0) {
        $at = $queue.Dequeue()
        if ($at -eq $To) {
            $path = [System.Collections.Generic.List[object]]::new()
            $step = $To
            while ($null -ne $came[$step]) { $path.Insert(0, $came[$step]); $step = "$($came[$step].Item.Greater.Key)" }
            return , $path.ToArray()
        }
        foreach ($edge in @($edges | Where-Object { "$($_.Item.Greater.Key)" -eq $at })) {
            $next = "$($edge.Item.Smaller.Key)"
            if ($came.ContainsKey($next)) { continue }
            $came[$next] = $edge
            $queue.Enqueue($next)
        }
    }
    return $null
}

function ConvertTo-LambekComparisonFact {
    param([pscustomobject] $Sentence, [pscustomobject] $Item, [string] $Language)

    # A sentence of the message, kept as a thing told, said back as it was said
    $form = Get-LambekComparisonForm -Item $Item
    return [pscustomobject]@{
        Action     = 'verb:comparison'
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

function Resolve-LambekComparisonMessage {
    param([object[]] $Items, [string] $Language)

    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    $asks = @($Items | Where-Object { $_.Item.Kind -eq 'askcompare' })
    if ($asks.Count -gt 1 -or ($asks.Count -eq 1 -and -not [object]::ReferenceEquals($asks[0], $Items[-1]))) { return $null }
    $facts = @(foreach ($entry in $Items) { if ($entry.Item.Kind -eq 'compare') { ConvertTo-LambekComparisonFact -Sentence $entry.Sentence -Item $entry.Item -Language $Language } })
    $known = @(Get-LambekComparisonKnown -Language $Language)
    $k = 0
    $now = @(foreach ($entry in $Items) { if ($entry.Item.Kind -eq 'compare') { [pscustomobject]@{ Fact = $facts[$k]; Item = $entry.Item }; $k++ } })
    $all = @($known) + @($now)
    $lines = [System.Collections.Generic.List[string]]::new()
    # (with a capital only where the answer starts a sentence with it: "Ja. Rex ist", "Oui : le chat est")
    $model = Get-LambekFormModel -Language $Language
    $sentence = {
        param([string] $text)
        if ("$($data['Yes'])" -match '[.!?]\s*\{0\}') { return $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1) }
        $first = @($text -split '\s+')[0]
        $reading = @($(if ($model) { $model.Read([string[]] @($first)) }))
        if ($reading.Count -eq 1 -and "$($reading[0].Upos)" -ne 'PROPN') { return $text.Substring(0, 1).ToLowerInvariant() + $text.Substring(1) }
        return $text
    }
    if ($asks.Count -eq 0) {
        # Told: said back; and said at once when it goes back on what was told (more and less than the same one)
        $shape = 'Noted'
        if ($script:Incognito) { $shape += 'Here' }
        $lines.Add(($say[$shape] -f (@($facts | ForEach-Object { Format-LambekFact -Fact $_ -Language $Language -Register 'vous' }) -join ' ')))
        foreach ($entry in $now) {
            $back = Find-LambekComparisonPath -Known $all -Of $entry.Item.Of -From "$($entry.Item.Smaller.Key)" -To "$($entry.Item.Greater.Key)"
            if ($back) {
                $lines.Add($data['Clash'])
                foreach ($step in @(@($back) + @($entry))) { $lines.Add("- $(Format-LambekFact -Fact $step.Fact -Language $Language -Register 'vous' -Bare)") }
                break
            }
        }
        Set-LambekLastProof
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }
    $ask = $asks[0].Item
    $said = ConvertTo-LambekOtherSide -Text $ask.Said -Language $Language -Register 'vous'
    if (-not $said) { $said = $ask.Said }
    $said = $said.Trim().TrimEnd('.')
    $listed = { param($path) foreach ($step in $path) { $lines.Add("- $(Format-LambekFact -Fact $step.Fact -Language $Language -Register 'vous' -Bare)") } }
    $proof = {
        param($path, [string] $concluded)
        Set-LambekLastProof -Facts @($path | ForEach-Object { $_.Fact }) -Conclusion @($concluded) -Forms @($path | ForEach-Object { Get-LambekComparisonForm -Item $_.Item })
    }
    $yes = Find-LambekComparisonPath -Known $all -Of $ask.Of -From "$($ask.Greater.Key)" -To "$($ask.Smaller.Key)"
    if ($yes) {
        $lines.Add(($data['Yes'] -f (& $sentence $said)))
        if ($data['Because']) { $lines.Add($data['Because']) }
        & $listed $yes
        & $proof $yes (Get-LambekComparisonForm -Item $ask)
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }
    # (what is more than another is not less than it: the way the other way round says no)
    $no = Find-LambekComparisonPath -Known $all -Of $ask.Of -From "$($ask.Smaller.Key)" -To "$($ask.Greater.Key)"
    if ($no) {
        # (no, said as what holds: the other is the one that is more)
        $back = ConvertTo-LambekOtherSide -Text $ask.Back -Language $Language -Register 'vous'
        if (-not $back) { $back = $ask.Back }
        $lines.Add(($data['No'] -f (& $sentence $back.Trim().TrimEnd('.'))))
        if ($data['Because']) { $lines.Add($data['Because']) }
        & $listed $no
        & $proof $no (Get-LambekComparisonForm -Item $ask -Not)
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }
    # (nothing told of either compared so: the question is for the rest of Lambek)
    $named = "$($ask.Greater.Key)", "$($ask.Smaller.Key)"
    $about = @($all | Where-Object { $_.Item.Of -eq $ask.Of -and @("$($_.Item.Greater.Key)", "$($_.Item.Smaller.Key)" | Where-Object { $_ -in $named }).Count -gt 0 })
    if ($about.Count -eq 0 -and $facts.Count -eq 0) { return $null }
    Set-LambekLastProof
    $lines.Add(($data['Unknown'] -f ($say['Quote'] -f $said)))
    return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
}
