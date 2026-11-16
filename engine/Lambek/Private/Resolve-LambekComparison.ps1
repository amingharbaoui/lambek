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
        $items = [System.Collections.Generic.List[object]]::new()
        $read = 0
        foreach ($sentence in $sentences) {
            # (read with its commas when they are all it has more: "Rex, Max et Paul" are three)
            $words = $sentence.Text
            $marked = (("$($sentence.Original)" -replace '[.!?;]+\s*$', '') -replace "^[\p{Po}-['\u2019]]+", '').Trim()
            if ($marked -match ',' -and (($marked -replace ',', ' ') -replace '\s+', ' ').Trim() -ceq $words) { $words = $marked }
            $pairs = @(Read-LambekComparison -Sentence $words -Language $language -Question:$sentence.Question | Where-Object { $_ })
            if ($pairs.Count -eq 0) { break }
            foreach ($pair in $pairs) { $items.Add([pscustomobject]@{ Sentence = $sentence; Item = $pair }) }
            $read++
        }
        if ($read -ne $sentences.Count) { continue }
        $items = $items.ToArray()
        return Resolve-LambekComparisonMessage -Items $items -Language $language
    }
    return Resolve-LambekComparisonDegree -Text $Text
}

function Resolve-LambekComparisonDegree {
    param([string] $Text)

    # What one is, from one it is more so than: "Max est grand", "Rex est plus grand que Max": "Rex est-il grand ?" ->
    # yes. One is so when it is more so than one that is, and not so when it is less so than one that is not (being
    # so is being so beyond some point, the same for both). Only a question alone, about one named, of one word said
    # of it; what was told of that one itself is left to the reasoning on kinds
    # (in the language the question reads in where something was told compared so, the one it seems in first)
    $first = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) -Forms
    $detected = $null
    foreach ($language in @(@($first) + @(Get-LambekAvailableLanguage | Where-Object { $_ -ne $first } | Sort-Object))) {
        if (-not $language -or -not (Get-LambekComparisonWord -Language $language)) { continue }
        $sentences = @(Split-LambekCategorySentence -Text $Text -Language $language)
        if ($sentences.Count -ne 1 -or -not $sentences[0].Question) { continue }
        $known = @(Get-LambekComparisonKnown -Language $language)
        if ($known.Count -eq 0) { continue }
        $ask = Read-LambekCategorySentence -Sentence $sentences[0].Text -Language $language -Question
        if (-not $ask -or $ask.Kind -ne 'askis' -or -not $ask.Individual -or $ask.Verb -or $ask.Quantifier) { continue }
        $atoms = @($ask.Predicate.Atoms)
        if ($atoms.Count -ne 1) { continue }
        # (the word as the reasoning on kinds keeps it, "op:fast" for one its dictionary does not know apart)
        $atom = "$($atoms[0])"
        $of = $atom -replace '^op:', ''
        $compared = @($known | Where-Object { $_.Item.Of -eq $of })
        if ($compared.Count -gt 0) { $detected = $language; break }
    }
    if (-not $detected) { return $null }
    $who = "$($ask.Individual.Key)"
    $said = @(Get-LambekCategoryKnown -Language $detected | Where-Object {
            $_.Item.Kind -in 'is', 'isnot' -and $_.Item.Individual -and -not ($_.Item.PSObject.Properties['Default'] -and $_.Item.Default) -and
            @($_.Item.Predicate.Atoms).Count -eq 1 -and "$(@($_.Item.Predicate.Atoms)[0])" -eq $atom
        })
    if (@($said | Where-Object { "$($_.Item.Individual.Key)" -eq $who }).Count -gt 0) { return $null }
    # (the shortest way: to one said to be so, or from one said not to be)
    $ways = [System.Collections.Generic.List[object]]::new()
    foreach ($one in $said) {
        $other = "$($one.Item.Individual.Key)"
        $path = $(if ($one.Item.Kind -eq 'is') { Find-LambekComparisonPath -Known $compared -Of $of -From $who -To $other } else { Find-LambekComparisonPath -Known $compared -Of $of -From $other -To $who })
        if ($path) { $ways.Add([pscustomobject]@{ Kind = $one.Item.Kind; Path = $path; Said = $one }) }
    }
    $yes = @($ways | Where-Object Kind -EQ 'is' | Sort-Object { @($_.Path).Count } | Select-Object -First 1)
    $no = @($ways | Where-Object Kind -EQ 'isnot' | Sort-Object { @($_.Path).Count } | Select-Object -First 1)
    # (both: what was told cannot all be true, and that is for the reasoning on kinds to say)
    if (($yes.Count -gt 0) -eq ($no.Count -gt 0)) { return $null }
    $found = $(if ($yes.Count -gt 0) { $yes[0] } else { $no[0] })
    $shape = $(if ($yes.Count -gt 0) { 'is' } else { 'isnot' })
    $data = (Get-LambekCategoryVocabulary -Language $detected).Data
    # (said as the answers on kinds are: "Oui : Rex est grand.", "Nein.")
    $template = "$($data[$(if ($shape -eq 'is') { 'Yes' } else { 'No' })])"
    $sentence = Get-LambekCategorySentence -Item $ask -Shape $shape -Language $detected
    if (-not $template -or (-not $sentence -and $template -match '\{0\}')) { return $null }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(($template -f $sentence))
    if ($data['Because']) { $lines.Add($data['Because']) }
    $steps = @(Select-LambekComparisonOnce -Items @($found.Path) -Key { param($s) "$($s.Fact.Joined)|$($s.Fact.Text)|$(Get-LambekComparisonForm -Item $s.Item)" })
    $facts = @(@($steps | ForEach-Object { $_.Fact }) + @($found.Said.Fact))
    $shown = @{}
    foreach ($fact in $facts) {
        $line = "- $(Format-LambekFact -Fact $fact -Language $detected -Register 'vous' -Bare)"
        if (-not $shown.ContainsKey($line)) { $shown[$line] = $true; $lines.Add($line) }
    }
    Set-LambekLastProof -Facts $facts -Conclusion @(Get-LambekCategoryConclusion -Item $ask -Shape $shape) `
        -Forms @(@($steps | ForEach-Object { (Get-LambekComparisonForm -Item $_.Item) -replace '^compare\((more|notmore)\|[^|]*\|', "compare(`$1|$atom|" }) + @("category($(Get-LambekCategorySignature -Item $found.Said.Item))"))
    return [pscustomobject]@{ Language = $detected; Reply = ($lines -join "`n"); Facts = @() }
}

function Select-LambekComparisonOnce {
    param([object[]] $Items, [scriptblock] $Key)

    # Each once, in the order they came: a sentence of several said back once, a thing told listed once
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($item in $Items) { if ($seen.Add("$(& $Key $item)")) { $item } }
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
    # (a comma after a word ends one named of several: kept apart from the word, by its place)
    $commas = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($word in @($text -split '\s+' | Where-Object { $_ })) {
        $token = $word.TrimEnd(',')
        if (-not $token) { continue }
        if ($token.Length -lt $word.Length) { [void] $commas.Add($tokens.Count) }
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
    $not = @(Get-LambekNotWord -Language $Language)
    if (@($readings | Where-Object { "|$($_.Feats)|" -match '\|(Polarity|PronType)=Neg\|' -or (ConvertTo-LambekNormalizedText -Text "$($_.Form)") -in $not }).Count -gt 0) { return $null }
    $than = @(for ($i = 0; $i -lt $plain.Count; $i++) { if ($plain[$i] -in $words.Than) { $i } })
    if ($than.Count -ne 1 -or $than[0] -lt 2 -or $than[0] -ge $tokens.Count - 1) { return $null }
    $t = $than[0]
    # How it is compared: "plus grand", "more beautiful", or one adjective said in its comparative ("taller", "groesser")
    $adjective = $t - 1
    $feats = "$($readings[$adjective].Feats)"
    $lemma = "$($readings[$adjective].Lemma)"
    if ("$($readings[$adjective].Upos)" -ne 'ADJ') {
        # (read otherwise in its sentence, "faster" a noun before "than": an adjective when its treebanks or its
        # dictionary say it is one, with the features and the lemma of that tag)
        $known = $null
        $listed = $model.Lexicon -and $model.Lexicon.Forms.ContainsKey($plain[$adjective]) -and @($model.Lexicon.Forms[$plain[$adjective]] | Where-Object { "$($_.Upos)" -eq 'ADJ' }).Count -gt 0
        $tags = @($(if ($model.Tags.TryGetValue($tokens[$adjective].ToLowerInvariant(), [ref] $known)) { $known | Where-Object { "$_".StartsWith('ADJ|') } }))
        if (-not $listed -and $tags.Count -eq 0) { return $null }
        if ($tags.Count -gt 0) {
            $feats = "$($tags[0])".Substring(4)
            $lemma = $model.LemmaFor($tokens[$adjective], "$($tags[0])")
        }
        elseif ($listed) { $lemma = "$(@($model.Lexicon.Forms[$plain[$adjective]] | Where-Object { "$($_.Upos)" -eq 'ADJ' })[0].Lemma)" }
    }
    $more = $null
    $start = $adjective
    if ($plain[$adjective - 1] -in $words.More) { $more = $true; $start = $adjective - 1 }
    elseif ($plain[$adjective - 1] -in $words.Less) { $more = $false; $start = $adjective - 1 }
    elseif ("|$feats|" -match '\|Degree=Cmp\|') { $more = $true }
    if ($null -eq $more) { return $null }
    $lemma = ConvertTo-LambekNormalizedText -Text "$(if ($lemma) { $lemma } else { $tokens[$adjective] })"
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
    # Each side one named, or several joined by the word that says both ("Rex et Max sont plus grands que Tom"): one
    # compared with one for each two, the sentence kept whole. A word of the sentence read as a name or a thing by its
    # tags is one even when the dictionary does not know it ("the XR-200")
    $lemmas = @{}
    foreach ($reading in $readings) {
        if ("$($reading.Upos)" -notin 'NOUN', 'ADJ', 'PROPN' -or -not $reading.Lemma) { continue }
        $lemmas[(ConvertTo-LambekNormalizedText -Text "$($reading.Form)")] = ConvertTo-LambekNormalizedText -Text "$($reading.Lemma)"
    }
    $and = @(Get-LambekConjunctionWord -Language $Language | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" })
    $side = {
        param([int] $from, [int] $to)
        $parts = [System.Collections.Generic.List[string]]::new()
        $part = [System.Collections.Generic.List[string]]::new()
        for ($i = $from; $i -le $to; $i++) {
            if ((ConvertTo-LambekNormalizedText -Text $tokens[$i]) -in $and) { $parts.Add(($part -join ' ')); $part.Clear(); continue }
            $part.Add($tokens[$i])
            if ($commas.Contains($i)) { $parts.Add(($part -join ' ')); $part.Clear() }
        }
        $parts.Add(($part -join ' '))
        $found = [System.Collections.Generic.List[object]]::new()
        foreach ($text in $parts) {
            $one = $(if ($text) { ConvertTo-LambekCategoryIndividual -Text $text -Language $Language -Lemmas $lemmas })
            if (-not $one) { return , @() }
            $found.Add($one)
        }
        , $found.ToArray()
    }
    $first = $(if ($copula -eq 0) { 1 } else { 0 })
    $ones = & $side $first ($first + $who.Count - 1)
    $twos = & $side ($t + 1) ($tokens.Count - 1)
    if ($ones.Count -eq 0 -or $twos.Count -eq 0) { return $null }
    $keys = @(@($ones) + @($twos) | ForEach-Object { "$($_.Key)" })
    if (@($keys | Select-Object -Unique).Count -ne $keys.Count) { return $null }
    $verb = $(if ($copula -eq 0) { $tokens[$copula].ToLowerInvariant() } else { $tokens[$copula] })
    $written = { param([int] $from, [int] $to) @(for ($i = $from; $i -le $to; $i++) { "$($tokens[$i])$(if ($commas.Contains($i) -and $i -lt $to) { ',' })" }) }
    $who = & $written $first ($first + $who.Count - 1)
    $other = & $written ($t + 1) ($tokens.Count - 1)
    foreach ($one in $ones) {
        foreach ($two in $twos) {
            [pscustomobject]@{
                Kind    = $(if ($asking) { 'askcompare' } else { 'compare' })
                Of      = $lemma
                Greater = $(if ($more) { $one } else { $two })
                Smaller = $(if ($more) { $two } else { $one })
                # (said again with the words of the sentence: the one, the verb, how, than, the other)
                Said    = ((@($who) + @($verb) + @($tokens[$start..$t]) + @($other)) -join ' ')
                # (and the other way round, for an answer no: "Rex est plus grand que Tom" when "Tom" was asked of)
                Back    = ((@($other) + @($verb) + @($tokens[$start..$t]) + @($who)) -join ' ')
                Several = ($ones.Count * $twos.Count) -gt 1
            }
        }
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
        # (what was kept as a thing one is, or a rule about kinds, says no one is more than another)
        if ($fact.PSObject.Properties['Core'] -and "$($fact.Core)".StartsWith('category(')) { continue }
        foreach ($read in @(Read-LambekComparison -Sentence (("$($fact.Text)".Trim()) -replace '[.!;]+\s*$', '') -Language $Language | Where-Object { $_ })) {
            # (a sentence of several kept once for each two: each read back as the two it was kept for)
            if ($read.Kind -ne 'compare') { continue }
            if ($fact.PSObject.Properties['Core'] -and "$($fact.Core)".StartsWith('compare(') -and "$($fact.Core)" -ne "$(Get-LambekComparisonForm -Item $read)|") { continue }
            [pscustomobject]@{ Fact = $fact; Item = $read }
        }
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
    # (one question, the last sentence; asked of several, one for each two)
    if (@($asks | Where-Object { -not [object]::ReferenceEquals($_.Sentence, $Items[-1].Sentence) }).Count -gt 0) { return $null }
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
        # (a sentence of several said back once)
        $once = @(Select-LambekComparisonOnce -Items $facts -Key { param($f) "$($f.Joined)" })
        $lines.Add(($say[$shape] -f (@($once | ForEach-Object { Format-LambekFact -Fact $_ -Language $Language -Register 'vous' }) -join ' ')))
        foreach ($entry in $now) {
            $back = Find-LambekComparisonPath -Known $all -Of $entry.Item.Of -From "$($entry.Item.Smaller.Key)" -To "$($entry.Item.Greater.Key)"
            if ($back) {
                $lines.Add($data['Clash'])
                foreach ($step in @(Select-LambekComparisonOnce -Items @(@($back) + @($entry)) -Key { param($s) "$($s.Fact.Joined)|$($s.Fact.Text)" })) { $lines.Add("- $(Format-LambekFact -Fact $step.Fact -Language $Language -Register 'vous' -Bare)") }
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
    # (each thing told said once, even when the way goes through two of one sentence)
    $once = { param($path) @(Select-LambekComparisonOnce -Items @($path) -Key { param($s) "$($s.Fact.Joined)|$($s.Fact.Text)|$(Get-LambekComparisonForm -Item $s.Item)" }) }
    $listed = {
        param($path)
        $shown = @{}
        foreach ($step in (& $once $path)) {
            $line = "- $(Format-LambekFact -Fact $step.Fact -Language $Language -Register 'vous' -Bare)"
            if (-not $shown.ContainsKey($line)) { $shown[$line] = $true; $lines.Add($line) }
        }
    }
    $proof = {
        param($path, [string[]] $concluded)
        $steps = & $once $path
        Set-LambekLastProof -Facts @($steps | ForEach-Object { $_.Fact }) -Conclusion $concluded -Forms @($steps | ForEach-Object { Get-LambekComparisonForm -Item $_.Item })
    }
    if ($asks.Count -gt 1) {
        # Asked of several at once ("Rex et Max sont-ils plus grands que Tom ?"): yes when it holds for each two, no
        # when it does not hold for one of them; otherwise it may be true or false
        $path = [System.Collections.Generic.List[object]]::new()
        $each = $true
        foreach ($entry in $asks) {
            $way = Find-LambekComparisonPath -Known $all -Of $entry.Item.Of -From "$($entry.Item.Greater.Key)" -To "$($entry.Item.Smaller.Key)"
            if (-not $way) { $each = $false; break }
            foreach ($step in $way) { $path.Add($step) }
        }
        if ($each) {
            $lines.Add(($data['Yes'] -f (& $sentence $said)))
            if ($data['Because']) { $lines.Add($data['Because']) }
            $path = $path.ToArray()
            & $listed $path
            & $proof $path ([string[]] @($asks | ForEach-Object { Get-LambekComparisonForm -Item $_.Item }))
            return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
        }
        foreach ($entry in $asks) {
            $no = Find-LambekComparisonPath -Known $all -Of $entry.Item.Of -From "$($entry.Item.Smaller.Key)" -To "$($entry.Item.Greater.Key)"
            if (-not $no) { continue }
            $lines.Add($data['NoShort'])
            if ($data['Because']) { $lines.Add($data['Because']) }
            & $listed $no
            & $proof $no ([string[]] @(Get-LambekComparisonForm -Item $entry.Item -Not))
            return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
        }
        Set-LambekLastProof
        $lines.Add(($data['Unknown'] -f ($say['Quote'] -f $said)))
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
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
    # (nothing told leads either way: it may be true or false, said so, whether or not anything was told of them)
    Set-LambekLastProof
    $lines.Add(($data['Unknown'] -f ($say['Quote'] -f $said)))
    return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
}
