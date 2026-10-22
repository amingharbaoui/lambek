#Requires -Version 7.4
<#
.SYNOPSIS
    Downloads the plain texts Lambek reads to learn words on its own (tools/corpus.json), into a folder of their own.
.DESCRIPTION
    Each source is downloaded once, its SHA-256 compared with the one written in tools/corpus.json (a source that
    changed since is kept, with a warning: Tatoeba and Common Voice grow every week), then unpacked into the text that
    tools/Learn-LambekWords.ps1 reads. The texts never go into the repository: only what Lambek learned from them does.
    Licences: Tatoeba CC BY 2.0 FR, Leipzig Corpora Collection CC BY, Common Voice CC0, Project Gutenberg public domain;
    the judges: UD French-FQB and French-Sequoia LGPL-LR, UniMorph CC BY-SA 3.0.
.EXAMPLE
    ./tools/Get-LambekCorpus.ps1 -Path ../lambek-corpus -Language fr
#>
param(
    # The folder the texts go into (outside the repository)
    [string] $Path = (Join-Path $PSScriptRoot '../../lambek-corpus'),

    # Only the sources of these languages
    [string[]] $Language = @('fr', 'en')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'corpus.json') -Raw | ConvertFrom-Json
$folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
New-Item -ItemType Directory -Path $folder -Force | Out-Null

foreach ($source in @($manifest.Sources | Where-Object { $_.Language -in $Language })) {
    $file = Join-Path $folder $source.File
    $text = Join-Path $folder $source.Text
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Host "Downloading $($source.Name) from $($source.Url)"
        Invoke-WebRequest -Uri $source.Url -OutFile $file -UseBasicParsing
    }
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $source.Sha256) { Write-Warning "$($source.Name) is not the file Lambek learned from (it changed since): what is learned from it will differ." }

    if (-not (Test-Path -LiteralPath $text -PathType Leaf)) {
        switch ($source.Unpack) {
            'bzip2' {
                $reader = [LambekBzip2Reader]::new([IO.File]::OpenRead($file))
                $writer = [IO.File]::Create($text)
                try { $reader.CopyTo($writer) } finally { $writer.Dispose(); $reader.Dispose() }
            }
            'tar.gz' {
                $stream = [IO.Compression.GZipStream]::new([IO.File]::OpenRead($file), [IO.Compression.CompressionMode]::Decompress)
                $tar = [System.Formats.Tar.TarReader]::new($stream)
                try {
                    while ($null -ne ($entry = $tar.GetNextEntry())) {
                        if ($entry.Name -eq $source.Member) { $entry.ExtractToFile($text, $true); break }
                    }
                }
                finally { $tar.Dispose(); $stream.Dispose() }
                if (-not (Test-Path -LiteralPath $text -PathType Leaf)) { throw "$($source.Member) is not in $($source.File)." }
            }
            default { }
        }
    }
    Write-Host ("{0,-28} {1,-8} {2}" -f $source.Name, $source.Language, $source.Licence)
}
# What the notebooks are measured on before they are written: treebanks never learned from, and conjugations
foreach ($judge in @($manifest.Judges | Where-Object { $_.Language -in $Language })) {
    $file = Join-Path $folder $judge.File
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Host "Downloading $($judge.Name) from $($judge.Url)"
        Invoke-WebRequest -Uri $judge.Url -OutFile $file -UseBasicParsing
    }
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $judge.Sha256) { Write-Warning "$($judge.Name) is not the file the notebooks were measured on." }
    Write-Host ("{0,-28} {1,-8} {2}" -f $judge.Name, $judge.Language, $judge.Licence)
}
Write-Host "The texts are in $folder."
