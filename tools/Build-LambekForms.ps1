#Requires -Version 7.6
<#
.SYNOPSIS
    Learns the forms of the words of a language (lemma, part of speech, features) from annotated treebanks, for Lambek
    to read words without a dictionary written by hand.
.DESCRIPTION
    Every word of a Universal Dependencies treebank is annotated with its lemma, its part of speech and its features.
    From them Lambek learns, and keeps only what it learned:
    - the rule of form of every word (what to take off and put on its ends to find its lemma), checked to give back
      every lemma of the treebanks;
    - a perceptron that says the part of speech and the features of a word from the word, its ends and its neighbours,
      and one that says which rule of form to apply; all in integers, every pass in the same order, so the same
      treebanks give the same model, byte for byte, on every machine;
    - how written text is cut into words ("du": de le, "l'avion": l' avion), from the same treebanks;
    - the paradigms: the forms each lemma was seen with, by part of speech and features, to say words as well as to
      read them (a slip of the annotators, Typo=Yes, or a shortened word, Abbr=Yes, is left out).

    The treebanks of the models of Lambek, release 2.18 of Universal Dependencies (CC BY-SA 4.0), train and dev
    files (the test files are in bench/forms, to measure the models, never to learn from). For French, the written
    French of GSD and the spoken French of ParisStories and Rhapsodie, where people say tu and ask questions:
      https://raw.githubusercontent.com/UniversalDependencies/UD_French-GSD/r2.18/fr_gsd-ud-train.conllu
      https://raw.githubusercontent.com/UniversalDependencies/UD_French-GSD/r2.18/fr_gsd-ud-dev.conllu
      https://raw.githubusercontent.com/UniversalDependencies/UD_French-ParisStories/r2.18/fr_parisstories-ud-train.conllu
      https://raw.githubusercontent.com/UniversalDependencies/UD_French-ParisStories/r2.18/fr_parisstories-ud-dev.conllu
      https://raw.githubusercontent.com/UniversalDependencies/UD_French-Rhapsodie/r2.18/fr_rhapsodie-ud-train.conllu
      https://raw.githubusercontent.com/UniversalDependencies/UD_French-Rhapsodie/r2.18/fr_rhapsodie-ud-dev.conllu
      https://raw.githubusercontent.com/UniversalDependencies/UD_English-EWT/r2.18/en_ewt-ud-train.conllu
      https://raw.githubusercontent.com/UniversalDependencies/UD_English-EWT/r2.18/en_ewt-ud-dev.conllu
    Their SHA-256 are checked when they are given with these names. For German, Spanish, Dutch, Portuguese and Italian,
    the treebanks named in engine/Lambek/Data/Forms/SOURCES.md, from the same release, at the same addresses.

    A language whose treebanks are small can be given its sentences translated from English (-English and
    -Translated, Tatoeba): the model learned from the treebanks reads them, with the lexicon of the language, and the
    model of English its English side; the words are aligned (IBM Model 1, both ways) and the part of speech of each
    English word is carried over to the word it is aligned with, as far as the words the treebanks know carry over to
    their own (LambekProjection). The sentences where every word carried over agrees with the reading of the model, or
    is set right by what the treebanks or the lexicon say of it, and that have a word the treebanks never met, are
    taught to the tagger after the treebanks, as many words of them as the treebanks have (more, and the short
    sentences of Tatoeba weigh more than the treebanks: measured on the Italian dev files of ISDT and VIT). They teach
    the tags of words in context only: the words known, their lemmas and their rules of form are the treebanks'.
.EXAMPLE
    ./tools/Build-LambekForms.ps1 -Language it -Path (Get-ChildItem ./ud/it_*-ud-train.conllu, ./ud/it_*-ud-dev.conllu) -English ./tatoeba/Tatoeba.en-it.en -Translated ./tatoeba/Tatoeba.en-it.it -OutFile ./engine/Lambek/Data/Forms/it.forms.gz
.EXAMPLE
    ./tools/Build-LambekForms.ps1 -Language fr -Path (Get-ChildItem ./ud/fr_*-ud-train.conllu, ./ud/fr_*-ud-dev.conllu) -OutFile ./engine/Lambek/Data/Forms/fr.forms.gz
#>
param(
    [Parameter(Mandatory)]
    [string] $Language,

    # CoNLL-U files to learn from
    [Parameter(Mandatory)]
    [string[]] $Path,

    [Parameter(Mandatory)]
    [string] $OutFile,

    # Passes over the treebanks: 10 on the dev files of French and English, more changed nothing
    [int] $Passes = 10,

    # The sentences of the language translated from English, one a line, and their English, line for line (Tatoeba,
    # Moses format): read and aligned to teach the tagger more sentences
    [string] $English,

    [string] $Translated,

    # A part of speech carried over is believed as far as the known words carry it over right: `Trust` of the time to
    # set a word right, `Doubt` of the time to refuse a sentence, when met at least `Least` times
    [double] $Trust = 0.9,

    [double] $Doubt = 0.6,

    [int] $Least = 100
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force

# The files of release 2.18, as they were when the models of Lambek were learned
$known = @{
    'fr_gsd-ud-train.conllu' = '4b9a87b1b7e6e7003219df1d3ccca87ffaca0f00a6055b12b1857df5373589d2'
    'fr_gsd-ud-dev.conllu'   = '9221e5084cc6a1b1540671cfbd2fc0456efc223b2fe8dd2146c2bad921be02d4'
    'fr_parisstories-ud-train.conllu' = '558c125ecb84f4e16ef8d8871368e24b8c6054446a06da9a5211fc67abb65a1d'
    'fr_parisstories-ud-dev.conllu' = '3b37b918ab0d7885604f0fe5b91c412320157f18d0257eda11dbdec94e0666ad'
    'fr_rhapsodie-ud-train.conllu' = '082695d3b008734319c3c2303722acb45afbc70d1223c2591100754b24f4726e'
    'fr_rhapsodie-ud-dev.conllu' = 'f69bafa87da277d04d56c8c08c9518ea6c622cf5c4493cd7261580973853b450'
    'en_ewt-ud-train.conllu' = 'd68e06122a702464c613076523d56740f047e5bbe89dd90ec32737e04d952143'
    'en_ewt-ud-dev.conllu'   = '39239e0a60db3ae68f4b7036189f11b6692741d10ff8240dd91f74f2760d90f8'
}
$files = foreach ($item in $Path) {
    $full = (Resolve-Path -LiteralPath $item).Path
    $name = Split-Path -Path $full -Leaf
    if ($known.ContainsKey($name)) {
        $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $known[$name]) { Write-Warning "$name is not the file of release 2.18: the model will differ from the one shipped." }
    }
    $full
}

$sentences = [System.Collections.Generic.List[LambekTreebankWord[]]]::new()
foreach ($file in $files) {
    $read = [LambekTreebank]::Read($file)
    # A treebank that hides its words ("_", to be put back from elsewhere) or leaves out their lemmas or their features
    # would teach "_" for a word and no features for any: it is never learned from
    $count = 0; $form = 0; $lemma = 0; $feats = 0
    foreach ($sentence in $read) {
        foreach ($word in $sentence) {
            $count++
            if ($word.Form -ceq '_') { $form++ }
            if ($word.Lemma -ceq '_') { $lemma++ }
            if ($word.Feats -ceq '_') { $feats++ }
        }
    }
    foreach ($missing in @(@('words', $form), @('lemmas', $lemma), @('features', $feats))) {
        if ($count -gt 0 -and $missing[1] -gt 0.9 * $count) { throw "$(Split-Path -Path $file -Leaf) leaves out the $($missing[0]) of $($missing[1]) of its $count words: it cannot be learned from." }
    }
    $sentences.AddRange($read)
}
$words = 0
foreach ($sentence in $sentences) { $words += $sentence.Length }
Write-Host "$($files.Count) file(s), $($sentences.Count) sentences, $words words."

# Every lemma must be found again by its rule of form
$rules = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$lost = 0
foreach ($sentence in $sentences) {
    foreach ($word in $sentence) {
        $rule = [LambekFormRule]::Of($word.Form, $word.Lemma)
        [void] $rules.Add($rule)
        if ([LambekFormRule]::Apply($rule, $word.Form) -cne $word.Lemma) { $lost++ }
    }
}
Write-Host "$($rules.Count) rules of form; lemmas not found again by their rule: $lost."
if ($lost -gt 0) { throw "$lost lemma(s) are not found again by their rule of form." }

$model = [LambekForms]::new()
$model.Language = $Language
$model.Passes = $Passes
$model.LearnTokens([string[]] $files)
$clock = [Diagnostics.Stopwatch]::StartNew()
$projected = [System.Collections.Generic.List[LambekTreebankWord[]]]::new()
if ($English -or $Translated) {
    if (-not ($English -and $Translated)) { throw 'The translated sentences need both sides: -English and -Translated.' }
    # The model of the treebanks alone, with the lexicon of the language, reads the translated side
    $reader = [LambekForms]::new()
    $reader.Language = $Language
    $reader.Passes = $Passes
    $reader.LearnTokens([string[]] $files)
    $reader.Train($sentences, [Action[int]] { param($pass) Write-Host "  pass $pass of $Passes, treebanks alone ($([math]::Round($clock.Elapsed.TotalSeconds))s)" })
    # (saved and loaded again, with what Lambek learned of the language besides, as the engine reads it)
    $first = Join-Path ([IO.Path]::GetTempPath()) "lambek-forms-$PID.forms.gz"
    $reader.Save($first)
    $reader = [LambekForms]::Load($first)
    Remove-Item -LiteralPath $first -Force
    $data = Join-Path $PSScriptRoot '../engine/Lambek/Data/Forms'
    $learned = Join-Path $data "$Language.learned.gz"
    if (Test-Path -LiteralPath $learned -PathType Leaf) { $reader.AddLearned([LambekSelfReader]::Load((Resolve-Path -LiteralPath $learned).Path)) }
    $lexicon = Join-Path $data "$Language.lexicon.gz"
    if (Test-Path -LiteralPath $lexicon -PathType Leaf) { $reader.Lexicon = [LambekLexicon]::Load((Resolve-Path -LiteralPath $lexicon).Path) }
    $englishModel = & (Get-Module Lambek) { Get-LambekFormModel -Language en }
    $result = [LambekProjection]::Project($englishModel, $reader, [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $English).Path), [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Translated).Path), 12, 5, $Trust, $Doubt, $Least)
    Write-Host "$($result.Pairs) pairs aligned; carried over right: $(@($result.Trust.GetEnumerator() | ForEach-Object { '{0} {1:P0}' -f $_.Key, $_.Value }) -join ', ')"
    $taken = 0
    foreach ($sentence in $result.Sentences) {
        if ($taken + $sentence.Length -gt $words) { break }
        $taken += $sentence.Length
        $projected.Add($sentence)
    }
    Write-Host "$($result.Sentences.Count) sentences kept ($($result.Refused) refused, $($result.Unsure) unsure, $($result.Known) of known words only), $($projected.Count) taught ($taken words)."
    $reader = $null
    [GC]::Collect()
    $clock.Restart()
}
$model.Train($sentences, $projected, [Action[int]] { param($pass) Write-Host "  pass $pass of $Passes ($([math]::Round($clock.Elapsed.TotalSeconds))s)" })
Write-Host "Learned in $([math]::Round($clock.Elapsed.TotalSeconds))s: $($model.Tagger.Classes.Count) tags, $($model.Lemmatiser.Classes.Count) rules, $($model.Tagger.WeightCount + $model.Lemmatiser.WeightCount) weights; $($model.Contractions.Count) contractions."

$full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
New-Item -ItemType Directory -Path (Split-Path -Path $full -Parent) -Force | Out-Null
$model.Save($full)
$hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Written $full ($([math]::Round((Get-Item -LiteralPath $full).Length / 1MB, 1)) MB), SHA-256 $hash"
