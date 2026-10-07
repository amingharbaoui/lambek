#Requires -Version 7.4
param(
    [ValidateSet('All', 'Analyze', 'Test', 'Benchmark', 'Fingerprint')]
    [string] $Task = 'All',

    # Where the fingerprint writes its lines (one answer each)
    [string] $OutFile
)

$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot 'engine'

# Tool versions
$pesterVersion = '6.2.0'
$analyzerVersion = '1.25.0'
Write-Host "PowerShell $($PSVersionTable.PSVersion)"

# Static analysis
if ($Task -eq 'All' -or $Task -eq 'Analyze') {
    Write-Host 'Running PSScriptAnalyzer...'
    Import-Module PSScriptAnalyzer -MinimumVersion $analyzerVersion -Force
    Write-Host "PSScriptAnalyzer $((Get-Module PSScriptAnalyzer).Version)"

    $settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
    $files = Get-ChildItem -Path (Join-Path $engine 'Lambek') -Recurse -Include '*.ps1', '*.psm1'
    $issues = @()
    foreach ($file in $files) {
        $issues += Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settings
    }

    if ($issues.Count -gt 0) {
        foreach ($issue in $issues) {
            Write-Host "$($issue.ScriptName):$($issue.Line) $($issue.RuleName) $($issue.Message)"
        }
        throw "PSScriptAnalyzer found $($issues.Count) issue(s)."
    }
    Write-Host 'PSScriptAnalyzer: no issues.'
}

# Tests
if ($Task -eq 'All' -or $Task -eq 'Test') {
    Write-Host 'Running Pester...'

    Import-Module Pester -MinimumVersion $pesterVersion -Force

    # Tests keep what they learn and log in a folder of their own, never in the user's
    $env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-tests-$PID"

    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $engine 'tests'
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'

    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) {
        throw "$($result.FailedCount) test(s) failed."
    }
}

# Benchmark
if ($Task -eq 'Benchmark') {
    Import-Module (Join-Path $engine 'Lambek/Lambek.psd1') -Force
    Import-LambekPack -Path (Join-Path $PSScriptRoot 'dsl/files') | Out-Null
    Import-LambekPack -Path (Join-Path $PSScriptRoot 'dsl/code') | Out-Null

    $path = Join-Path $PSScriptRoot 'bench/requests.json'
    foreach ($split in 'calibration', 'test') {
        $report = Invoke-LambekBenchmark -Path $path -Split $split
        Write-Host ''
        Write-Host "Benchmark ($split)"
        foreach ($name in 'Total', 'Correct', 'Clarified', 'Wrong', 'RecognitionRate', 'WrongActionRate', 'Determinism', 'MedianMs', 'P95Ms') {
            Write-Host ("  {0,-16} {1}" -f $name, $report.$name)
        }
    }
}

# Fingerprint: what Lambek answers to every request of the benchmark, one line each, and the hash of them all.
# The same sources must give the same hash on every machine
if ($Task -eq 'Fingerprint') {
    # Nothing learned before may change an answer
    $env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-fingerprint-$PID"
    Import-Module (Join-Path $engine 'Lambek/Lambek.psd1') -Force
    Import-LambekPack -Path (Join-Path $PSScriptRoot 'dsl/files') | Out-Null
    Import-LambekPack -Path (Join-Path $PSScriptRoot 'dsl/code') | Out-Null

    $invariant = [cultureinfo]::InvariantCulture
    $cases = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bench/requests.json') -Raw | ConvertFrom-Json).Cases
    $lines = foreach ($case in $cases) {
        $card = ConvertTo-LambekRequest -Text $case.Text | Resolve-LambekIntent
        $names = [string[]] @($card.Parameters.Keys)
        [array]::Sort($names, [System.StringComparer]::Ordinal)
        $values = foreach ($name in $names) {
            $said = foreach ($value in @($card.Parameters[$name])) {
                if ($value -is [timespan]) { $value.TotalSeconds.ToString($invariant) + 's' }
                elseif ($value -is [double] -or $value -is [long] -or $value -is [int]) { ([double] $value).ToString('R', $invariant) }
                else { [string] $value }
            }
            "$name=$($said -join ' ')"
        }
        "$($case.Id)|$($card.Status)|$($card.Action)|$(([double] $card.Confidence).ToString('R', $invariant))|$($values -join ';')"
    }

    $text = ($lines -join "`n") + "`n"
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
    if ($OutFile) { [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile), $text, [Text.UTF8Encoding]::new($false)) }
    Write-Host "Fingerprint of $(@($lines).Count) answers: $hash"
}
