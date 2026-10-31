#Requires -Version 7.6
<#
.SYNOPSIS
    Learns how a language sounds (the shapes of its sentences) from free corpora, for Lambek to choose how it says things.
.DESCRIPTION
    Every line of every file is a sentence. The same sentence twice counts once. One line in fifty is kept aside, and
    the perplexity of the model on them is said at the end. The corpora used for the models of Lambek, both free:
    - Common Voice (CC0): git clone --depth 1 --filter=blob:none --sparse https://github.com/common-voice/common-voice
      then git sparse-checkout set server/data/fr server/data/en (the addresses and single words are left out);
    - Europarl, sample of NLTK (no copyright restriction known):
      https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/europarl_raw.zip
.EXAMPLE
    ./tools/Build-LambekFluency.ps1 -Language fr -Path ./cv/server/data/fr, ./europarl_raw/french -OutFile ./engine/Lambek/Data/Speech/fr.fluency.gz
#>
param(
    [Parameter(Mandatory)]
    [string] $Language,

    # Files or folders of sentences, one per line
    [Parameter(Mandatory)]
    [string[]] $Path,

    [Parameter(Mandatory)]
    [string] $OutFile,

    [int] $Order = 3,

    # How many frequent words are kept as themselves; every other word is read as its kind
    [int] $Keep = 1000,

    # The fewest times an n-gram of each order from 2 up must be seen to be kept
    [int[]] $Least = @(2, 3)
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
$dictionary = & (Get-Module Lambek) { param($language) Get-LambekDictionary -Language $language } $Language

$files = foreach ($item in $Path) {
    if (Test-Path -LiteralPath $item -PathType Container) {
        Get-ChildItem -LiteralPath $item -File | Where-Object Name -NotMatch '^(addresses|singleword|lulucmy)' | Sort-Object Name | ForEach-Object FullName
    }
    else { (Resolve-Path -LiteralPath $item).Path }
}
$learned = [System.Collections.Generic.List[string]]::new()
$aside = [System.Collections.Generic.List[string]]::new()
$line = 0
foreach ($file in $files) {
    foreach ($sentence in [IO.File]::ReadLines($file)) {
        if ($line % 50 -eq 7) { $aside.Add($sentence) } else { $learned.Add($sentence) }
        $line++
    }
}
Write-Host "$($files.Count) files, $($learned.Count) sentences to learn from, $($aside.Count) kept aside."

$clock = [Diagnostics.Stopwatch]::StartNew()
$model = [LambekFluency]::Train($learned, $Language, $dictionary, $Order, $Keep, $Least)
Write-Host "Learned in $([math]::Round($clock.Elapsed.TotalSeconds))s: $($model.Sentences) sentences, $($model.Tokens) words, $($model.Symbols.Length) symbols, $($model.Size()) n-grams."
$full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
New-Item -ItemType Directory -Path (Split-Path -Path $full -Parent) -Force | Out-Null
$model.Save($full)

$model = [LambekFluency]::Load($full)
$sum = 0.0
$count = 0.0
foreach ($sentence in $aside) {
    $score = $model.Score($sentence, $dictionary)
    $sum += $score[0]
    $count += $score[1]
}
Write-Host "Saved $full ($((Get-Item -LiteralPath $full).Length) bytes). Perplexity on the sentences kept aside: $([math]::Round([math]::Pow(10, -$sum / $count), 2))."
