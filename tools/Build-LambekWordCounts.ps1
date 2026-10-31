#Requires -Version 7.6
<#
.SYNOPSIS
    Counts how often each word is written in the plain texts Lambek reads (tools/corpus.json), for each language, into
    engine/Lambek/Data/Speech/<language>.counts.gz.
.DESCRIPTION
    The language model of Lambek (Data/Speech/<language>.fluency.gz) keeps its frequent words as themselves and reads
    every other word as its kind ("a noun"), so it cannot tell "fleuve" from "flue" when "fluve" was typed. These counts
    can: how often each word is written, in lower case, letters only. A word is kept only when at least two sources write
    it, and twice at least, so a slip in one text ("teh") is no word. No list is written for any language: the counts
    come from the texts of the manifest, the same for every language it has.
    The texts are downloaded first by tools/Get-LambekCorpus.ps1; they never go into the repository, only the counts.
.EXAMPLE
    ./tools/Build-LambekWordCounts.ps1 -Path ../lambek-corpus -Language fr, en
#>
param(
    # The folder the texts were downloaded into (tools/Get-LambekCorpus.ps1)
    [string] $Path = (Join-Path $PSScriptRoot '../../lambek-corpus'),

    # The languages to count
    [string[]] $Language = @('fr', 'en'),

    # A word is kept when this many sources write it, this many times in all
    [int] $LeastSources = 2,
    [long] $LeastCount = 2
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'corpus.json') -Raw | ConvertFrom-Json
$folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

foreach ($code in $Language) {
    $counts = [LambekWordCounts]::new()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    foreach ($source in @($manifest.Sources | Where-Object Language -EQ $code)) {
        $text = Join-Path $folder $source.Text
        if (-not (Test-Path -LiteralPath $text -PathType Leaf)) { throw "$($source.Name) is not in $folder (run tools/Get-LambekCorpus.ps1 first)." }
        $counts.Add([LambekCorpusText]::Sentences($text, $source.Shape))
        Write-Host ("  {0,-28} read ({1:N0}s)" -f $source.Name, $clock.Elapsed.TotalSeconds)
    }
    $counts.Keep($LeastSources, $LeastCount)
    $out = Join-Path $PSScriptRoot "../engine/Lambek/Data/Speech/$code.counts.gz"
    $counts.Save([IO.Path]::GetFullPath($out))
    Write-Host ("{0}: {1:N0} words kept, {2:N0} written in all, into {3}" -f $code, $counts.Count, $counts.Total, $out)
}
