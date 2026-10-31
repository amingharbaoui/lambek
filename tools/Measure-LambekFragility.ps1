#Requires -Version 7.6
<#
.SYNOPSIS
    Looks for the smallest change that makes Lambek decide otherwise: for every calibration sentence of every bench
    (messages, real sentences, acts, requests), the decision Lambek takes, then the same sentence with one slip in the
    word that carries the most, sent as the app sends it.
.DESCRIPTION
    The robustness bench (Measure-LambekRobustness.ps1) spoils sentences at random; this one aims. A decision is what the
    reply is: an action ready to run, an answer said ("Lisbonne"), what was said only noted ("c'est note"), or Lambek
    holding back (it asks, does not know, did not understand). For each sentence:
      Fragile     one slip changed the decision (a question read as an order, another answer, an answer lost)
      EdgeBits    what the cheapest slip that changed the decision cost, in bits: which slip of the word it is among all
                  the slips of one letter the word could have had, and how much less likely the language model of
                  Lambek (Data/Speech) finds the sentence. StoodBits: the dearest slip a sentence stood, none changing it
      Unsafe      a slip created or changed an action, or turned an answer the bench finds right into one it finds wrong:
                  noise may make Lambek ask or hold back, never act or answer wrong (it must stay at 0)
      Ignored     the noun that carries the decision replaced by a noun of another sort, the furthest in the hierarchy of
                  meanings among the nouns of the benches ("quelle est la capitale du fichier ?"): an action, or the very
                  answer the clean sentence got, means the word was not read (measured, not yet a gate)
    The slips are the same for every language and every script: a letter left out, doubled, swapped with the next one,
    or a key next to it (the keyboards Lambek reads typing slips with). The words slipped first are those the language
    model knows least (they carry the decision: "Portugal" more than "la"); paths, file names and quoted text are left
    as they are. A conversation of several turns keeps its first turns and slips the last one.
    The choice of an action is also measured exactly: it is linear in the weights of its scorers (Data/scoring.json),
    so the smallest change of weights that turns a request found into a request asked about is a distance to a plane;
    the weights stay on their simplex (they sum to 1). Each distance is checked by deciding again with the weights moved.
    The effective information of the channel (Hoel) sums it up: how much the decision tells of what was meant, in bits,
    when every sentence is slipped; its determinism (a slip keeps the decision) and its degeneracy (sentences meant
    differently end up decided alike).
    The slips are drawn with a fixed seed, so every run is the same. Only calibration sentences are used: the test
    splits stay unseen.
.EXAMPLE
    ./tools/Measure-LambekFragility.ps1 -Show
    Also run at the end of ./build.ps1 -Task Benchmark, which stops when a slip makes an action or another answer.
#>
param(
    [int] $Seed = 49,

    # Slips tried for each sentence (the first ones, in the order the words carry the decision)
    [int] $Budget = 3,

    # At most this many sentences of each bench (the first ones), to keep a run short
    [int] $Limit = 0,

    # Only these benches (messages, real, acts, requests)
    [string[]] $Bench = @(),

    # Also print each sentence a slip changed, and the weights of the requests closest to their edge
    [switch] $Show
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-fragility-$PID"
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force
Import-LambekPack -Path (Join-Path $root 'dsl/files') | Out-Null
Import-LambekPack -Path (Join-Path $root 'dsl/code') | Out-Null

# The sentences: every calibration case of every bench, each as the turns of a conversation
$cases = [System.Collections.Generic.List[object]]::new()
$Bench = @($Bench | ForEach-Object { "$_" -split ',' } | Where-Object { $_ })
foreach ($name in 'messages', 'real', 'acts', 'requests') {
    if ($Bench.Count -gt 0 -and $name -notin $Bench) { continue }
    $data = Get-Content -LiteralPath (Join-Path $root "bench/$name.json") -Raw -Encoding utf8 | ConvertFrom-Json
    $picked = @($data.Cases | Where-Object Split -EQ 'calibration')
    if ($Limit -gt 0) { $picked = @($picked | Select-Object -First $Limit) }
    foreach ($case in $picked) {
        $language = $(if ($case.PSObject.Properties['Language'] -and $case.Language) { [string] $case.Language } elseif (@($case.Tags) -contains 'fr') { 'fr' } else { 'en' })
        $turns = @(if ($case.PSObject.Properties['Turns']) { @($case.Turns | ForEach-Object { [string] $_.Text }) } else { [string] $case.Text })
        # What the bench expects of the last turn, said the way the message bench judges it (none for the acts: only the
        # act is known there, and noise must still never make an action)
        $expect = $null
        if ($case.PSObject.Properties['Turns'] -and $case.Turns[-1].PSObject.Properties['Expect']) { $expect = $case.Turns[-1].Expect }
        elseif ($case.PSObject.Properties['Expect']) { $expect = $case.Expect }
        elseif ($case.PSObject.Properties['Expected'] -and $case.Expected.Status -eq 'Ready') { $expect = [pscustomobject]@{ Reply = 'action'; Action = $case.Expected.Action } }
        $cases.Add([pscustomobject]@{ Bench = $name; Id = [string] $case.Id; Language = $language; Turns = $turns; Expect = $expect })
    }
}

$report = & (Get-Module Lambek) {
    param($Cases, $Seed, $Budget, $Show)

    $templates = Get-LambekReplyTemplate
    # A reply that holds back anywhere in it ("dans ce monde imagine : ... je ne pourrais pas le conclure"), not only at
    # its start: the patterns of the replies that hold back, unanchored, when they say more than what is filled in
    $holding = @($templates | Where-Object { $_.Kind -in 'NotUnderstood', 'Abstained', 'Asked' } | ForEach-Object { $_.Pattern.ToString().Substring(1) } |
            Where-Object { ($_ -replace '\.\*|\\', '').Length -ge 20 } | Sort-Object -Unique | ForEach-Object { [regex]::new($_, 'Singleline') })
    # A reply that only notes what was said ("c'est note. ...", "vous m'avez dit : ..."): it claims nothing of its own
    $noting = [System.Collections.Generic.List[regex]]::new()
    foreach ($file in Get-ChildItem -Path (Join-Path (Get-Module Lambek).ModuleBase 'Data/Languages') -Filter '*.json' | Sort-Object Name) {
        $data = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        foreach ($key in 'Noted', 'NotedHere', 'Quoted') {
            $text = $(if ($data['Dialogue'] -and $data['Dialogue']['Say']) { $data['Dialogue']['Say'][$key] })
            if ($text -isnot [string]) { continue }
            $forms = @($text)
            if ($file.BaseName -eq 'fr') { $forms += [LambekSpeech]::Familiar($text, (Get-LambekDictionary -Language 'fr')) }
            foreach ($form in @($forms | Select-Object -Unique)) {
                $noting.Add([regex]::new('^' + ([regex]::Escape((ConvertTo-LambekBenchText -Text $form)) -replace '\\\{\d+(:[^}]*)?\}', '.*'), 'Singleline'))
            }
        }
    }
    $now = [datetime]::Parse('2026-10-19T12:00:00', [Globalization.CultureInfo]::InvariantCulture)
    $saved = @{
        Told = $script:Told; Board = $script:Board; Journal = $script:ToldJournal; Incognito = $script:Incognito; Pending = $script:CategoryPending
        Proofs = $script:LastProofs; Problems = $script:ProblemStores; Frames = $script:SpeechFrames; Capture = $script:SpeechCapture
        Host = $script:HostState; Recent = $script:SpeechRecent; Turn = $script:SpeechTurn; Now = $script:Now; Said = $script:SpeechSaid
    }

    # One conversation, alone (nothing told before is in it, nothing of it is written down): the decision on its last turn
    $decide = {
        param([string[]] $Turns, [string] $Language, [string] $Chat)
        $script:Told = $null; $script:Board = $null; $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
        $script:CategoryPending = $null; $script:LastProofs = $null; $script:ProblemStores = $null; $script:SpeechFrames = $null
        $script:SpeechCapture = $null; $script:SpeechRecent = @{}; $script:SpeechTurn = 0; $script:Now = $now
        $script:HostState = @{ Plans = [ordered]@{}; Simulations = @{}; Approvals = @{} }
        $result = $null
        $index = 0
        foreach ($text in $Turns) {
            $index++
            $line = ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $index; method = 'ask'; params = [ordered]@{ text = $text; chat = $Chat; incognito = $true; language = $Language } })
            $response = Invoke-LambekHostRequest -Line $line -AuditPath (Join-Path ([IO.Path]::GetTempPath()) "lambek-fragility-$PID.jsonl") | ConvertFrom-Json -AsHashtable
            $result = $(if ($response.ContainsKey('error') -and $response.error) { $null } else { $response.result })
        }
        if (-not $result) { return [pscustomobject]@{ Class = 'Error'; Actions = ''; Reply = ''; Status = 'Error'; Acted = @(); Kind = 'Empty' } }
        $actions = @($result['steps'] | Where-Object { $_ -and $_['action'] } | ForEach-Object { [string] $_['action'] }) -join ','
        $reply = [string] $result['answer']
        if (-not $reply) { $reply = (@($result['questions']) + @($result['steps'] | ForEach-Object { if ($_) { $_['questions'] } }) | Where-Object { $_ }) -join "`n" }
        $kind = Get-LambekReplyKind -Text $reply -Templates $templates
        $plain = ConvertTo-LambekBenchText -Text $reply
        if ($kind -eq 'Said' -and @($holding | Where-Object { $_.IsMatch($plain) }).Count -gt 0) { $kind = 'Abstained' }
        # Four kinds of decision: an action ready to run, an answer said, what was said only noted, or holding back
        $class = 'Held'
        if ([string] $result['status'] -eq 'Ready' -and $actions) { $class = "Act:$actions" }
        elseif ($kind -eq 'Said' -and -not $actions) { $class = $(if (@($noting | Where-Object { $_.IsMatch($plain) }).Count -gt 0) { 'Noted' } else { 'Said' }) }
        return [pscustomobject]@{ Class = $class; Actions = $actions; Reply = $plain; Status = [string] $result['status']; Acted = @($actions -split ',' | Where-Object { $_ }); Kind = $kind }
    }

    # Right, wrong, or not answered, as the message bench judges a turn (nothing to judge without an expectation)
    $judge = {
        param($Expect, $Decision)
        if (-not $Expect) { return $null }
        return Get-LambekMessageOutcome -Expect $Expect -Turn ([pscustomobject]@{ Status = $Decision.Status; Actions = $Decision.Acted; Reply = $Decision.Reply; Kind = $Decision.Kind })
    }

    # The slips, the same for every script: a letter left out, doubled, swapped with the next, or a key next to it
    $neighbors = Get-LambekKeyNeighbor
    $near = @{}
    foreach ($pair in $neighbors) {
        $from = [string] $pair[0]
        if (-not $near.ContainsKey($from)) { $near[$from] = [System.Collections.Generic.List[string]]::new() }
        $near[$from].Add([string] $pair[1])
    }
    foreach ($key in @($near.Keys)) { $near[$key] = @($near[$key] | Sort-Object) }
    $random = [Random]::new($Seed)
    $slip = {
        param([string] $Word)
        $ways = @('drop', 'double', 'swap')
        $keyed = @(0..($Word.Length - 1) | Where-Object { $near.ContainsKey([string] [char]::ToLowerInvariant($Word[$_])) })
        if ($keyed.Count -gt 0) { $ways += 'key' }
        $way = $ways[$random.Next($ways.Count)]
        # (never the first letter: a slip there is rarer, and a capital tells a name)
        $at = 1 + $random.Next($Word.Length - 1)
        switch ($way) {
            'drop' { return [pscustomobject]@{ Way = $way; Word = $Word.Remove($at, 1) } }
            'double' { return [pscustomobject]@{ Way = $way; Word = $Word.Insert($at, [string] $Word[$at]) } }
            'swap' {
                if ($at -ge $Word.Length - 1) { $at = $Word.Length - 2 }
                if ($at -lt 1 -or $Word[$at] -eq $Word[$at + 1]) { return [pscustomobject]@{ Way = 'drop'; Word = $Word.Remove($Word.Length - 1, 1) } }
                return [pscustomobject]@{ Way = $way; Word = $Word.Substring(0, $at) + $Word[$at + 1] + $Word[$at] + $Word.Substring($at + 2) }
            }
            'key' {
                $at = @($keyed | Where-Object { $_ -ge 1 })
                $at = $(if ($at.Count -gt 0) { $at[$random.Next($at.Count)] } else { $keyed[0] })
                $letter = [string] [char]::ToLowerInvariant($Word[$at])
                $other = $near[$letter][$random.Next($near[$letter].Count)]
                if ([char]::IsUpper($Word[$at])) { $other = $other.ToUpperInvariant() }
                return [pscustomobject]@{ Way = $way; Word = $Word.Substring(0, $at) + $other + $Word.Substring($at + 1) }
            }
        }
    }

    # Bits of a sentence in the language model of its language (none for a language without one)
    $bits = {
        param([string] $Text, [string] $Language)
        $model = Get-LambekFluency -Language $Language
        if (-not $model) { return [double]::NaN }
        return - $model.Score($Text, (Get-LambekDictionary -Language $Language))[0] * [math]::Log(10, 2)
    }

    # The words that carry the decision first: those the language model keeps least (a rare word, a name), then the longest
    $words = {
        param([string] $Text, [string] $Language)
        $model = Get-LambekFluency -Language $Language
        $found = @([regex]::Matches($Text, '(?<![\\/.:\w"''])\p{L}{4,}(?![\\/.:\w"''])'))
        # (nothing inside quotes: what is quoted is said as it is)
        $quoted = @([regex]::Matches($Text, '"[^"]*"|' + [char] 0x00AB + '[^' + [char] 0x00BB + ']*' + [char] 0x00BB))
        $found = @($found | Where-Object { $m = $_; @($quoted | Where-Object { $m.Index -ge $_.Index -and $m.Index -lt $_.Index + $_.Length }).Count -eq 0 })
        return @($found | Sort-Object @{ Expression = { if ($model -and $model.Knows($_.Value.ToLowerInvariant())) { 1 } else { 0 } } }, @{ Expression = { $_.Value.Length }; Descending = $true }, @{ Expression = { $_.Index } })
    }

    # A word of another sort: the noun that carries the decision, replaced by the noun of the other sentences of the same
    # language the furthest from it in the hierarchy of meanings (Wu-Palmer on WordNet): "quelle est la capitale du
    # Portugal ?" becomes "quelle est la capitale du fichier ?". No list is written for it: the nouns come from the benches
    $noun = {
        param([string] $Word, [string] $Language)
        $dictionary = Get-LambekDictionary -Language $Language
        foreach ($lemma in @($dictionary.Lemmas($Word, $Language) | Where-Object Pos -EQ 'n')) {
            $senses = @($dictionary.Senses($lemma.Lemma, $Language, 'n'))
            if ($senses.Count -gt 0) { return [pscustomobject]@{ Lemma = $lemma.Lemma; Tag = $lemma.Tag; Sense = $senses[0] } }
        }
        return $null
    }
    $pool = @{}
    foreach ($case in $Cases) {
        if (-not $pool.ContainsKey($case.Language)) { $pool[$case.Language] = [ordered]@{} }
        foreach ($turn in $case.Turns) {
            $reading = Get-LambekSentenceReading -Text $turn -Language $case.Language
            if (-not $reading -or -not $reading.PSObject.Properties['Readings']) { continue }
            foreach ($form in @($reading.Readings | Where-Object { $_ -and $_.Upos -eq 'NOUN' -and $_.Form.Length -ge 3 } | ForEach-Object Form)) {
                $found = & $noun $form $case.Language
                if ($found -and -not $pool[$case.Language].Contains($found.Lemma)) { $pool[$case.Language][$found.Lemma] = $found }
            }
        }
    }
    $foreign = {
        param([string] $Text, [string] $Language, [object[]] $Words)
        $dictionary = Get-LambekDictionary -Language $Language
        # (a noun in this very sentence, as the forms model reads it: "comment" in "comment ca va" is none)
        $reading = Get-LambekSentenceReading -Text $Text -Language $Language
        if (-not $reading -or -not $reading.PSObject.Properties['Readings']) { return $null }
        $nouns = @($reading.Readings | Where-Object { $_ -and $_.Upos -in 'NOUN', 'PROPN' } | ForEach-Object { $_.Form.ToLowerInvariant() })
        foreach ($word in @($Words | Where-Object { $_.Value.ToLowerInvariant() -in $nouns })) {
            $own = & $noun $word.Value $Language
            if (-not $own) { continue }
            $far = @($pool[$Language].Values | Where-Object Lemma -NE $own.Lemma | Sort-Object @{ Expression = { $dictionary.WuPalmer($own.Sense, $_.Sense) } }, Lemma | Select-Object -First 1)
            if ($far.Count -eq 0) { continue }
            $form = @($dictionary.Forms($far[0].Lemma, $Language, 'n', $own.Tag) | Select-Object -First 1)
            $other = $(if ($form.Count -gt 0 -and $form[0]) { $form[0] } else { $far[0].Lemma })
            if ([char]::IsUpper($word.Value[0])) { $other = $other.Substring(0, 1).ToUpperInvariant() + $other.Substring(1) }
            if ($other -eq $word.Value) { continue }
            return [pscustomobject]@{ Word = $word.Value; Other = $other; Text = $Text.Substring(0, $word.Index) + $other + $Text.Substring($word.Index + $word.Length) }
        }
        return $null
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $number = 0
    foreach ($case in $Cases) {
        $number++
        $clean = & $decide $case.Turns $case.Language "fragility-$number"
        $cleanOutcome = & $judge $case.Expect $clean
        $last = $case.Turns[-1]
        $before = @($case.Turns | Select-Object -SkipLast 1)
        $cleanBits = & $bits $last $case.Language
        $tried = [System.Collections.Generic.List[object]]::new()
        $candidates = @(& $words $last $case.Language)
        for ($k = 0; $k -lt $Budget -and $candidates.Count -gt 0; $k++) {
            $word = $candidates[$k % $candidates.Count]
            $changed = & $slip $word.Value
            if ($changed.Word -ceq $word.Value) { continue }
            $text = $last.Substring(0, $word.Index) + $changed.Word + $last.Substring($word.Index + $word.Length)
            $number++
            $got = & $decide (@($before) + @($text)) $case.Language "fragility-$number"
            # The same answer, but for the word as it was typed said back ("je ne connais pas Portigal")
            $reply = $got.Reply
            $typed = ConvertTo-LambekBenchText -Text $changed.Word
            if ($typed) { $reply = [regex]::Replace($reply, '(?<!\w)' + [regex]::Escape($typed) + '(?!\w)', (ConvertTo-LambekBenchText -Text $word.Value)) }
            $outcome = & $judge $case.Expect $got
            # The same decision: the same kind, and for an answer the same words, or right both times by the bench
            $same = $got.Class -eq $clean.Class -and ($got.Class -ne 'Said' -or $reply -eq $clean.Reply -or ($cleanOutcome -eq 'Correct' -and $outcome -eq 'Correct'))
            # Unsafe: an action the clean sentence did not make, or an answer right without the slip and wrong with it
            $unsafe = ($got.Class -like 'Act:*' -and $got.Class -ne $clean.Class) -or ($got.Class -eq 'Said' -and $cleanOutcome -eq 'Correct' -and $outcome -eq 'Wrong')
            # What the slip costs: which slip of the word it is among all the slips of one letter it could have had (a
            # long word has more), and how much less likely the sentence became (a rare word is read by its kind in the
            # model, so a slip in it costs nothing more there)
            $count = 3 * ($word.Value.Length - 1)
            for ($i = 1; $i -lt $word.Value.Length; $i++) { $letter = [string] [char]::ToLowerInvariant($word.Value[$i]); if ($near.ContainsKey($letter)) { $count += $near[$letter].Count } }
            $likely = (& $bits $text $case.Language) - $cleanBits
            $cost = [math]::Log([math]::Max($count, 2), 2) + $(if ([double]::IsNaN($likely)) { 0 } else { [math]::Max(0, $likely) })
            $tried.Add([pscustomobject]@{ Text = $text; Way = $changed.Way; Word = $word.Value; Bits = $cost; Same = $same; Unsafe = $unsafe; Got = $got.Class; Reply = $got.Reply })
            if ($Show -and -not $same) { Write-Host "  [$($case.Bench) $($case.Id)] $text -> $($got.Class) $($got.Reply) (clean: $($clean.Class) $($clean.Reply))" }
        }
        # The word of another sort: an action, or the very answer the clean sentence got, means the word was not read
        $ignored = $null
        $swapped = & $foreign $last $case.Language $candidates
        if ($swapped) {
            $number++
            $got = & $decide (@($before) + @($swapped.Text)) $case.Language "fragility-$number"
            $kept = ($got.Class -like 'Act:*') -or ($got.Class -eq 'Said' -and $clean.Class -eq 'Said' -and $got.Reply -eq $clean.Reply)
            $ignored = [pscustomobject]@{ Text = $swapped.Text; Word = $swapped.Word; Other = $swapped.Other; Got = $got.Class; Reply = $got.Reply; Ignored = $kept }
            if ($Show -and $kept) { Write-Host "  [$($case.Bench) $($case.Id) other sort] $($swapped.Text) -> $($got.Class) $($got.Reply)" }
        }
        $changes = @($tried | Where-Object { -not $_.Same })
        $rows.Add([pscustomobject]@{
                Bench    = $case.Bench
                Id       = $case.Id
                Language = $case.Language
                Clean    = $clean.Class
                Tried    = $tried.Count
                Fragile  = $changes.Count -gt 0
                # The cheapest slip that changed the decision; for a sentence none changed, the dearest slip it stood
                Edge     = $(if ($changes.Count) { ($changes | Measure-Object -Property Bits -Minimum).Minimum } else { $null })
                Stood    = $(if ($tried.Count -and -not $changes.Count) { ($tried | Measure-Object -Property Bits -Maximum).Maximum } else { $null })
                Slips    = $tried.ToArray()
                Foreign  = $ignored
            })
    }

    # The choice of an action, exactly: the score of an action is linear in the weights of its scorers, its best example
    # kept (Select-LambekIntent); found means above the threshold and ahead of the next action by the margin of its risk
    $scoring = Get-LambekScoring
    $names = 'Grammar', 'Cosine', 'WordJaccard', 'NGramJaccard', 'Edit'
    $w = [double[]] @($names | ForEach-Object { $scoring.Weights[$_] })
    $dot = { param($a, $b) $s = 0.0; for ($k = 0; $k -lt $a.Count; $k++) { $s += $a[$k] * $b[$k] }; $s }
    # (a change of weights that keeps their sum: only the part of a gradient across the simplex counts)
    $across = { param($v) $mean = ($v | Measure-Object -Sum).Sum / $v.Count; [double[]] @($v | ForEach-Object { $_ - $mean }) }
    $weights = [System.Collections.Generic.List[object]]::new()
    foreach ($case in @($Cases | Where-Object Bench -EQ 'requests')) {
        $request = ConvertTo-LambekRequest -Text $case.Turns[-1] -Language $case.Language
        $evidence = Get-LambekIntentEvidence -Request $request
        $selection = Select-LambekIntent -Evidence $evidence -Scoring $scoring
        if ($selection.Status -ne 'Found') { continue }
        $features = foreach ($ranked in @($selection.Ranked | Select-Object -First 2)) {
            $candidate = @($evidence.Candidates | Where-Object { $_.Action.Id -eq $ranked.Action.Id })[0]
            $best = $null
            $top = [double]::NegativeInfinity
            foreach ($example in $candidate.Examples) {
                $text = $w[1] * $example.Cosine + $w[2] * $example.WordJaccard + $w[3] * $example.NGramJaccard + $w[4] * $example.EditSimilarity
                if ($text -gt $top) { $top = $text; $best = $example }
            }
            , [double[]] @($candidate.GrammarScore, $best.Cosine, $best.WordJaccard, $best.NGramJaccard, $best.EditSimilarity)
        }
        $features = @($features)
        $risk = $selection.Best.Action.Risk
        $margin = $scoring.Margin
        if ($scoring.Margins -and $scoring.Margins.ContainsKey($risk)) { $margin = $scoring.Margins[$risk] }
        # Two planes: the threshold (the score of the action falls under it) and the margin (the next action comes too close)
        $edges = [System.Collections.Generic.List[object]]::new()
        $gradient = & $across $features[0]
        $length = [math]::Sqrt((& $dot $gradient $gradient))
        if ($length -gt 1e-12) { $edges.Add([pscustomobject]@{ Plane = 'threshold'; Distance = ((& $dot $w $features[0]) - $scoring.Threshold) / $length; Gradient = $gradient; Length = $length }) }
        if ($features.Count -gt 1) {
            $difference = [double[]] @(0..4 | ForEach-Object { $features[0][$_] - $features[1][$_] })
            $gradient = & $across $difference
            $length = [math]::Sqrt((& $dot $gradient $gradient))
            if ($length -gt 1e-12) { $edges.Add([pscustomobject]@{ Plane = 'margin'; Distance = ((& $dot $w $difference) - $margin) / $length; Gradient = $gradient; Length = $length }) }
        }
        if ($edges.Count -eq 0) { continue }
        $edge = @($edges | Sort-Object Distance)[0]
        # Checked: decide again with the weights moved just past the plane. Weights below 0 are no weights the scorers
        # can have: a request whose edge lies there does not turn with any weights
        $step = $edge.Distance * 1.001 + 1e-9
        $moved = [double[]] @(0..4 | ForEach-Object { $w[$_] - $step * $edge.Gradient[$_] / $edge.Length })
        $valid = @($moved | Where-Object { $_ -lt 0 }).Count -eq 0
        $other = [pscustomobject]@{}
        foreach ($property in $scoring.PSObject.Properties) { $other | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        $table = @{}
        for ($k = 0; $k -lt $names.Count; $k++) { $table[$names[$k]] = $moved[$k] }
        $other.Weights = $table
        $again = Select-LambekIntent -Evidence $evidence -Scoring $other
        $turned = $again.Status -ne 'Found' -or -not $again.Best -or $again.Best.Action.Id -ne $selection.Best.Action.Id
        $weights.Add([pscustomobject]@{
                Id       = $case.Id
                Action   = $selection.Best.Action.Id
                Plane    = $edge.Plane
                Distance = $edge.Distance
                Relative = $edge.Distance / [math]::Sqrt((& $dot $w $w))
                Valid    = $valid
                Checked  = $turned
                Then     = "$($again.Status) $(if ($again.Best) { $again.Best.Action.Id })"
            })
    }

    $script:Told = $saved.Told; $script:Board = $saved.Board; $script:ToldJournal = $saved.Journal; $script:Incognito = $saved.Incognito
    $script:CategoryPending = $saved.Pending; $script:LastProofs = $saved.Proofs; $script:ProblemStores = $saved.Problems
    $script:SpeechFrames = $saved.Frames; $script:SpeechCapture = $saved.Capture; $script:HostState = $saved.Host
    $script:SpeechRecent = $saved.Recent; $script:SpeechTurn = $saved.Turn; $script:Now = $saved.Now; $script:SpeechSaid = $saved.Said
    [pscustomobject]@{ Rows = $rows.ToArray(); Weights = $weights.ToArray() }
} $cases $Seed $Budget $Show

# What one slip did, bench by bench
$median = {
    param([double[]] $Values)
    $sorted = @($Values | Where-Object { -not [double]::IsNaN($_) } | Sort-Object)
    if ($sorted.Count -eq 0) { return '-' }
    return [math]::Round($sorted[[int][math]::Floor(($sorted.Count - 1) / 2)], 1)
}
Write-Host ('{0,-10} {1,10} {2,8} {3,9} {4,10} {5,10} {6,7} {7,10} {8,8}' -f 'Bench', 'Sentences', 'Fragile', 'Rate', 'EdgeBits', 'StoodBits', 'Unsafe', 'OtherSort', 'Ignored')
$all = @($report.Rows)
$groups = @($all | Group-Object Bench | ForEach-Object { , @($_.Group) })
if ($groups.Count -gt 1) { $groups += , $all }
foreach ($group in $groups) {
    $name = $(if ($group.Count -eq $all.Count -and @($group | Select-Object -ExpandProperty Bench -Unique).Count -gt 1) { 'all' } else { $group[0].Bench })
    $fragile = @($group | Where-Object Fragile).Count
    $unsafe = @($group | ForEach-Object { $_.Slips } | Where-Object Unsafe).Count
    $rate = $(if ($group.Count) { [math]::Round($fragile / $group.Count, 3) } else { 0 })
    $edge = & $median ([double[]] @($group | Where-Object Fragile | ForEach-Object Edge))
    $stood = & $median ([double[]] @($group | Where-Object { $null -ne $_.Stood } | ForEach-Object Stood))
    $other = @($group | Where-Object { $_.Foreign })
    Write-Host ('{0,-10} {1,10} {2,8} {3,9} {4,10} {5,10} {6,7} {7,10} {8,8}' -f $name, $group.Count, $fragile, $rate, $edge, $stood, $unsafe, $other.Count, @($other | Where-Object { $_.Foreign.Ignored }).Count)
}

# Effective information of the channel (Hoel): the kind of decision each clean sentence got is what was meant; every slip
# is an intervention. EI = H(the mean row) - the mean H(row), each kind meant weighing the same
$entropy = { param($counts) $n = ($counts.Values | Measure-Object -Sum).Sum; $h = 0.0; foreach ($c in $counts.Values) { if ($c -gt 0) { $p = $c / $n; $h -= $p * [math]::Log($p, 2) } }; $h }
$kinds = @($all | ForEach-Object Clean | Sort-Object -Unique)
$outputs = @(@($kinds) + @($all | ForEach-Object { $_.Slips } | ForEach-Object Got) | Sort-Object -Unique)
$mean = @{}
foreach ($o in $outputs) { $mean[$o] = 0.0 }
$spread = 0.0
foreach ($kind in $kinds) {
    $counts = @{}
    foreach ($o in $outputs) { $counts[$o] = 0 }
    foreach ($row in @($all | Where-Object Clean -EQ $kind)) { foreach ($s in $row.Slips) { $counts[$s.Got]++ } }
    $n = ($counts.Values | Measure-Object -Sum).Sum
    if ($n -eq 0) { $counts[$kind] = 1; $n = 1 }
    foreach ($o in $outputs) { $mean[$o] += $counts[$o] / $n / $kinds.Count }
    $spread += (& $entropy $counts) / $kinds.Count
}
$size = [math]::Log([math]::Max($kinds.Count, 1), 2)
$information = (& $entropy $mean) - $spread
Write-Host ''
Write-Host ("Effective information {0} bits of {1} (determinism {2}, degeneracy {3}), over {4} kinds of decision" -f [math]::Round($information, 3), [math]::Round($size, 3), [math]::Round($size - $spread, 3), [math]::Round($size - (& $entropy $mean), 3), $kinds.Count)

# The choice of an action: how far the weights must move before a request found is asked about
$weights = @($report.Weights)
if ($weights.Count -gt 0) {
    $valid = @($weights | Where-Object Valid)
    $relative = @($valid | ForEach-Object Relative | Sort-Object)
    $low = $(if ($relative.Count) { [math]::Round($relative[0], 3) } else { '-' })
    $middle = $(if ($relative.Count) { [math]::Round($relative[[int][math]::Floor(($relative.Count - 1) / 2)], 3) } else { '-' })
    Write-Host ("Choice of an action: {0} requests found; {1} turn with valid weights (checked {2}), the nearest at {3} of the weights, the median at {4}; {5} turn with no valid weights" -f $weights.Count, $valid.Count, @($valid | Where-Object Checked).Count, $low, $middle, ($weights.Count - $valid.Count))
    if ($Show) {
        foreach ($near in @($valid | Sort-Object Relative | Select-Object -First 5)) { Write-Host ("  {0} {1}: {2} plane at {3} -> {4}" -f $near.Id, $near.Action, $near.Plane, [math]::Round($near.Relative, 3), $near.Then) }
    }
}

$unsafe = @($all | ForEach-Object { $s = $_; @($s.Slips | Where-Object Unsafe | ForEach-Object { "$($s.Bench) $($s.Id): $($_.Text) -> $($_.Got) $($_.Reply)" }) })
foreach ($line in $unsafe) { Write-Host "  unsafe: $line" }
# (a run where a slip made an action or another answer fails: build.ps1 stops on it)
if ($unsafe.Count -gt 0) { exit 1 }
