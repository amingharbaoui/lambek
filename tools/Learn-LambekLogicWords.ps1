#Requires -Version 7.6
<#
.SYNOPSIS
    Lambek learns the words of logic of a language (the words that say "every one", "at least one", "none") from
    sentences translated from and to English, never from a list written by hand: engine/Lambek/Data/Forms/<language>.logic.
.DESCRIPTION
    The English side says the kind: the treebank of English (UD English-EWT) tags "all", "every", "each" PronType=Tot,
    "some" PronType=Ind, "no" PronType=Neg, and the forms model of English reads them so in context. The copulas, the
    verbs that only join ("est" of "Tom est un chat"), are the lemmas the treebanks of the language tag cop. Both sides of every
    pair are read by the forms models of their languages; a lemma of the other language is a word of that kind when it is
    met as a determiner or a pronoun in at least -Least pairs with that kind on the English side, and with it in most of
    the pairs where it is met (Native/Logic.cs). For English itself, the words are those its treebank tags so.

    The pairs: Tatoeba, release v2023-04-12 of OPUS (CC BY 2.0 FR), in Moses format, one sentence a line on each side:
      https://object.pouta.csc.fi/OPUS-Tatoeba/v2023-04-12/moses/en-fr.txt.zip (de-en, en-es, en-it, en-nl, en-pt)
.EXAMPLE
    ./tools/Learn-LambekLogicWords.ps1 -Language fr -English ../tatoeba/Tatoeba.en-fr.en -Other ../tatoeba/Tatoeba.en-fr.fr -Treebank ./ud/fr_gsd-ud-train.conllu
.EXAMPLE
    ./tools/Learn-LambekLogicWords.ps1 -Language en -Treebank ./ud/en_ewt-ud-train.conllu
#>
param(
    [Parameter(Mandatory)]
    [string] $Language,

    # The English side and the side of the language, one sentence a line, the same line for the same pair
    [string] $English,
    [string] $Other,

    # Treebanks of the language (CoNLL-U), for its copulas: the lemmas they tag with the relation cop
    [Parameter(Mandatory)]
    [string[]] $Treebank,

    # The least pairs a word must be met in with its kind
    [int] $Least = 20,

    # Longer sentences are left out: in a short one, a word of logic on one side is the one on the other
    [int] $Longest = 12,

    [string] $OutFile = (Join-Path $PSScriptRoot "../engine/Lambek/Data/Forms/$Language.logic")
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
function Get-LambekForms {
    param([string] $Name)
    [LambekForms]::Load([IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../engine/Lambek/Data/Forms/$Name.forms.gz")))
}
$englishForms = Get-LambekForms -Name 'en'
$out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
if ($Language -eq 'en') {
    $words = [LambekLogicWords]::FromTags($englishForms)
    $source = 'UD English-EWT 2.18 (CC BY-SA 4.0), as its annotators tagged the words'
}
else {
    if (-not $English -or -not $Other) { throw 'Give the English side and the side of the language (-English, -Other).' }
    $model = Get-LambekForms -Name $Language
    $first = [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $English).Path)
    $second = [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Other).Path)
    if ($first.Count -ne $second.Count) { throw "The two sides do not have as many lines ($($first.Count), $($second.Count))." }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $words = [LambekLogicWords]::Learn($englishForms, $model, $first, $second, $Least, $Longest)
    $hashes = @($English, $Other | ForEach-Object { "$(Split-Path $_ -Leaf) $((Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant())" })
    $source = "Tatoeba v2023-04-12, OPUS (CC BY 2.0 FR), $($first.Count) pairs, least $Least, longest $Longest; $($hashes -join '; ')"
    Write-Host "Read $($first.Count) pairs ($([math]::Round($clock.Elapsed.TotalSeconds))s)."
}
$treebanks = @($Treebank | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
$copulas = [LambekLogicWords]::Copulas([string[]] $treebanks)
$words = [LambekLogicWord[]] @(@($words) + @($copulas))
$source += "; copulas of $(@($treebanks | ForEach-Object { "$(Split-Path $_ -Leaf) $((Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant())" }) -join ', ')"
[LambekLogicWords]::Write($out, $source, $words)
foreach ($group in @($words | Group-Object Kind)) { Write-Host ("  {0,-5} {1}" -f $group.Name, (@($group.Group | Sort-Object { - $_.Together } | ForEach-Object { "$($_.Word) ($($_.Together)/$($_.Seen))" }) -join ', ')) }
