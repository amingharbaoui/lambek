#Requires -Version 7.6
<#
.SYNOPSIS
    Lambek learns the words of its languages as Wiktionary says them, to read the words its treebanks never met
    ("abbaia" is "abbaiare", "pesce" a noun): engine/Lambek/Data/Forms/<language>.lexicon.gz. Nothing in it is written by hand.
.DESCRIPTION
    The words come from Wiktionary (CC BY-SA 4.0 and GFDL), as Wiktextract reads it, the English edition, which names
    the words of every language with the same English tags; kaikki.org gives them a file for each language:
      https://kaikki.org/dictionary/<Language>/kaikki.org-dictionary-<Language>.jsonl.gz
    Each word is taken from its headword, its senses that are the form of another word ("abbaia": form of "abbaiare",
    third person singular present indicative) and its tables of forms (Native/Lexicon.cs).

    How Wiktionary's names turn into the tags of the treebanks is learned once for every language, from the words
    Wiktionary and the treebanks both have: a part of speech of Wiktionary is the UPOS most of its words are tagged
    with; a tag is the one feature that tells its words apart the most (met with nine in ten of them, at most half as
    often without it), learned from the forms Wiktionary gives one reading of; a tag that is no feature is kept when
    most of its words are the forms of the lemma it gives them ("form-of"), and a word with any other tag is left out
    ("diminutive": another word). A word is kept when its language is seen written so in its translated sentences
    (Tatoeba): a table may write what text does not (the stress of "abbaiare").

    When the forms model reads a word as one of the parts of speech the lexicon gives it, the word takes the lemma the
    lexicon gives it; a word the treebanks never met, read as none of them, takes the lexicon's reading nearest to the
    tagger's.
.EXAMPLE
    ./tools/Learn-LambekLexicon.ps1 -Wiktionary ../wikt -Treebank ../ud -Tatoeba ../tatoeba
#>
param(
    # The files of kaikki.org, named kaikki.org-dictionary-<Language>.jsonl.gz or <Language>.jsonl.gz
    [Parameter(Mandatory)]
    [string] $Wiktionary,

    # The treebanks of each language, <language>/<treebank>-ud-train.conllu, those of its forms model
    [Parameter(Mandatory)]
    [string] $Treebank,

    # The sentences of each language, Tatoeba.<pair>.<language> (Moses format, one sentence a line)
    [Parameter(Mandatory)]
    [string] $Tatoeba,

    # The treebanks of each forms model
    [System.Collections.IDictionary] $Treebanks = [ordered]@{
        fr = @('fr_gsd', 'fr_rhapsodie', 'fr_parisstories')
        en = @('en_ewt')
        de = @('de_gsd')
        es = @('es_ancora', 'es_gsd')
        nl = @('nl_alpino', 'nl_lassysmall')
        pt = @('pt_bosque', 'pt_petrogold', 'pt_porttinari', 'pt_dantestocks')
        it = @('it_markit', 'it_twittiro', 'it_parlamint')
    },

    # The least words a name of Wiktionary must be met with to be turned into a tag
    [int] $Least = 30,

    [string] $OutDirectory = (Join-Path $PSScriptRoot '../engine/Lambek/Data/Forms')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
$names = @{ fr = 'French'; en = 'English'; de = 'German'; es = 'Spanish'; nl = 'Dutch'; pt = 'Portuguese'; it = 'Italian' }
$pairs = @{ fr = 'en-fr'; en = 'en-fr'; de = 'de-en'; es = 'en-es'; nl = 'en-nl'; pt = 'en-pt'; it = 'en-it' }

# The words of Wiktionary of each language, read once and kept in a file apart (all of them together do not hold in
# memory)
$work = Join-Path ([IO.Path]::GetTempPath()) "lambek-lexicon-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
foreach ($language in $Treebanks.Keys) {
    $file = @(Get-ChildItem -LiteralPath $Wiktionary -File | Where-Object { $_.Name -in "kaikki.org-dictionary-$($names[$language]).jsonl.gz", "$($names[$language]).jsonl.gz" })[0]
    if (-not $file) { throw "No file of Wiktextract for $($names[$language]) in $Wiktionary." }
    $raws = [LambekLexicon]::Extract($file.FullName, $language)
    [LambekLexicon]::WriteRaw((Join-Path $work "$language.raw.gz"), $raws)
    Write-Host "$($names[$language]): $($raws.Count) words of Wiktionary, $(Split-Path -Path $file.FullName -Leaf) $((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
    $raws = $null
    [GC]::Collect()
}

# How Wiktionary's names turn into the tags of the treebanks, from the words both have (only those are read here)
$learning = [System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[System.Collections.Generic.List[LambekLexicon+Raw], System.Collections.Generic.List[LambekTreebankWord[]]]]]::new()
foreach ($language in $Treebanks.Keys) {
    $sentences = [System.Collections.Generic.List[LambekTreebankWord[]]]::new()
    foreach ($name in $Treebanks[$language]) { $sentences.AddRange([LambekTreebank]::Read((Join-Path $Treebank "$language/$name-ud-train.conllu"))) }
    $forms = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($sentence in $sentences) { foreach ($treebankWord in $sentence) { [void] $forms.Add($treebankWord.Form.ToLowerInvariant()) } }
    $met = [LambekLexicon]::ReadRaw((Join-Path $work "$language.raw.gz"), $forms)
    $learning.Add([System.Collections.Generic.KeyValuePair[System.Collections.Generic.List[LambekLexicon+Raw], System.Collections.Generic.List[LambekTreebankWord[]]]]::new($met, $sentences))
}
$mapping = [LambekLexicon]::Learn($learning, $Least)
Write-Host "Parts of speech: $(@($mapping.Pos.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
Write-Host "Tags: $(@($mapping.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
Write-Host "Kept without a tag: $($mapping.Neutral -join ', ')"

# The lexicon of each language, of the words it is seen written so
$word = [regex]::new("\p{L}+(?:['’-]\p{L}+)*")
foreach ($language in $Treebanks.Keys) {
    $said = Join-Path $Tatoeba "Tatoeba.$($pairs[$language]).$language"
    $attested = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadLines($said)) { foreach ($match in $word.Matches($line.ToLowerInvariant())) { [void] $attested.Add($match.Value) } }
    $lexicon = [LambekLexicon]::Build([LambekLexicon]::ReadRaw((Join-Path $work "$language.raw.gz")), $mapping, $attested)
    $lexicon.Source = "Wiktionary (CC BY-SA 4.0), English edition, by Wiktextract (kaikki.org); kept as written in $(Split-Path -Path $said -Leaf)"
    $out = Join-Path $OutDirectory "$language.lexicon.gz"
    $lexicon.Save($out)
    Write-Host "Written $out ($($lexicon.Forms.Count) forms)"
    $lexicon = $null
    [GC]::Collect()
}
Remove-Item -LiteralPath $work -Recurse -Force
