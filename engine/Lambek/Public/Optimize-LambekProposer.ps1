function Optimize-LambekProposer {
    <#
    .SYNOPSIS
        Trains the optional proposer (a very small transformer) on the examples of the loaded packs and writes it.
        The proposer never decides: it only suggests an example sentence when Lambek did not understand a request.
    .EXAMPLE
        Optimize-LambekProposer -Path ./bench/requests.json -OutFile ./engine/Lambek/Data/proposer.json
    #>
    [CmdletBinding()]
    param(
        # The benchmark: two thirds of its calibration split are learned, one third is held out for the threshold.
        # Its test split is never read here
        [string] $Path,

        [string] $OutFile,

        # How many variations of each example sentence are made
        [ValidateRange(1, 200)]
        [int] $Variations = 8,

        [ValidateRange(1, 500)]
        [int] $Epochs = 8,

        [ValidateRange(8, 256)]
        [int] $Dimension = 32,

        [ValidateRange(1, 4)]
        [int] $Layers = 1,

        [uint64] $Seed = 20260,

        # A proposal must be right this often on the held-out requests
        [ValidateRange(0.5, 1.0)]
        [double] $Precision = 0.9
    )

    if ($script:Packs.Count -eq 0) { throw 'No pack is loaded: the proposer learns from the examples of the packs.' }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::GetCurrentProcess()
    $processorStart = $process.TotalProcessorTime.TotalSeconds
    $random = [LambekXorShift]::new($Seed)

    # The classes: every action of the packs, then "none"
    $actions = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($pack in $script:Packs.Values) { foreach ($action in $pack.Actions) { [void] $actions.Add($action.Id) } }
    $classes = [string[]] (@($actions) + @('none'))
    $model = [LambekTransformer]::Create(4096, $Dimension, 4, $Layers, 2 * $Dimension, 32, $classes, $Seed, 0.0)

    # What is learned: the sentences of the packs, then the requests of the benchmark that are not held out
    $seeds = [System.Collections.Generic.List[object]]::new()
    foreach ($source in Get-LambekProposerSeed) { $seeds.Add($source) }
    $heldOut = [System.Collections.Generic.List[object]]::new()
    if ($Path) {
        $number = 0
        foreach ($case in Get-LambekBenchmarkCase -Path $Path -Split 'calibration') {
            $label = Get-LambekProposerLabel -Case $case -Classes $classes
            if (-not $label) { continue }
            $entry = [pscustomobject]@{ Words = [LambekTransformerText]::Words($case.Text); Label = $label; Language = [string] $case.Language; Verbs = @() }
            if ($number % 3 -eq 2) { $heldOut.Add($entry) } else { $seeds.Add($entry) }
            $number++
        }
    }

    # Each sentence as it is, then its variations
    $forms = @{}
    foreach ($language in Get-LambekAvailableLanguage) { $forms[$language] = Get-LambekProposerForm -Language $language }
    $foreign = Get-LambekProposerForeignWord -Seeds $seeds
    $samples = [System.Collections.Generic.List[object]]::new()
    foreach ($source in $seeds) {
        $samples.Add([pscustomobject]@{ Words = [string[]] $source.Words; Label = $source.Label })
        $own = $null
        if ($forms.ContainsKey($source.Language)) { $own = $forms[$source.Language] }
        $others = [string[]] @()
        if ($foreign.ContainsKey($source.Label)) { $others = $foreign[$source.Label] }
        for ($k = 0; $k -lt $Variations; $k++) {
            $samples.Add([pscustomobject]@{ Words = [LambekTransformerText]::Vary([string[]] $source.Words, $random, $own, $others); Label = $source.Label })
        }
    }
    $positive = $samples.Count

    # Sentences that ask for nothing Lambek does
    foreach ($sample in Get-LambekProposerNone -Seeds $seeds -Random $random -Count ([int] ($positive * 0.3)) -Variations $Variations) { $samples.Add($sample) }

    # A fixed, shuffled order; then the training itself
    $order = [LambekTransformerText]::Shuffle($samples.Count, $random)
    $inputs = [int[][][]]::new($samples.Count)
    $labels = [int[]]::new($samples.Count)
    for ($i = 0; $i -lt $order.Length; $i++) {
        $sample = $samples[$order[$i]]
        $inputs[$i] = $model.EncodeWords([string[]] $sample.Words)
        $labels[$i] = $model.ClassIndex($sample.Label)
    }
    $prepared = $clock.Elapsed.TotalSeconds
    $process.Refresh()
    $processorPrepared = $process.TotalProcessorTime.TotalSeconds
    $losses = $model.Fit($inputs, $labels, $Epochs, 32, 0.003, $null)
    $trained = $clock.Elapsed.TotalSeconds - $prepared
    $process.Refresh()
    $processorTrained = $process.TotalProcessorTime.TotalSeconds

    # Held out: the third of the benchmark kept aside, each request as typed and with typing mistakes.
    # Without a benchmark: new variations of the sentences of the packs (a weaker check, they look like the training)
    $checks = [System.Collections.Generic.List[object]]::new()
    $checkRandom = [LambekXorShift]::new($Seed + 1)
    if ($heldOut.Count -gt 0) {
        foreach ($entry in $heldOut) {
            $checks.Add($entry)
            for ($k = 0; $k -lt 2; $k++) {
                $words = [string[]] $entry.Words.Clone()
                for ($mistake = 0; $mistake -le $k; $mistake++) {
                    $at = $checkRandom.NextInt($words.Length)
                    $words[$at] = [LambekTransformerText]::Misspell($words[$at], $checkRandom)
                }
                $checks.Add([pscustomobject]@{ Words = $words; Label = $entry.Label })
            }
        }
    }
    else {
        foreach ($source in $seeds) {
            $checks.Add([pscustomobject]@{ Words = [LambekTransformerText]::Vary([string[]] $source.Words, $checkRandom, $null, [string[]] @()); Label = $source.Label })
        }
        foreach ($sample in Get-LambekProposerNone -Seeds $seeds -Random $checkRandom -Count ([int] ($seeds.Count * 0.3)) -Variations 1) { $checks.Add($sample) }
    }

    # The threshold: the lowest one at which a proposal is right often enough
    $measure = Measure-LambekProposer -Model $model -Checks $checks.ToArray()
    $model.Threshold = [LambekTransformer]::Calibrate($measure.Confidence, $measure.Right, $Precision)
    $kept = Measure-LambekProposer -Model $model -Checks $checks.ToArray()

    # What the file says about itself (no date: the same data gives the same file)
    $model.Notes['Samples'] = "$($samples.Count)"
    $model.Notes['Seeds'] = "$($seeds.Count)"
    $model.Notes['HeldOut'] = "$($checks.Count)"
    $model.Notes['HeldOutSource'] = $(if ($heldOut.Count -gt 0) { 'benchmark' } else { 'variations' })
    $model.Notes['HeldOutPrecision'] = $kept.Precision.ToString('0.0000', [cultureinfo]::InvariantCulture)
    $model.Notes['HeldOutProposed'] = "$($kept.Proposed)"
    $model.Notes['Epochs'] = "$Epochs"
    $model.Notes['Variations'] = "$Variations"
    if ($OutFile) { [System.IO.File]::WriteAllText($OutFile, $model.Save(), [System.Text.UTF8Encoding]::new($false)) }

    [pscustomobject]@{
        PSTypeName       = 'Lambek.Proposer'
        Classes          = $classes
        Seeds            = $seeds.Count
        Samples          = $samples.Count
        Loss             = [math]::Round($losses[$losses.Length - 1], 4)
        HeldOut          = $checks.Count
        HeldOutTop1      = $kept.Top1
        HeldOutTop3      = $kept.Top3
        Threshold        = [math]::Round($model.Threshold, 4)
        HeldOutProposed  = $kept.Proposed
        HeldOutPrecision = $kept.Precision
        PrepareSeconds   = [math]::Round($prepared, 1)
        TrainSeconds     = [math]::Round($trained, 1)
        # Processor time: what the work costs when the machine does nothing else
        PrepareProcessor = [math]::Round($processorPrepared - $processorStart, 1)
        TrainProcessor   = [math]::Round($processorTrained - $processorPrepared, 1)
        Model            = $model
    }
}

function Get-LambekProposerLabel {
    param([hashtable] $Case, [string[]] $Classes)

    # A request with a known action teaches that action; one Lambek must not understand teaches "none".
    # A request answered by a question has no known action and teaches nothing
    $status = [string] $Case.Expected.Status
    if ($status -eq 'Unknown') { return 'none' }
    if ($status -eq 'Ready' -and $Case.Expected.ContainsKey('Action') -and $Case.Expected.Action -in $Classes) { return [string] $Case.Expected.Action }
    return $null
}

function Get-LambekProposerSeed {
    # The sentences of the packs in every language: the examples of each action, its title, and each verb only it has
    $owners = @{}
    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            foreach ($verb in @($action.Verbs)) {
                if (-not $owners.ContainsKey($verb)) { $owners[$verb] = @() }
                $owners[$verb] = @($owners[$verb]) + @($action.Id)
            }
        }
    }
    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            foreach ($language in @($action.Examples.Keys | Sort-Object)) {
                $lexicon = $null
                if ($language -in (Get-LambekAvailableLanguage)) { $lexicon = Get-LambekLexicon -Language $language }
                foreach ($example in @($action.Examples[$language])) {
                    $words = [LambekTransformerText]::Words($example)
                    # The words of the sentence that say the action (a verb of the action, or a form of one)
                    $verbs = @(foreach ($word in $words) {
                            $base = $word
                            if ($lexicon -and $lexicon.BaseForms.ContainsKey($word)) { $base = $lexicon.BaseForms[$word] }
                            if ($word -in $action.Verbs -or $base -in $action.Verbs) { $word }
                        })
                    [pscustomobject]@{ Words = $words; Label = $action.Id; Language = $language; Verbs = $verbs }
                }
                if ($action.Title -is [System.Collections.IDictionary] -and $action.Title.Contains($language)) {
                    [pscustomobject]@{ Words = [LambekTransformerText]::Words($action.Title[$language]); Label = $action.Id; Language = $language; Verbs = @() }
                }
                if ($pack.Words.ContainsKey($language)) {
                    foreach ($verb in @($action.Verbs)) {
                        if ($pack.Words[$language].ContainsKey($verb) -and @($owners[$verb]).Count -eq 1) {
                            [pscustomobject]@{ Words = [string[]] @($verb); Label = $action.Id; Language = $language; Verbs = @() }
                        }
                    }
                }
            }
        }
    }
}

function Get-LambekProposerForm {
    param([string] $Language)

    # For each word, the other forms of the same base ("delete", "deleting", "remove"...), from the language and the packs
    $groups = @{}
    $baseForms = (Get-LambekLexicon -Language $Language).BaseForms
    foreach ($form in @($baseForms.Keys | Sort-Object)) {
        $base = [string] $baseForms[$form]
        if ($form -notmatch '^[a-z]+$' -or $base -notmatch '^[a-z]+$') { continue }
        if (-not $groups.ContainsKey($base)) { $groups[$base] = [System.Collections.Generic.List[string]]::new(); $groups[$base].Add($base) }
        if (-not $groups[$base].Contains($form)) { $groups[$base].Add($form) }
    }
    $forms = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::Ordinal)
    foreach ($base in @($groups.Keys | Sort-Object)) {
        $members = [string[]] $groups[$base].ToArray()
        foreach ($member in $members) { $forms[$member] = $members }
    }
    return $forms
}

function Get-LambekProposerForeignWord {
    param([System.Collections.Generic.List[object]] $Seeds)

    # For each action, the words its sentences use in all the languages: one of them is sometimes mixed in
    $words = @{}
    foreach ($seed in $Seeds) {
        if ($seed.Label -eq 'none') { continue }
        if (-not $words.ContainsKey($seed.Label)) { $words[$seed.Label] = [System.Collections.Generic.List[string]]::new() }
        foreach ($word in $seed.Words) {
            if ($word -notlike '<*' -and -not $words[$seed.Label].Contains($word)) { $words[$seed.Label].Add($word) }
        }
    }
    $result = @{}
    foreach ($label in $words.Keys) { $result[$label] = [string[]] $words[$label].ToArray() }
    return $result
}

function Get-LambekProposerNone {
    param(
        [System.Collections.Generic.List[object]] $Seeds,
        [LambekXorShift] $Random,
        [int] $Count,
        [int] $Variations
    )

    $languages = @(Get-LambekAvailableLanguage)
    $placeholders = [string[]] @('<path>', '<path>', '<ext>', '<num>', '<file>', '<quoted>')
    foreach ($language in $languages) {
        $lexicon = Get-LambekLexicon -Language $language

        # Words that say nothing to Lambek: from the dictionary of the language, or random letters without it
        $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($word in $lexicon.BaseForms.Keys) { [void] $known.Add($word); [void] $known.Add([string] $lexicon.BaseForms[$word]) }
        foreach ($pack in $script:Packs.Values) {
            if ($pack.Words.ContainsKey($language)) { foreach ($word in $pack.Words[$language].Keys) { [void] $known.Add($word) } }
            foreach ($action in $pack.Actions) { foreach ($verb in @($action.Verbs)) { [void] $known.Add($verb) } }
        }
        $noise = [System.Collections.Generic.List[string]]::new()
        $dictionary = Join-Path $script:DictionaryPath "$language.dict.gz"
        if (Test-Path -LiteralPath $dictionary -PathType Leaf) {
            foreach ($word in [LambekTransformerText]::DictionaryWords($dictionary, 600)) { if (-not $known.Contains($word)) { $noise.Add($word) } }
        }
        if ($noise.Count -eq 0) {
            for ($n = 0; $n -lt 600; $n++) {
                $letters = [char[]]::new(3 + $Random.NextInt(7))
                for ($i = 0; $i -lt $letters.Length; $i++) { $letters[$i] = [char] (97 + $Random.NextInt(26)) }
                $noise.Add([string]::new($letters))
            }
        }
        $stopWords = [string[]] @($lexicon.StopWords | Sort-Object)

        # Small talk, sums, definitions, "again", "yes": Lambek answers them itself, they are no action
        $phrases = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $lexicon.Talk.Keys) { foreach ($phrase in $lexicon.Talk[$name].Phrases) { $phrases.Add(@($phrase) -join ' ') } }
        foreach ($phrase in @($lexicon.Again | Where-Object { $_ })) { $phrases.Add($phrase) }
        if ($lexicon.Define) { foreach ($phrase in @($lexicon.Define.Phrases)) { $phrases.Add("$phrase $($noise[$Random.NextInt($noise.Count)])") } }
        if ($lexicon.Calculate) { foreach ($phrase in @($lexicon.Calculate.Phrases)) { $phrases.Add("$phrase 3 + 4") } }
        foreach ($key in 'Run', 'Explain') { foreach ($word in @($lexicon.FollowUp[$key])) { $phrases.Add($word) } }
        foreach ($phrase in $phrases) {
            $words = [LambekTransformerText]::Words($phrase)
            [pscustomobject]@{ Words = $words; Label = 'none' }
            [pscustomobject]@{ Words = [LambekTransformerText]::Vary($words, $Random, $null, [string[]] @()); Label = 'none' }
        }

        # Sentences of words Lambek does not know, with some small words and sometimes a path or a number
        for ($n = 0; $n -lt [int] ($Count / $languages.Count); $n++) {
            $words = [System.Collections.Generic.List[string]]::new()
            $length = 1 + $Random.NextInt(5)
            for ($i = 0; $i -lt $length; $i++) {
                if ($stopWords.Length -gt 0 -and $Random.NextDouble() -lt 0.35) { $words.Add($stopWords[$Random.NextInt($stopWords.Length)]) }
                else { $words.Add($noise[$Random.NextInt($noise.Count)]) }
            }
            if ($Random.NextDouble() -lt 0.4) { $words.Insert($Random.NextInt($words.Count + 1), $placeholders[$Random.NextInt($placeholders.Length)]) }
            [pscustomobject]@{ Words = [string[]] $words.ToArray(); Label = 'none' }
        }

        # A sentence of a pack whose verb is a word Lambek does not know asks for nothing it knows
        foreach ($seed in $Seeds) {
            if ($seed.Language -ne $language -or @($seed.Verbs).Count -eq 0) { continue }
            for ($k = 0; $k -lt [math]::Max(1, [int] ($Variations / 8)); $k++) {
                $words = [string[]] @(foreach ($word in $seed.Words) { if ($word -in $seed.Verbs) { $noise[$Random.NextInt($noise.Count)] } else { $word } })
                [pscustomobject]@{ Words = [LambekTransformerText]::Vary($words, $Random, $null, [string[]] @()); Label = 'none' }
            }
        }
    }

    # The requests of the benchmark Lambek must not understand, with their variations
    foreach ($seed in $Seeds) {
        if ($seed.Label -ne 'none') { continue }
        for ($k = 0; $k -lt $Variations; $k++) {
            [pscustomobject]@{ Words = [LambekTransformerText]::Vary([string[]] $seed.Words, $Random, $null, [string[]] @()); Label = 'none' }
        }
    }
}

function Measure-LambekProposer {
    param([LambekTransformer] $Model, [object[]] $Checks)

    # For each request: the best class and its probability; a proposal is a best class that is an action,
    # at or over the threshold. It is right when it is the action the request means
    $confidence = [System.Collections.Generic.List[double]]::new()
    $right = [System.Collections.Generic.List[bool]]::new()
    $top1 = 0
    $top3 = 0
    $proposed = 0
    $proposedRight = 0
    $none = $Model.ClassIndex('none')
    foreach ($check in $Checks) {
        $probabilities = $Model.Forward($Model.EncodeWords([string[]] $check.Words), $null)
        $order = [LambekTransformer]::Rank($probabilities)
        $label = $Model.ClassIndex($check.Label)
        if ($order[0] -eq $label) { $top1++ }
        if ($label -in @($order[0..2])) { $top3++ }
        if ($order[0] -eq $none) { continue }
        $confidence.Add($probabilities[$order[0]])
        $right.Add($order[0] -eq $label)
        if ($probabilities[$order[0]] -ge $Model.Threshold) {
            $proposed++
            if ($order[0] -eq $label) { $proposedRight++ }
        }
    }
    $precision = 0.0
    if ($proposed -gt 0) { $precision = [math]::Round($proposedRight / $proposed, 4) }
    [pscustomobject]@{
        Total      = $Checks.Count
        Top1       = [math]::Round($top1 / [math]::Max(1, $Checks.Count), 4)
        Top3       = [math]::Round($top3 / [math]::Max(1, $Checks.Count), 4)
        Proposed   = $proposed
        Precision  = $precision
        Confidence = [double[]] $confidence.ToArray()
        Right      = [bool[]] $right.ToArray()
    }
}
