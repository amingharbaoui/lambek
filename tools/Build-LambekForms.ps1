#Requires -Version 7.4
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
    - how written text is cut into words ("du": de le, "l'avion": l' avion), from the same treebanks.

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
    Their SHA-256 are checked when they are given with these names.
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
    [int] $Passes = 10
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
foreach ($file in $files) { $sentences.AddRange([LambekTreebank]::Read($file)) }
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
$model.Train($sentences, [Action[int]] { param($pass) Write-Host "  pass $pass of $Passes ($([math]::Round($clock.Elapsed.TotalSeconds))s)" })
Write-Host "Learned in $([math]::Round($clock.Elapsed.TotalSeconds))s: $($model.Tagger.Classes.Count) tags, $($model.Lemmatiser.Classes.Count) rules, $($model.Tagger.WeightCount + $model.Lemmatiser.WeightCount) weights; $($model.Contractions.Count) contractions."

$full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
New-Item -ItemType Directory -Path (Split-Path -Path $full -Parent) -Force | Out-Null
$model.Save($full)
$hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Written $full ($([math]::Round((Get-Item -LiteralPath $full).Length / 1MB, 1)) MB), SHA-256 $hash"
