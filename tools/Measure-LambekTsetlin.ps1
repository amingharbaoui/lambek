#Requires -Version 7.6
<#
.SYNOPSIS
    The experiment of step 4.3: rules that can be read (a Tsetlin machine) against the perceptron of the forms models,
    on the words Lambek never saw.
.DESCRIPTION
    The task: the part of speech of a word never seen when learning, from its ends, its shape and its neighbours. Both
    learn from the rare words of the train file (seen at most twice), with the same features (the most frequent ones),
    in the same order, and are measured on the words of the dev or test file never seen in the train file.
    The Tsetlin machine (tools/Tsetlin/LambekTsetlin.cs) is not part of the engine: on French, it read 85.7 % of the
    unseen words of the dev file at best, against 89.0 % for the perceptron, and its rules could be read only when it
    read 77 % of them (-Positive). The perceptron was kept.
.EXAMPLE
    ./tools/Measure-LambekTsetlin.ps1 -Path ./ud/fr_gsd-ud-train.conllu -Measure ./ud/fr_gsd-ud-dev.conllu -Clauses 100 -Threshold 25 -Specificity 3
#>
param(
    # The train file of a treebank
    [Parameter(Mandatory)]
    [string] $Path,

    # The file to measure on (dev or test)
    [Parameter(Mandatory)]
    [string] $Measure,

    # How many features are kept, the most frequent first
    [int] $Features = 1024,

    [int] $Clauses = 100,

    [int] $Threshold = 25,

    [double] $Specificity = 3,

    [int] $Passes = 10,

    # Clauses of features only, never of their absence: rules easier to read
    [switch] $Positive,

    # Say the first rules learned for a few parts of speech
    [switch] $ShowRules
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
if (-not ('LambekTsetlin' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Tsetlin/LambekTsetlin.cs') }

$train = [LambekTreebank]::Read((Resolve-Path -LiteralPath $Path).Path)
$measured = [LambekTreebank]::Read((Resolve-Path -LiteralPath $Measure).Path)
$frequency = @{}
foreach ($sentence in $train) { foreach ($word in $sentence) { $key = $word.Form.ToLowerInvariant(); $frequency[$key] = 1 + [int] $frequency[$key] } }
$common = [System.Collections.Generic.HashSet[string]]::new([string[]] @($frequency.GetEnumerator() | Sort-Object { -$_.Value }, Name | Select-Object -First 200 | ForEach-Object Name))

# What both learners see of a word: its ends, its shape, and its neighbours when they are common words
function Get-WordFeature {
    param([string[]] $Forms, [int] $Index)
    $word = $Forms[$Index]
    $lower = $word.ToLowerInvariant()
    $seen = [System.Collections.Generic.List[string]]::new()
    for ($n = 1; $n -le 4; $n++) { if ($lower.Length -ge $n) { $seen.Add("s$n=" + $lower.Substring($lower.Length - $n)) } }
    for ($n = 1; $n -le 3; $n++) { if ($lower.Length -ge $n) { $seen.Add("p$n=" + $lower.Substring(0, $n)) } }
    if ($word.Length -gt 0 -and [char]::IsUpper($word[0])) { $seen.Add('cap') }
    if ($word -cmatch '^\p{Lu}+$' -and $word.Length -gt 1) { $seen.Add('allcap') }
    if ($word -match '\d') { $seen.Add('digit') }
    if ($word.Contains('-')) { $seen.Add('hyphen') }
    if ($Index -eq 0) { $seen.Add('first') }
    $seen.Add('len=' + [math]::Min($lower.Length, 12))
    $left = if ($Index -gt 0) { $Forms[$Index - 1].ToLowerInvariant() } else { '<s>' }
    $right = if ($Index + 1 -lt $Forms.Length) { $Forms[$Index + 1].ToLowerInvariant() } else { '</s>' }
    $seen.Add('w-1=' + $(if ($left -eq '<s>' -or $common.Contains($left)) { $left } else { '*' }))
    $seen.Add('w+1=' + $(if ($right -eq '</s>' -or $common.Contains($right)) { $right } else { '*' }))
    return , $seen
}

$examples = foreach ($sentence in $train) {
    $forms = [string[]] @($sentence | ForEach-Object Form)
    for ($i = 0; $i -lt $sentence.Length; $i++) {
        if ($frequency[$forms[$i].ToLowerInvariant()] -le 2) { [pscustomobject]@{ Features = (Get-WordFeature $forms $i); Upos = $sentence[$i].Upos } }
    }
}
$unseen = foreach ($sentence in $measured) {
    $forms = [string[]] @($sentence | ForEach-Object Form)
    for ($i = 0; $i -lt $sentence.Length; $i++) {
        if (-not $frequency.ContainsKey($forms[$i].ToLowerInvariant())) { [pscustomobject]@{ Features = (Get-WordFeature $forms $i); Upos = $sentence[$i].Upos } }
    }
}

$counts = @{}
foreach ($example in $examples) { foreach ($feature in $example.Features) { $counts[$feature] = 1 + [int] $counts[$feature] } }
$kept = [string[]] @($counts.GetEnumerator() | Sort-Object { -$_.Value }, Name | Select-Object -First $Features | ForEach-Object Name)
$featureId = @{}
for ($i = 0; $i -lt $kept.Length; $i++) { $featureId[$kept[$i]] = $i }
$classes = [string[]] @($examples | ForEach-Object Upos | Sort-Object -Unique)
$classId = @{}
for ($i = 0; $i -lt $classes.Length; $i++) { $classId[$classes[$i]] = $i }
$keep = { param($list) [string[]] @($list | Where-Object { $featureId.ContainsKey($_) }) }
Write-Host "$($examples.Count) rare words to learn from, $($unseen.Count) unseen words to measure, $($kept.Length) features, $($classes.Length) parts of speech."

$perceptron = [LambekPerceptron]::new()
foreach ($class in $classes) { [void] $perceptron.ClassOf($class, $true) }
for ($pass = 0; $pass -lt $Passes; $pass++) { foreach ($example in $examples) { [void] $perceptron.Learn((& $keep $example.Features), $classId[$example.Upos], $null) } }
$perceptron.Average()
$right = @($unseen | Where-Object { $classes[$perceptron.Best((& $keep $_.Features), $null)] -eq $_.Upos }).Count
Write-Host ('Perceptron: {0:P2}' -f ($right / $unseen.Count))

$machine = [LambekTsetlin]::new($classes, $kept, $Clauses, $Threshold, $Specificity, 100, 20261020, [bool] $Positive)
$ids = { param($list) [int[]] @($list | Where-Object { $featureId.ContainsKey($_) } | ForEach-Object { $featureId[$_] }) }
$learning = @($examples | ForEach-Object { , (& $ids $_.Features) })
$truth = @($examples | ForEach-Object { $classId[$_.Upos] })
$asked = @($unseen | ForEach-Object { , (& $ids $_.Features) })
$clock = [Diagnostics.Stopwatch]::StartNew()
for ($pass = 0; $pass -lt $Passes; $pass++) {
    for ($i = 0; $i -lt $learning.Count; $i++) { $machine.Learn($learning[$i], $truth[$i]) }
    $right = 0
    for ($i = 0; $i -lt $asked.Count; $i++) { if ($classes[$machine.Predict($asked[$i])] -eq $unseen[$i].Upos) { $right++ } }
    Write-Host ('Tsetlin, pass {0}: {1:P2} ({2:N0}s)' -f ($pass + 1), ($right / $unseen.Count), $clock.Elapsed.TotalSeconds)
}
Write-Host "Literals in the clauses: $($machine.Included)"
if ($ShowRules) {
    foreach ($class in 'VERB', 'NOUN', 'ADJ', 'PROPN') {
        if (-not $classId.ContainsKey($class)) { continue }
        Write-Host "== $class"
        $machine.Rules($classId[$class]) | Where-Object { $_.StartsWith('+') } | Select-Object -First 6 | ForEach-Object { Write-Host "   $_" }
    }
}
