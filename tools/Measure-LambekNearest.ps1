#Requires -Version 7.4
<#
.SYNOPSIS
    The nearest examples, weighed by a bell curve and found through an inverted index, against the perceptron of the
    forms models, and both together, on the words Lambek never saw.
.DESCRIPTION
    The task and the features are those of Measure-LambekTsetlin.ps1: the part of speech of a word never seen when
    learning. Both learn from the rare words of the train file, with all their features, and are measured on the words
    of the dev or test file never seen in the train file. Said for each: how many are right; for the two together, how
    many they agree on and how many of those are right, and how many either of them gets right.
    On the test files (k = 10, -Supervised): French 84.7 % against 86.2 % for the perceptron, English 78.5 % against
    78.9 %; where they disagree (10 % and 17 % of the words), the perceptron is right less than half the time.
.EXAMPLE
    ./tools/Measure-LambekNearest.ps1 -Path ./ud/fr_gsd-ud-train.conllu -Measure ./ud/fr_gsd-ud-dev.conllu
#>
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [Parameter(Mandatory)]
    [string] $Measure,

    # The numbers of nearest examples and the widths of the bell to try
    [int[]] $Neighbours = @(5, 10, 20, 40),

    [double[]] $Width = @(0.3, 0.5, 0.8, 2.0),

    [int] $Passes = 10,

    # Weigh the features by how much they tell the parts of speech apart
    [switch] $Supervised
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
if (-not ('LambekNearest' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Nearest/LambekNearest.cs') }

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

$examples = foreach ($sentence in $train) {
    $forms = [string[]] @($sentence | ForEach-Object Form)
    for ($i = 0; $i -lt $sentence.Length; $i++) {
        if ($frequency[$forms[$i].ToLowerInvariant()] -le 2) { [pscustomobject]@{ Features = [string[]] (Get-WordFeature $forms $i); Upos = $sentence[$i].Upos; Form = $forms[$i] } }
    }
}
$unseen = @(foreach ($sentence in $measured) {
        $forms = [string[]] @($sentence | ForEach-Object Form)
        for ($i = 0; $i -lt $sentence.Length; $i++) {
            if (-not $frequency.ContainsKey($forms[$i].ToLowerInvariant())) { [pscustomobject]@{ Features = [string[]] (Get-WordFeature $forms $i); Upos = $sentence[$i].Upos; Form = $forms[$i] } }
        }
    })
Write-Host "$(@($examples).Count) rare words to learn from, $($unseen.Count) unseen words to measure."

# The perceptron, every feature
$perceptron = [LambekPerceptron]::new()
foreach ($class in @($examples | ForEach-Object Upos | Sort-Object -Unique)) { [void] $perceptron.ClassOf($class, $true) }
for ($pass = 0; $pass -lt $Passes; $pass++) { foreach ($example in $examples) { [void] $perceptron.Learn($example.Features, $perceptron.ClassOf($example.Upos, $false), $null) } }
$perceptron.Average()
$said = @($unseen | ForEach-Object { $perceptron.Classes[$perceptron.Best($_.Features, $null)] })
$right = 0
for ($i = 0; $i -lt $unseen.Count; $i++) { if ($said[$i] -eq $unseen[$i].Upos) { $right++ } }
Write-Host ('Perceptron: {0:P2}' -f ($right / $unseen.Count))

# The nearest examples
$memory = [LambekNearest]::new()
$memory.Supervised = [bool] $Supervised
foreach ($example in $examples) { $memory.Add($example.Features, $example.Upos, $example.Form) }
foreach ($k in $Neighbours) {
    foreach ($w in $Width) {
        $near = 0; $agree = 0; $agreeRight = 0; $either = 0; $apartRight = 0
        for ($i = 0; $i -lt $unseen.Count; $i++) {
            $share = 0.0; $why = $null
            $voted = $memory.Vote($unseen[$i].Features, $k, $w, [ref] $share, [ref] $why)
            $truth = $unseen[$i].Upos
            if ($voted -eq $truth) { $near++ }
            if ($voted -eq $said[$i]) { $agree++; if ($voted -eq $truth) { $agreeRight++ } }
            elseif ($said[$i] -eq $truth) { $apartRight++ }
            if ($voted -eq $truth -or $said[$i] -eq $truth) { $either++ }
        }
        $apart = $unseen.Count - $agree
        Write-Host ('Nearest k={0,-3} width={1,-4}: {2:P2} | both agree on {3:P1}, right then {4:P2}; apart, the perceptron right {5:P2} | either right {6:P2}' -f $k, $w, ($near / $unseen.Count), ($agree / $unseen.Count), ($agreeRight / [math]::Max(1, $agree)), ($apartRight / [math]::Max(1, $apart)), ($either / $unseen.Count))
    }
}
