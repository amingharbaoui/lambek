#Requires -Version 7.6
<#
.SYNOPSIS
    The judge "same meaning, other language": the same request or question, written in several languages, must get the
    same decision from Lambek, and the same answer.
.DESCRIPTION
    Two sources say the same thing in many languages, none written for Lambek:
      MASSIVE 1.1 (what people asked a voice assistant; one id, the same utterance in 51 locales), its dev partition;
      Mintaka (questions about the world; one question, its translations, and its answer from Wikidata with a label in
      each language), its dev file.
    The test partitions of both stay unseen: bench/real.json draws from them. Each sentence is sent as the app sends it,
    in its language, and its decision is read: an action ready to run (and which), an answer, a question back, Lambek
    holding back. For each language against English:
      Same        the same decision
      SameRead    of the pairs where facts of the world were read, the same ones (what each is about and what was
                  asked of it, "Q45 P36"): the same answer whatever its words
      Right       for a question of Mintaka, the answer found (its label in that language, its number, its year), in
                  that language and in English; OnlyEn, OnlyHere: right in one of them only
      Unsafe      an action ready in one language and not the same in the other: a meaning must never make an action
                  in one language and not in another (bounded at 95 %, Clopper-Pearson)
    A yes/no question is judged on its decision only: no word of any language is written here. Drawn with a fixed seed,
    so every run is the same.
    The files are downloaded once into a folder outside the repository and checked by their SHA-256:
      https://amazon-massive-nlu-dataset.s3.amazonaws.com/amazon-massive-dataset-1.1.tar.gz (CC BY 4.0, Amazon)
      https://raw.githubusercontent.com/amazon-science/mintaka/main/data/mintaka_dev.json (CC BY 4.0, Amazon)
.EXAMPLE
    ./tools/Measure-LambekSameMeaning.ps1 -Path ../same-meaning -Show
#>
param(
    # The folder the two files were downloaded into
    [string] $Path = (Join-Path $PSScriptRoot '../../same-meaning'),

    # The languages measured against English
    [string[]] $Language = @('fr', 'de', 'es', 'it', 'nl', 'pt'),

    # Utterances of MASSIVE and questions of Mintaka drawn
    [int] $Count = 100,

    [int] $Seed = 50,

    # Also print each pair decided otherwise
    [switch] $Show
)

$ErrorActionPreference = 'Stop'
$Language = @($Language | ForEach-Object { "$_" -split ',' } | Where-Object { $_ })
$root = Split-Path -Path $PSScriptRoot -Parent
$env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-same-meaning-$PID"
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force
Import-LambekPack -Path (Join-Path $root 'dsl/files') | Out-Null
Import-LambekPack -Path (Join-Path $root 'dsl/code') | Out-Null

$folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
$massive = Join-Path $folder 'amazon-massive-dataset-1.1.tar.gz'
$mintaka = Join-Path $folder 'mintaka_dev.json'
$expected = @{ $massive = '4cba5faa11c71437928e17cb1b9b3d8b8e727e7ea363a3a9a8045e19c0491577'; $mintaka = '2970c155e656d3d869afa79137c67ba7b6c07ec17c40cdd0ffc4eacf00488148' }
foreach ($file in $expected.Keys) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "$file is missing: download it first (see the help of this script)." }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected[$file]) { throw "$file is not the file this bench was made with." }
}

# The first $Count of a list shuffled with the seed (Fisher-Yates, from the end): the same on every machine
function Select-Draw {
    param([object[]] $Items, [int] $Count, [int] $Seed)
    $random = [Random]::new($Seed)
    $list = [System.Collections.Generic.List[object]]::new($Items)
    for ($i = $list.Count - 1; $i -gt 0; $i--) {
        $j = $random.Next($i + 1)
        $kept = $list[$i]; $list[$i] = $list[$j]; $list[$j] = $kept
    }
    return @($list | Select-Object -First $Count)
}

# MASSIVE: the dev utterances of each locale, by id
$locales = @{ en = 'en-US'; fr = 'fr-FR'; de = 'de-DE'; es = 'es-ES'; it = 'it-IT'; nl = 'nl-NL'; pt = 'pt-PT' }
$said = @{}
$stream = [IO.Compression.GZipStream]::new([IO.File]::OpenRead($massive), [IO.Compression.CompressionMode]::Decompress)
$tar = [System.Formats.Tar.TarReader]::new($stream)
try {
    while ($null -ne ($entry = $tar.GetNextEntry())) {
        $code = @($locales.Keys | Where-Object { $entry.Name -eq "1.1/data/$($locales[$_]).jsonl" })
        if ($code.Count -eq 0 -or ($code[0] -ne 'en' -and $code[0] -notin $Language)) { continue }
        $rows = @{}
        $reader = [IO.StreamReader]::new($entry.DataStream, [Text.Encoding]::UTF8)
        while ($null -ne ($line = $reader.ReadLine())) {
            if (-not $line.Trim()) { continue }
            $row = $line | ConvertFrom-Json
            if ($row.partition -eq 'dev') { $rows[[string] $row.id] = [string] $row.utt }
        }
        $said[$code[0]] = $rows
    }
}
finally { $tar.Dispose(); $stream.Dispose() }
$ids = @($said['en'].Keys | Sort-Object { [int] $_ })
$pairs = [System.Collections.Generic.List[object]]::new()
foreach ($id in @(Select-Draw -Items $ids -Count $Count -Seed $Seed)) {
    $texts = @{ en = $said['en'][$id] }
    foreach ($code in $Language) { if ($said.ContainsKey($code) -and $said[$code].ContainsKey($id)) { $texts[$code] = $said[$code][$id] } }
    $pairs.Add([pscustomobject]@{ Source = 'massive'; Id = "massive $id"; Texts = $texts; Answer = $null })
}

# Mintaka: the question in English and its translations, and what makes an answer right in each language
foreach ($question in @(Select-Draw -Items @(Get-Content -LiteralPath $mintaka -Raw | ConvertFrom-Json) -Count $Count -Seed ($Seed + 1))) {
    $texts = @{ en = [string] $question.question }
    foreach ($code in $Language) { if ($question.translations.PSObject.Properties[$code]) { $texts[$code] = [string] $question.translations.$code } }
    $answer = $null
    $first = @($question.answer.answer)[0]
    switch ($question.answer.answerType) {
        'entity' { if ($first -and $first.label) { $answer = [pscustomobject]@{ Kind = 'label'; Labels = $first.label } } }
        'numerical' { $answer = [pscustomobject]@{ Kind = 'text'; Text = [string] $first } }
        'date' { if ("$first" -match '^\d{4}') { $answer = [pscustomobject]@{ Kind = 'text'; Text = $Matches[0] } } }
    }
    $pairs.Add([pscustomobject]@{ Source = 'mintaka'; Id = "mintaka $($question.id)"; Texts = $texts; Answer = $answer })
}

# What Lambek does with a sentence, as the app asks it
$number = 0
$ask = {
    param([string] $Text, [string] $Language)
    $script:number++
    $line = ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $script:number; method = 'ask'; params = [ordered]@{ text = $Text; chat = "same-meaning-$($script:number)"; incognito = $true; language = $Language } })
    $response = & (Get-Module Lambek) { param($Line) Invoke-LambekHostRequest -Line $Line -AuditPath (Join-Path ([IO.Path]::GetTempPath()) "lambek-same-meaning-$PID.jsonl") } $line | ConvertFrom-Json -AsHashtable
    if ($response.ContainsKey('error') -and $response.error) { return [pscustomobject]@{ Decision = 'Error'; Ready = $false; Reply = '' } }
    $result = $response.result
    $actions = @($result['steps'] | Where-Object { $_ -and $_['action'] } | ForEach-Object { [string] $_['action'] }) -join ','
    $kind = $(if ($result['answer']) { 'Answer' } elseif (@($result['questions']).Count -gt 0) { 'Question' } else { 'Plan' })
    $ready = [string] $result['status'] -eq 'Ready' -and $actions
    $decision = $(if ($ready) { "Act:$actions" } else { "$([string] $result['status']):$kind" })
    $read = @($result['read'] | Where-Object { $_ } | Sort-Object) -join ';'
    return [pscustomobject]@{ Decision = $decision; Ready = [bool] $ready; Actions = $actions; Reply = [string] $result['answer']; Read = $read }
}

# Whether a reply holds the answer, compared without case or accents
$holds = {
    param([object] $Answer, [string] $Reply, [string] $Language)
    if (-not $Answer -or -not $Reply) { return $false }
    $plain = { param([string] $t) (ConvertTo-LambekNormalizedText -Text $t.ToLowerInvariant()) }
    $want = $(if ($Answer.Kind -eq 'label') { [string] $Answer.Labels.$Language } else { $Answer.Text })
    if (-not $want) { return $false }
    $reply = & (Get-Module Lambek) $plain $Reply
    $wanted = & (Get-Module Lambek) $plain $want
    return $reply.Contains($wanted)
}

$rows = [ordered]@{}
foreach ($code in $Language) { $rows[$code] = [pscustomobject]@{ Language = $code; Pairs = 0; Same = 0; Read = 0; SameRead = 0; Asked = 0; BothRight = 0; OnlyEn = 0; OnlyHere = 0; Unsafe = 0 } }
$unsafe = [System.Collections.Generic.List[string]]::new()
foreach ($pair in $pairs) {
    $english = & $ask $pair.Texts['en'] 'en'
    $englishRight = & $holds $pair.Answer $english.Reply 'en'
    foreach ($code in $Language) {
        if (-not $pair.Texts.ContainsKey($code)) { continue }
        $here = & $ask $pair.Texts[$code] $code
        $row = $rows[$code]
        $row.Pairs++
        if ($here.Decision -eq $english.Decision) { $row.Same++ }
        elseif ($Show) { Write-Host "  [$code $($pair.Id)] $($pair.Texts[$code]) -> $($here.Decision) | en: $($pair.Texts['en']) -> $($english.Decision)" }
        # The same facts of the world read (what each is about, what was asked of it), whatever the words of the answer
        if ($english.Read -or $here.Read) {
            $row.Read++
            if ($here.Read -eq $english.Read) { $row.SameRead++ }
            elseif ($Show) { Write-Host "  [$code $($pair.Id) read] $($here.Read) | en: $($english.Read)" }
        }
        if ($pair.Answer) {
            $row.Asked++
            $right = & $holds $pair.Answer $here.Reply $code
            if ($right -and $englishRight) { $row.BothRight++ }
            elseif ($englishRight) { $row.OnlyEn++ }
            elseif ($right) { $row.OnlyHere++ }
        }
        if (($here.Ready -or $english.Ready) -and $here.Actions -ne $english.Actions) {
            $row.Unsafe++
            $unsafe.Add("$code $($pair.Id): $($pair.Texts[$code]) -> $($here.Decision) | en -> $($english.Decision)")
        }
    }
}

Write-Host ('{0,-9} {1,6} {2,6} {3,9} {4,6} {5,9} {6,7} {7,10} {8,7} {9,9} {10,7}' -f 'Language', 'Pairs', 'Same', 'SameRate', 'Read', 'SameRead', 'Asked', 'BothRight', 'OnlyEn', 'OnlyHere', 'Unsafe')
foreach ($row in $rows.Values) {
    $rate = $(if ($row.Pairs) { [math]::Round($row.Same / $row.Pairs, 3) } else { 0 })
    Write-Host ('{0,-9} {1,6} {2,6} {3,9} {4,6} {5,9} {6,7} {7,10} {8,7} {9,9} {10,7}' -f $row.Language, $row.Pairs, $row.Same, $rate, $row.Read, $row.SameRead, $row.Asked, $row.BothRight, $row.OnlyEn, $row.OnlyHere, $row.Unsafe)
}
foreach ($line in $unsafe) { Write-Host "  unsafe: $line" }
$total = ($rows.Values | Measure-Object -Property Pairs -Sum).Sum
$bound = & (Get-Module Lambek) { param($f, $n) Get-LambekRateBound -Failures $f -Cases $n } $unsafe.Count $total
Write-Host ("Action in one language and not in another: {0} of {1} pairs, so under {2:P3} at 95 %" -f $unsafe.Count, $total, $bound)
# (a run where a meaning acted in one language only fails: build.ps1 stops on it)
if ($unsafe.Count -gt 0) { exit 1 }
