#Requires -Version 7.4
param(
    [ValidateSet('All', 'Analyze', 'Test', 'Benchmark')]
    [string] $Task = 'All'
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
