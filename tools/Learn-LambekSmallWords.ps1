#Requires -Version 7.6
<#
.SYNOPSIS
    Lambek learns the small words of each language (the determiners, prepositions, pronouns, conjunctions, auxiliaries
    and particles it writes often) from the forms models learned from its treebanks, never from a list written by
    hand: engine/Lambek/Data/Forms/<language>.small.
.DESCRIPTION
    The forms model of a language (Data/Forms/<language>.forms.gz, tools/Build-LambekForms.ps1) holds every form its
    treebanks wrote, with its part of speech. A word is a small word of a language when its treebanks wrote it as a
    word of a closed class more than half the times they wrote it, at least -Rate of all the words they wrote ("y" of
    Spanish, "en" of Dutch), and no other language writes it as a small word -Ratio times as often (an English "the"
    quoted in a German newspaper is no small word of German). The words are bare (lower case, no accents), as the
    language of a message is told by them (Get-LambekLanguageScore -Forms).

    They tell the language of a message where the small words written by hand say nothing or the wrong thing: the
    readers of general rules and the language of a chat. The router, the guards and the readers of requests keep the
    words written by hand, which they were measured with.
.EXAMPLE
    ./tools/Learn-LambekSmallWords.ps1
#>
param(
    # The languages, all those with a forms model when none is named
    [string[]] $Language = @(),

    # How often a small word is written, at least, of all the words the treebanks of its language wrote
    [double] $Rate = 0.0002,

    # How many times as often another language must write a word as a small word for it to be that language's only
    [double] $Ratio = 10
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$forms = Join-Path $root 'engine/Lambek/Data/Forms'
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force

$all = @(Get-ChildItem -LiteralPath $forms -Filter '*.forms.gz' | ForEach-Object { $_.Name -replace '\.forms\.gz$', '' } | Sort-Object)
if ($Language.Count -eq 0) { $Language = $all }

# Every language is read, the ones named and the others, for a word to be compared with all of them
$counts = [ordered]@{}
$hashes = @{}
foreach ($name in $all) {
    $path = Join-Path $forms "$name.forms.gz"
    $counts[$name] = [LambekFormCounts]::Load([IO.Path]::GetFullPath($path))
    $hashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

foreach ($name in $Language) {
    if (-not $counts.Contains($name)) { throw "No forms model for '$name' in $forms." }
    $mine = $counts[$name]
    $kept = foreach ($word in $mine.SmallWords()) {
        $small = $mine.SmallCount($word)
        if ($small * 2 -le $mine.Count($word)) { continue }
        $share = $small / $mine.Total
        if ($share -lt $Rate) { continue }
        $theirs = @($all | Where-Object { $_ -ne $name -and $counts[$_].Total -gt 0 -and $counts[$_].SmallCount($word) / $counts[$_].Total -ge $share * $Ratio })
        if ($theirs.Count -gt 0) { continue }
        [pscustomobject]@{ Word = $word; Count = $small }
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# lambek-small-1`t$name.forms.gz $($hashes[$name]), rate $($Rate.ToString([cultureinfo]::InvariantCulture)), ratio $($Ratio.ToString([cultureinfo]::InvariantCulture))")
    foreach ($row in @($kept | Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = { $_.Word }; Descending = $false })) {
        $lines.Add("$($row.Word)`t$($row.Count)")
    }
    $out = Join-Path $forms "$name.small"
    [IO.File]::WriteAllText($out, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Write-Host "$name : $(@($kept).Count) small words -> $out"
}
