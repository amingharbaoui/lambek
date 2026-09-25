#Requires -Version 7.4
param(
    [ValidateSet('All', 'Analyze', 'Test')]
    [string] $Task = 'All'
)

$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot 'engine'

# Static analysis
if ($Task -eq 'All' -or $Task -eq 'Analyze') {
    Write-Host 'Running PSScriptAnalyzer...'

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

    Import-Module Pester -MinimumVersion 5.5.0 -Force

    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $engine 'tests'
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'

    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) {
        throw "$($result.FailedCount) test(s) failed."
    }
}
