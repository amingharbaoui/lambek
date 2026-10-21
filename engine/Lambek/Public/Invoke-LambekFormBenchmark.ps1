function Invoke-LambekFormBenchmark {
    <#
    .SYNOPSIS
        Measures the learned forms of words on a treebank they never learned from: lemma, part of speech, features.
    .DESCRIPTION
        Each sentence of the CoNLL-U file is read from its words, as annotated, and what the forms model says of each
        word is compared with the annotation: the part of speech (Upos), the features (Feats), both (AllTags) and the
        lemma (Lemma), over all the words and over the words never seen when learning (Unseen). With -Dictionary, the
        dictionaries Lambek reads today are measured on the same words: whether they know the form, and whether the
        right lemma is among their readings. Every sentence is read twice, the second time in the other order: the
        readings must be the same.

        Lambek is also measured speaking: each verb, noun and adjective of the treebank is said again from its lemma and
        its features (Speak), and the words whose lemma was never seen so when learning are counted apart
        (SpeakUnseen): those it says by analogy with the lemmas it knows.
    .EXAMPLE
        Invoke-LambekFormBenchmark -Path ./bench/forms/fr_gsd-ud-test.conllu -Language fr -Dictionary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Language,

        [switch] $Dictionary
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Treebank not found: $Path" }
    $model = Get-LambekFormModel -Language $Language
    if (-not $model) { throw "No forms model for '$Language'." }
    $sentences = [LambekTreebank]::Read((Resolve-Path -LiteralPath $Path).Path)
    $words = if ($Dictionary) { Get-LambekDictionary -Language $Language }

    $count = @{ Words = 0; Upos = 0; Feats = 0; All = 0; Lemma = 0; Unseen = 0; UnseenLemma = 0; UnseenUpos = 0; Known = 0; Among = 0; Said = 0; SaidRight = 0; New = 0; NewRight = 0 }
    $first = [System.Collections.Generic.List[string]]::new()
    # (only the reading is timed: saying the words again is measured apart)
    $clock = [System.Diagnostics.Stopwatch]::new()
    foreach ($sentence in $sentences) {
        $forms = [string[]] @($sentence | ForEach-Object Form)
        $clock.Start()
        $readings = $model.Read($forms)
        $clock.Stop()
        for ($i = 0; $i -lt $sentence.Length; $i++) {
            $gold = $sentence[$i]
            $read = $readings[$i]
            $first.Add("$($read.Lemma)|$($read.Upos)|$($read.Feats)")
            $count.Words++
            $upos = $read.Upos -ceq $gold.Upos
            $feats = $read.Feats -ceq $gold.Feats
            $lemma = $read.Lemma -ceq $gold.Lemma
            if ($upos) { $count.Upos++ }
            if ($feats) { $count.Feats++ }
            if ($upos -and $feats) { $count.All++ }
            if ($lemma) { $count.Lemma++ }
            if (-not $model.Knows($gold.Form)) {
                $count.Unseen++
                if ($lemma) { $count.UnseenLemma++ }
                if ($upos) { $count.UnseenUpos++ }
            }
            # Said again from its lemma and its features
            $key = [LambekForms]::ParadigmKey($gold.Upos, $gold.Lemma, $gold.Feats)
            if ($key -and $gold.Upos -in 'VERB', 'AUX', 'NOUN', 'ADJ' -and $gold.Feats -ne '_') {
                $said = @($model.Inflect($gold.Lemma, $gold.Upos, $gold.Feats))
                $right = $said.Count -gt 0 -and $said[0] -ceq $gold.Form.ToLowerInvariant()
                $count.Said++
                if ($right) { $count.SaidRight++ }
                if (-not $model.Paradigms.ContainsKey($key)) {
                    $count.New++
                    if ($right) { $count.NewRight++ }
                }
            }
            if ($words) {
                $lemmas = @($words.Lemmas($gold.Form, $Language))
                if ($lemmas.Count -eq 0) { $lemmas = @($words.Lemmas($gold.Form.ToLowerInvariant(), $Language)) }
                if ($lemmas.Count -gt 0) { $count.Known++ }
                $wanted = $gold.Lemma.ToLowerInvariant()
                if (@($lemmas | Where-Object { "$($_.Shown)".ToLowerInvariant() -eq $wanted -or "$($_.Lemma)".ToLowerInvariant() -eq $wanted }).Count -gt 0) { $count.Among++ }
            }
        }
    }
    $seconds = $clock.Elapsed.TotalSeconds

    # Twice, the other way round: the readings must be the same whatever came before
    $again = [System.Collections.Generic.List[string]]::new()
    for ($s = $sentences.Count - 1; $s -ge 0; $s--) {
        $readings = $model.Read([string[]] @($sentences[$s] | ForEach-Object Form))
        $lines = @($readings | ForEach-Object { "$($_.Lemma)|$($_.Upos)|$($_.Feats)" })
        $again.InsertRange(0, [string[]] $lines)
    }
    $same = 0
    for ($i = 0; $i -lt $first.Count; $i++) { if ($first[$i] -ceq $again[$i]) { $same++ } }

    $rate = { param($part, $whole) if ($whole) { [math]::Round($part / $whole, 4) } else { $null } }
    [pscustomobject]@{
        PSTypeName      = 'Lambek.FormBenchmark'
        Language        = $Language
        Sentences       = $sentences.Count
        Words           = $count.Words
        Upos            = & $rate $count.Upos $count.Words
        Feats           = & $rate $count.Feats $count.Words
        AllTags         = & $rate $count.All $count.Words
        Lemma           = & $rate $count.Lemma $count.Words
        Unseen          = $count.Unseen
        UnseenLemma     = & $rate $count.UnseenLemma $count.Unseen
        UnseenUpos      = & $rate $count.UnseenUpos $count.Unseen
        Speak           = & $rate $count.SaidRight $count.Said
        SpeakUnseen     = & $rate $count.NewRight $count.New
        DictionaryKnown = $(if ($Dictionary) { & $rate $count.Known $count.Words })
        DictionaryLemma = $(if ($Dictionary) { & $rate $count.Among $count.Words })
        Determinism     = & $rate $same $first.Count
        WordsPerSecond  = [math]::Round($count.Words / [math]::Max($seconds, 0.001))
    }
}
