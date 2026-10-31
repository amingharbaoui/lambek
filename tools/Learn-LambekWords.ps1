#Requires -Version 7.6
<#
.SYNOPSIS
    Lambek learns words on its own by reading plain text (step 4.6 of the roadmap), and writes down only what is
    confirmed: engine/Lambek/Data/Forms/<language>.learned.gz.
.DESCRIPTION
    The texts of tools/corpus.json (downloaded by tools/Get-LambekCorpus.ps1) are read in the order of the file, every
    sentence through the forms model learned from the treebanks. Every word the model never saw is noted with how it
    was read in each sentence; a word is written down only when it was met in several sentences, read the same way in
    most of them, is no name, and its lemma is sure (Native/Reading.cs). Never from what Lambek itself said: only these
    texts. The notebook is plain text (gzip): one word a line, with how often it was met and where.

    Then the notebook must earn its place: the forms models are measured with it and without it on treebanks they
    never learned from, and on the conjugations of UniMorph; a figure that falls refuses it (-Force writes it anyway,
    to look at it).
.EXAMPLE
    ./tools/Learn-LambekWords.ps1 -Language fr -Corpus ../lambek-corpus
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('fr', 'en')]
    [string] $Language,

    # The folder of the texts (tools/Get-LambekCorpus.ps1)
    [string] $Corpus = (Join-Path $PSScriptRoot '../../lambek-corpus'),

    [string] $OutFile = (Join-Path $PSScriptRoot "../engine/Lambek/Data/Forms/$Language.learned.gz"),

    # Treebanks never learned from, to measure the notebook on (CoNLL-U): by default the test treebanks of bench/forms,
    # and the judges of tools/corpus.json found in the folder of the texts
    [string[]] $Judge,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'corpus.json') -Raw | ConvertFrom-Json
$folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Corpus)
$model = [LambekForms]::Load([IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../engine/Lambek/Data/Forms/$Language.forms.gz")))

$reader = [LambekSelfReader]::new($model)
$clock = [Diagnostics.Stopwatch]::StartNew()
$read = [System.Collections.Generic.List[string]]::new()
foreach ($source in @($manifest.Sources | Where-Object Language -EQ $Language)) {
    $text = Join-Path $folder $source.Text
    if (-not (Test-Path -LiteralPath $text -PathType Leaf)) { throw "$($source.Name) is not in $($folder): run tools/Get-LambekCorpus.ps1 first." }
    $reader.Read($source.Name, [LambekCorpusText]::Sentences($text, $source.Shape))
    $hash = (Get-FileHash -LiteralPath (Join-Path $folder $source.File) -Algorithm SHA256).Hash.ToLowerInvariant()
    $read.Add("$($source.Name) $hash")
    Write-Host ("  {0,-28} {1,10:N0} sentences, {2,12:N0} words read so far ({3:N0}s)" -f $source.Name, $reader.Sentences, $reader.Words, $clock.Elapsed.TotalSeconds)
}
$words = $reader.Decide()
Write-Host "Written down: $($words.Count) words ($([math]::Round($clock.Elapsed.TotalSeconds))s)."
foreach ($group in @($words | Group-Object Why)) { Write-Host ("  {0,-12} {1}" -f $group.Name, $group.Count) }

# The notebook earns its place: nothing measured may fall with it
$judges = @($manifest.Judges | Where-Object Language -EQ $Language)
if (-not $PSBoundParameters.ContainsKey('Judge')) {
    $tests = @(Get-ChildItem -Path (Join-Path $PSScriptRoot "../bench/forms/$($Language)_*.conllu") -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $others = @($judges | Where-Object Kind -EQ 'treebank' | ForEach-Object { Join-Path $folder $_.File } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    $Judge = $tests + $others
}
$model = & (Get-Module Lambek) { param($l) Get-LambekFormModel -Language $l } $Language
$failed = $false
$compare = {
    param($what, $name, $without, $with)
    $fell = $with -lt $without
    if ($fell) { $script:failed = $true }
    Write-Host ("  {0,-34} {1,-12} {2} -> {3}{4}" -f $what, $name, $without, $with, $(if ($fell) { '  (falls)' } else { '' }))
}
foreach ($path in $Judge) {
    $model.ClearLearned()
    $without = Invoke-LambekFormBenchmark -Path $path -Language $Language
    $model.AddLearned($words)
    $with = Invoke-LambekFormBenchmark -Path $path -Language $Language
    foreach ($name in 'Upos', 'Lemma', 'UnseenLemma', 'UnseenUpos', 'Speak', 'SpeakUnseen') { & $compare (Split-Path $path -Leaf) $name $without.$name $with.$name }
}

# The conjugations of UniMorph, of the verbs met in the texts (the words of today, not those of old books only): each
# verb said in each person and tense, its lemma seen in the treebanks or not
$cells = @{
    fr = @{
        'V;IND;PRS;1;SG' = 'Mood=Ind|Number=Sing|Person=1|Tense=Pres'; 'V;IND;PRS;2;SG' = 'Mood=Ind|Number=Sing|Person=2|Tense=Pres'
        'V;IND;PRS;3;SG' = 'Mood=Ind|Number=Sing|Person=3|Tense=Pres'; 'V;IND;PRS;1;PL' = 'Mood=Ind|Number=Plur|Person=1|Tense=Pres'
        'V;IND;PRS;2;PL' = 'Mood=Ind|Number=Plur|Person=2|Tense=Pres'; 'V;IND;PRS;3;PL' = 'Mood=Ind|Number=Plur|Person=3|Tense=Pres'
        'V;IND;PST;3;SG;IPFV' = 'Mood=Ind|Number=Sing|Person=3|Tense=Imp'; 'V;IND;FUT;3;SG' = 'Mood=Ind|Number=Sing|Person=3|Tense=Fut'
        'V;COND;3;SG' = 'Mood=Cnd|Number=Sing|Person=3'; 'V;SBJV;PRS;3;SG' = 'Mood=Sub|Number=Sing|Person=3|Tense=Pres'
        'V.PTCP;PST' = 'Gender=Masc|Number=Sing|VerbForm=Part'
    }
    en = @{
        'V;PRS;3;SG' = 'Mood=Ind|Number=Sing|Person=3|Tense=Pres'; 'V;PST' = 'Mood=Ind|Tense=Past'
        'V;V.PTCP;PST' = 'Tense=Past|VerbForm=Part'; 'V;V.PTCP;PRS' = 'Tense=Pres|VerbForm=Part'
    }
}[$Language]
# (not $judge: names do not tell capitals apart, and $Judge is the list of treebanks)
foreach ($conjugations in @($judges | Where-Object Kind -EQ 'unimorph')) {
    $path = Join-Path $folder $conjugations.File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $rows = [System.Collections.Generic.List[string[]]]::new()
    foreach ($line in [IO.File]::ReadLines($path)) {
        $parts = $line.Split("`t")
        if ($parts.Length -ge 3 -and $cells.ContainsKey($parts[2]) -and $parts[0] -cmatch '^\p{Ll}+$' -and $reader.Met($parts[0]) -and $reader.Met($parts[1])) { $rows.Add($parts) }
    }
    $said = @{}
    foreach ($state in 'without', 'with') {
        if ($state -eq 'without') { $model.ClearLearned() } else { $model.AddLearned($words) }
        $count = @{ Seen = 0; SeenRight = 0; New = 0; NewRight = 0 }
        foreach ($row in $rows) {
            $right = @($model.Inflect($row[0], 'VERB', $cells[$row[2]]))[0] -ceq $row[1]
            if ($model.Lemmas.Contains($row[0])) { $count.Seen++; if ($right) { $count.SeenRight++ } } else { $count.New++; if ($right) { $count.NewRight++ } }
        }
        $said[$state] = @{ Seen = [math]::Round($count.SeenRight / [math]::Max(1, $count.Seen), 4); New = [math]::Round($count.NewRight / [math]::Max(1, $count.New), 4) }
    }
    & $compare "$($conjugations.Name) ($($rows.Count))" 'Seen' $said.without.Seen $said.with.Seen
    & $compare "$($conjugations.Name) ($($rows.Count))" 'NeverSeen' $said.without.New $said.with.New
}
& (Get-Module Lambek) { param($l) $script:FormModels.Remove($l) } $Language
if ($failed -and -not $Force) { throw 'A figure falls with what was learned: the notebook is not written.' }

$header = "What Lambek learned on its own from plain text, $Language, from: " + ($read -join '; ')
[LambekSelfReader]::Write([IO.Path]::GetFullPath($OutFile), $words, $header)
Write-Host "Written $OutFile, SHA-256 $((Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant())"
