#Requires -Version 7.4
<#
.SYNOPSIS
    Draws at random the real sentences of bench/real.json: what people asked a voice assistant (MASSIVE, French and
    English) and questions about the world with their answers (Mintaka), none of them written for Lambek.
.DESCRIPTION
    The test files of MASSIVE 1.1 and Mintaka are downloaded once into a folder of their own (never into the
    repository), their SHA-256 compared with the ones written in tools/real.json, and the sentences drawn with the seed
    written there: the same seed gives the same sentences on every machine, so nobody chose them. One sentence in two
    goes to the calibration split, the other to the test split.

    With bench/real.json there, the tool checks that its sentences are the ones drawn, in the same order and splits.
    With -Write (and no bench/real.json, or -Force), it writes the cases with what can be expected without reading
    them: the answer of Mintaka, and for an intent of MASSIVE that Lambek has no hold on (an alarm, music, the
    weather, the news...), that Lambek says it cannot. What the other sentences expect (a question of general
    knowledge, a calculation, the time) is written by hand afterwards, before Lambek is measured on them.
    Licences: MASSIVE CC BY 4.0 (Amazon), Mintaka CC BY 4.0 (Amazon).
.EXAMPLE
    ./tools/Get-LambekRealSentences.ps1
.EXAMPLE
    ./tools/Get-LambekRealSentences.ps1 -Write -Force
#>
param(
    # The folder the sources go into (outside the repository)
    [string] $Path = (Join-Path $PSScriptRoot '../../lambek-corpus'),

    # The bench the sentences are written to, or checked against
    [string] $Bench = (Join-Path $PSScriptRoot '../bench/real.json'),

    [switch] $Write,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'real.json') -Raw -Encoding utf8 | ConvertFrom-Json
$folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$benchPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Bench)

# The sources, downloaded once and checked
$files = @{}
foreach ($source in @($manifest.Sources)) {
    $file = Join-Path $folder $source.File
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Host "Downloading $($source.Name) from $($source.Url)"
        Invoke-WebRequest -Uri $source.Url -OutFile $file -UseBasicParsing
    }
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $source.Sha256) { throw "$($source.Name) is not the file the sentences were drawn from (SHA-256 $hash)." }
    $files[$source.Name] = $file
}

# The test utterances of MASSIVE in one locale, in the order of their id
function Read-MassiveTest {
    param([string] $Archive, [string] $Member)
    $stream = [IO.Compression.GZipStream]::new([IO.File]::OpenRead($Archive), [IO.Compression.CompressionMode]::Decompress)
    $tar = [System.Formats.Tar.TarReader]::new($stream)
    $rows = [System.Collections.Generic.List[object]]::new()
    try {
        while ($null -ne ($entry = $tar.GetNextEntry())) {
            if ($entry.Name -ne $Member) { continue }
            $reader = [IO.StreamReader]::new($entry.DataStream, [Text.Encoding]::UTF8)
            while ($null -ne ($line = $reader.ReadLine())) {
                if (-not $line.Trim()) { continue }
                $row = $line | ConvertFrom-Json
                if ($row.partition -eq 'test') { $rows.Add($row) }
            }
            break
        }
    }
    finally { $tar.Dispose(); $stream.Dispose() }
    if ($rows.Count -eq 0) { throw "$Member is not in $Archive." }
    return @($rows | Sort-Object { [int] $_.id })
}

# The first $Count of a list shuffled with the seed (Fisher-Yates, from the end): the same on every machine
function Select-LambekDraw {
    param([object[]] $Items, [int] $Count, [int] $Seed)
    $random = [Random]::new($Seed)
    $order = [int[]] (0..($Items.Count - 1))
    $drawn = [System.Collections.Generic.List[object]]::new()
    for ($i = $order.Count - 1; $i -ge 0 -and $drawn.Count -lt $Count; $i--) {
        $j = $random.Next($i + 1)
        $swap = $order[$i]; $order[$i] = $order[$j]; $order[$j] = $swap
        $drawn.Add($Items[$order[$i]])
    }
    return $drawn.ToArray()
}

# What a sentence of MASSIVE expects when its intent says it without reading it: Lambek has no hold on it (an order
# for elsewhere, the weather, the news, a recommendation), so it must say it cannot, and never do anything
$elsewhere = @($manifest.Abstain)
$numbers = [cultureinfo]::InvariantCulture

function Get-LambekMintakaExpect {
    param([object] $Question, [string] $Language)
    $answer = $Question.answer
    $wanted = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @($answer.answer)) {
        switch ($answer.answerType) {
            'entity' {
                $labels = @($value.label.$Language, $value.label.en, $value.label.fr | Where-Object { $_ } | Select-Object -Unique)
                $wanted.Add($labels -join '|')
            }
            'numerical' {
                $number = [double] $value
                $plain = $number.ToString('0.##########', $numbers)
                $forms = @($plain, $number.ToString('#,0.##########', $numbers), ($number.ToString('#,0.##########', $numbers) -replace ',', ' '))
                $words = $manifest.NumberWords.$Language
                if ($number -eq [math]::Floor($number) -and $number -ge 0 -and $number -lt @($words).Count) { $forms += $words[[int] $number] }
                $wanted.Add((@($forms | Select-Object -Unique) -join '|'))
            }
            'date' {
                $text = [string] $value
                if ($text -match '^(\d{4})-(\d{2})-(\d{2})$') {
                    $day = [datetime]::new([int] $Matches[1], [int] $Matches[2], [int] $Matches[3])
                    $month = $manifest.Months.$Language[$day.Month - 1]
                    $first = $(if ($Language -eq 'fr' -and $day.Day -eq 1) { '1er' } else { "$($day.Day)" })
                    $forms = @($text, "$first $month $($day.Year)")
                    if ($Language -eq 'en') { $forms += "$month $($day.Day), $($day.Year)" }
                    $wanted.Add(($forms -join '|'))
                }
                else { $wanted.Add($text) }
            }
            'boolean' { $wanted.Add($(if ($value) { $manifest.Yes.$Language } else { $manifest.No.$Language })) }
            default { $wanted.Add([string] $value) }
        }
    }
    return [ordered]@{ Reply = 'answer'; Contains = $wanted.ToArray() }
}

$cases = [System.Collections.Generic.List[object]]::new()
$number = 0
# What an earlier draw took is never drawn again (a draw added later only adds sentences)
$taken = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($draw in @($manifest.Draws)) {
    # One sentence in two to each split, or every one to the split the draw names
    $splitOf = { param($n) if ($draw.PSObject.Properties['Split']) { $draw.Split } elseif ($n % 2 -eq 1) { 'calibration' } else { 'test' } }
    $source = @($manifest.Sources | Where-Object Name -EQ $draw.Source)[0]
    if ($source.Kind -eq 'massive') {
        $items = @(Read-MassiveTest -Archive $files[$source.Name] -Member $draw.Member | Where-Object { -not $taken.Contains("$($draw.Member)|$($_.id)") })
        $drawn = Select-LambekDraw -Items $items -Count $draw.Count -Seed ([int] $manifest.Seed + [int] $draw.Offset)
        foreach ($row in $drawn) {
            [void] $taken.Add("$($draw.Member)|$($row.id)")
            $number++
            $expect = $null
            if ($row.intent -in $elsewhere) { $expect = [ordered]@{ Reply = 'abstain' } }
            $cases.Add([ordered]@{
                    Id       = 'R{0:000}' -f $number
                    Split    = & $splitOf $number
                    Language = $draw.Language
                    Tags     = @('massive', $row.scenario)
                    Text     = [string] $row.utt
                    Expect   = $expect
                    Source   = [ordered]@{ Corpus = $source.Name; Id = [string] $row.id; Intent = [string] $row.intent }
                })
        }
    }
    else {
        $items = @((Get-Content -LiteralPath $files[$source.Name] -Raw -Encoding utf8 | ConvertFrom-Json) | Where-Object { @($_.answer.answer | Where-Object { $null -ne $_ }).Count -gt 0 -and -not $taken.Contains("mintaka|$($draw.Language)|$($_.id)") } | Sort-Object id)
        $drawn = Select-LambekDraw -Items $items -Count $draw.Count -Seed ([int] $manifest.Seed + [int] $draw.Offset)
        foreach ($question in $drawn) {
            [void] $taken.Add("mintaka|$($draw.Language)|$($question.id)")
            $number++
            $text = $(if ($draw.Language -eq 'en') { $question.question } else { $question.translations.($draw.Language) })
            $cases.Add([ordered]@{
                    Id       = 'R{0:000}' -f $number
                    Split    = & $splitOf $number
                    Language = $draw.Language
                    Tags     = @('mintaka', $question.complexityType)
                    Text     = [string] $text
                    Expect   = Get-LambekMintakaExpect -Question $question -Language $draw.Language
                    Source   = [ordered]@{ Corpus = $source.Name; Id = [string] $question.id; Complexity = [string] $question.complexityType; Category = [string] $question.category }
                })
        }
    }
}

if ($Write) {
    if ((Test-Path -LiteralPath $benchPath) -and -not $Force) { throw "$benchPath is there: -Force writes it again, and loses what was written by hand." }
    $content = [ordered]@{
        Version     = '1.0'
        Description = $manifest.Bench
        Now         = $manifest.Now
        TestHash    = ''
        Cases       = $cases.ToArray()
    }
    [IO.File]::WriteAllText($benchPath, (ConvertTo-Json -InputObject $content -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
    $left = @($cases | Where-Object { -not $_.Expect }).Count
    Write-Host "Wrote $($cases.Count) sentences to $benchPath ($left to write the expectation of by hand)."
    return
}

# The bench is checked: the same sentences, drawn the same way
if (-not (Test-Path -LiteralPath $benchPath)) { throw "$benchPath is not there: -Write writes it." }
$written = @((Get-Content -LiteralPath $benchPath -Raw -Encoding utf8 | ConvertFrom-Json).Cases)
$differ = 0
for ($i = 0; $i -lt [math]::Max($written.Count, $cases.Count); $i++) {
    $was = $(if ($i -lt $written.Count) { $written[$i] })
    $now = $(if ($i -lt $cases.Count) { $cases[$i] })
    $same = $was -and $now -and $was.Id -eq $now.Id -and $was.Split -eq $now.Split -and $was.Language -eq $now.Language -and
    $was.Text -ceq $now.Text -and $was.Source.Corpus -eq $now.Source.Corpus -and $was.Source.Id -eq $now.Source.Id
    if (-not $same) {
        $differ++
        Write-Warning "$(if ($was) { $was.Id } else { $now.Id }): not the sentence drawn."
    }
}
if ($differ -gt 0) { throw "$differ sentence(s) of $benchPath are not the ones drawn with seed $($manifest.Seed)." }
Write-Host "The $($cases.Count) sentences of $benchPath are the ones drawn with seed $($manifest.Seed)."
