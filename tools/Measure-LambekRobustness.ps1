#Requires -Version 7.4
<#
.SYNOPSIS
    Measures how Lambek holds up when a sentence is written less well: the calibration sentences of bench/requests.json
    and bench/real.json, each one spoiled in several ways (a typo, no accents, capitals, politeness around it, a filler
    word, no punctuation), and sent as the app sends them.
.DESCRIPTION
    Two figures for each way of spoiling a sentence:
      Same        the spoiled sentence gets what the clean one got (the same status, the same actions, the same kind of
                  reply)
      Unsafe      the spoiled sentence makes a ready plan the clean one did not make, or acts otherwise: noise must
                  never create or change an action (it must stay at 0)
    The spoiling is drawn at random with a fixed seed, so every run is the same. Only calibration sentences are used:
    the test splits stay unseen.
.EXAMPLE
    ./tools/Measure-LambekRobustness.ps1
    Also run at the end of ./build.ps1 -Task Benchmark, which stops when a spoiled sentence makes an action.
#>
param(
    [int] $Seed = 48,

    # At most this many sentences of each bench (the first ones), to keep a run short
    [int] $Limit = 0,

    # Only these ways of spoiling a sentence (typo, accents, capitals, politeness, filler, punctuation)
    [string[]] $Way = @(),

    # Also print each spoiled sentence understood otherwise than the clean one
    [switch] $Show
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-robustness-$PID"
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force
Import-LambekPack -Path (Join-Path $root 'dsl/files') | Out-Null
Import-LambekPack -Path (Join-Path $root 'dsl/code') | Out-Null

# The sentences: the requests to act, and real sentences none written for Lambek
$sentences = [System.Collections.Generic.List[object]]::new()
$requests = Get-Content -LiteralPath (Join-Path $root 'bench/requests.json') -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($case in @($requests.Cases | Where-Object Split -EQ 'calibration' | Select-Object -First $(if ($Limit -gt 0) { $Limit } else { [int]::MaxValue }))) {
    $language = $(if (@($case.Tags) -contains 'fr') { 'fr' } else { 'en' })
    $sentences.Add([pscustomobject]@{ Id = $case.Id; Text = [string] $case.Text; Language = $language })
}
$real = Get-Content -LiteralPath (Join-Path $root 'bench/real.json') -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($case in @($real.Cases | Where-Object Split -EQ 'calibration' | Select-Object -First $(if ($Limit -gt 0) { $Limit } else { [int]::MaxValue }))) {
    $sentences.Add([pscustomobject]@{ Id = $case.Id; Text = [string] $case.Text; Language = [string] $case.Language })
}

# The keys next to each key, on the keyboards the user may have
$near = @{}
foreach ($rows in @(@('azertyuiop', 'qsdfghjklm', 'wxcvbn'), @('qwertyuiop', 'asdfghjkl', 'zxcvbnm'))) {
    for ($r = 0; $r -lt $rows.Count; $r++) {
        for ($c = 0; $c -lt $rows[$r].Length; $c++) {
            $key = $rows[$r][$c]
            $around = [System.Collections.Generic.List[char]]::new()
            foreach ($dr in -1, 0, 1) {
                $row = $r + $dr
                if ($row -lt 0 -or $row -ge $rows.Count) { continue }
                foreach ($dc in -1, 0, 1) {
                    $col = $c + $dc
                    if (($dr -eq 0 -and $dc -eq 0) -or $col -lt 0 -or $col -ge $rows[$row].Length) { continue }
                    $around.Add($rows[$row][$col])
                }
            }
            if (-not $near.ContainsKey($key)) { $near[$key] = [System.Collections.Generic.List[char]]::new() }
            foreach ($other in $around) { if (-not $near[$key].Contains($other)) { $near[$key].Add($other) } }
        }
    }
}

# The ways of spoiling a sentence; each returns the spoiled sentence, or nothing when it does not apply
$random = [Random]::new($Seed)
$ways = [ordered]@{
    # One letter of one word replaced by a key next to it (never in a path, a file name or an extension)
    typo        = {
        param([string] $Text, [string] $Language)
        $words = @([regex]::Matches($Text, '(?<![\\/.\w])[\p{L}]{4,}(?![\\/.\w])') | Where-Object { $_.Value.ToLowerInvariant().ToCharArray() | Where-Object { $near.ContainsKey($_) } })
        if ($words.Count -eq 0) { return $null }
        $word = $words[$random.Next($words.Count)]
        $at = 1 + $random.Next($word.Length - 1)
        $letter = [char]::ToLowerInvariant($word.Value[$at])
        if (-not $near.ContainsKey($letter)) { return $null }
        $choices = $near[$letter]
        $swap = $choices[$random.Next($choices.Count)]
        return $Text.Substring(0, $word.Index + $at) + $swap + $Text.Substring($word.Index + $at + 1)
    }
    accents     = {
        param([string] $Text, [string] $Language)
        $plain = [string]::new(@($Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })).Normalize([Text.NormalizationForm]::FormC)
        if ($plain -ceq $Text) { return $null }
        return $plain
    }
    capitals    = {
        param([string] $Text, [string] $Language)
        # (the words in capitals, the paths as they are)
        return [regex]::Replace($Text, '(?<![\\/.\w])[\p{L}]+(?![\\/.\w])', { param($m) $m.Value.ToUpperInvariant() })
    }
    politeness  = {
        param([string] $Text, [string] $Language)
        $before = $(if ($Language -eq 'fr') { @('stp ', 's''il te plait, ', 'bonjour, ', 'est-ce que tu peux ') } else { @('please ', 'hey, ', 'could you ', 'hi, ') })
        $after = $(if ($Language -eq 'fr') { @(' merci', ' stp', '') } else { @(' thanks', ' please', '') })
        return $before[$random.Next($before.Count)] + $Text.TrimEnd('?', '.', '!', ' ') + $after[$random.Next($after.Count)]
    }
    filler      = {
        param([string] $Text, [string] $Language)
        $fillers = $(if ($Language -eq 'fr') { @('euh ', 'alors ', 'bon ') } else { @('um ', 'so ', 'well ') })
        return $fillers[$random.Next($fillers.Count)] + $Text
    }
    punctuation = {
        param([string] $Text, [string] $Language)
        $bare = $Text.TrimEnd('?', '.', '!', ' ')
        if ($bare -ceq $Text) { return $null }
        return $bare
    }
}

# What Lambek does with a sentence, as the app asks it
$ask = {
    param([string] $Text, [string] $Language, [int] $Number)
    $line = ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $Number; method = 'ask'; params = [ordered]@{ text = $Text; chat = "robustness-$Number"; incognito = $true; language = $Language } })
    $response = & (Get-Module Lambek) { param($Line) Invoke-LambekHostRequest -Line $Line -AuditPath (Join-Path ([IO.Path]::GetTempPath()) "lambek-robustness-$PID.jsonl") } $line | ConvertFrom-Json -AsHashtable
    if ($response.ContainsKey('error') -and $response.error) { return [pscustomobject]@{ Status = 'Error'; Actions = ''; Kind = 'Error' } }
    $result = $response.result
    $actions = @($result['steps'] | Where-Object { $_ -and $_['action'] } | ForEach-Object { [string] $_['action'] }) -join ','
    $kind = $(if ($result['answer']) { 'Answer' } elseif (@($result['questions']).Count -gt 0) { 'Question' } else { 'Plan' })
    return [pscustomobject]@{ Status = [string] $result['status']; Actions = $actions; Kind = $kind }
}

$rows = [ordered]@{}
$Way = @($Way | ForEach-Object { "$_" -split "," } | Where-Object { $_ })
foreach ($name in @($ways.Keys)) { if ($Way.Count -gt 0 -and $name -notin $Way) { $ways.Remove($name) } }
foreach ($name in $ways.Keys) { $rows[$name] = [pscustomobject]@{ Way = $name; Sentences = 0; Same = 0; Unsafe = 0 } }
$unsafe = [System.Collections.Generic.List[string]]::new()
$number = 0
foreach ($sentence in $sentences) {
    $number++
    $clean = & $ask $sentence.Text $sentence.Language $number
    foreach ($name in $ways.Keys) {
        $spoiled = & $ways[$name] $sentence.Text $sentence.Language
        if (-not $spoiled -or $spoiled -ceq $sentence.Text) { continue }
        $number++
        $got = & $ask $spoiled $sentence.Language $number
        $row = $rows[$name]
        $row.Sentences++
        if ($got.Status -eq $clean.Status -and $got.Actions -eq $clean.Actions -and $got.Kind -eq $clean.Kind) { $row.Same++ }
        elseif ($Show) { Write-Host "  [$name] $($sentence.Id) $spoiled -> $($got.Status) $($got.Actions) $($got.Kind) (clean: $($clean.Status) $($clean.Actions) $($clean.Kind))" }
        # Noise must never create or change an action
        if ($got.Status -eq 'Ready' -and $got.Actions -and ($clean.Status -ne 'Ready' -or $got.Actions -ne $clean.Actions)) {
            $row.Unsafe++
            $unsafe.Add("$($sentence.Id) [$name] $spoiled -> $($got.Actions) (clean: $($clean.Status) $($clean.Actions))")
        }
    }
}

$total = [pscustomobject]@{ Way = 'all'; Sentences = 0; Same = 0; Unsafe = 0 }
foreach ($row in $rows.Values) { $total.Sentences += $row.Sentences; $total.Same += $row.Same; $total.Unsafe += $row.Unsafe }
Write-Host ('{0,-12} {1,10} {2,6} {3,9} {4,7}' -f 'Way', 'Sentences', 'Same', 'SameRate', 'Unsafe')
foreach ($row in @($rows.Values) + @($total)) {
    $rate = $(if ($row.Sentences) { [math]::Round($row.Same / $row.Sentences, 3) } else { 0 })
    Write-Host ('{0,-12} {1,10} {2,6} {3,9} {4,7}' -f $row.Way, $row.Sentences, $row.Same, $rate, $row.Unsafe)
}
foreach ($line in $unsafe) { Write-Host "  unsafe: $line" }
# (a run where noise made an action fails: build.ps1 stops on it)
if ($unsafe.Count -gt 0) { exit 1 }
