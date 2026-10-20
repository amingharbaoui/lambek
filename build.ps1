#Requires -Version 7.4
param(
    [ValidateSet('All', 'Build', 'Analyze', 'Test', 'Benchmark', 'Fingerprint')]
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

# The C# of the engine, built into engine/Lambek/bin with the hash of its sources (Lambek.psm1 computes the same hash).
# Without the .NET SDK the module still works: it compiles the same sources itself the first time it is imported
if ($Task -eq 'All' -or $Task -eq 'Build') {
    $native = Join-Path $engine 'Lambek/Native'
    $bin = Join-Path $engine 'Lambek/bin'
    # dotnet can be there with only the runtime: the SDK is what builds
    $sdks = @()
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        $sdks = @(dotnet --list-sdks 2>$null | Where-Object { $_ -match '^\d+\.' })
    }
    if ($sdks.Count -eq 0) {
        Write-Warning 'No .NET SDK is installed (winget install Microsoft.DotNet.SDK.8): the engine will compile its C# when it is first imported.'
    }
    else {
        Write-Host "Building the C# with .NET SDK $(($sdks[-1] -split ' ')[0])..."
        $sources = @(Get-ChildItem -Path $native -Filter '*.cs' | Sort-Object Name | ForEach-Object FullName)
        $text = ($sources | ForEach-Object { [IO.File]::ReadAllText($_) }) -join "`n"
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).Substring(0, 16)

        # The hash file goes first, so a failed build never leaves a library that claims the new sources
        $from = Join-Path $bin 'Lambek.Native.sources'
        if (Test-Path -LiteralPath $from) { Remove-Item -LiteralPath $from -Force }
        dotnet build (Join-Path $engine 'Lambek.Native/Lambek.Native.csproj') -c Release -nologo -v quiet | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'The C# build failed.' }
        [IO.File]::WriteAllText($from, $hash, [Text.UTF8Encoding]::new($false))
        Write-Host "Built engine/Lambek/bin/Lambek.Native.dll from sources $hash."
    }
}

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
    foreach ($split in 'calibration', 'test', 'hard') {
        $report = Invoke-LambekBenchmark -Path $path -Split $split
        Write-Host ''
        Write-Host "Benchmark ($split)"
        foreach ($name in 'Total', 'Correct', 'Clarified', 'Wrong', 'RecognitionRate', 'WrongActionRate', 'WrongActionBound', 'Determinism', 'MedianMs', 'P95Ms') {
            Write-Host ("  {0,-16} {1}" -f $name, $report.$name)
        }
    }

    # Free messages, sent as the app sends them: what Lambek does not answer, and what it says wrong.
    # Each figure is shown next to the one written in bench/baseline.json, the figures every step is measured against
    $messages = Join-Path $PSScriptRoot 'bench/messages.json'
    $baseline = $null
    $baselinePath = Join-Path $PSScriptRoot 'bench/baseline.json'
    if (Test-Path -LiteralPath $baselinePath) { $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json }
    foreach ($split in 'calibration', 'test') {
        $report = Invoke-LambekMessageBenchmark -Path $messages -Split $split
        $before = $null
        if ($baseline -and $baseline.Messages.PSObject.Properties[$split]) { $before = $baseline.Messages.$split }
        Write-Host ''
        Write-Host "Free messages ($split)"
        foreach ($name in 'Cases', 'Turns', 'Correct', 'Unanswered', 'NotUnderstood', 'Abstained', 'Asked', 'Wrong', 'WrongActions', 'UnansweredRate', 'WrongRate', 'WrongBound', 'Said', 'Composed', 'Determinism', 'MedianMs', 'P95Ms') {
            $was = ''
            if ($before -and $before.PSObject.Properties[$name]) { $was = "(baseline $($before.$name))" }
            Write-Host ("  {0,-16} {1,-10} {2}" -f $name, $report.$name, $was)
        }
        if ($split -eq 'test' -and -not $report.TestFrozen) {
            Write-Warning 'The test split of bench/messages.json is not the frozen one (TestHash): its figures cannot be compared with the baseline.'
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

    # And every reply to the free messages, so they too must be the same on every machine
    $messages = Invoke-LambekMessageBenchmark -Path (Join-Path $PSScriptRoot 'bench/messages.json')
    $lines = @($lines) + @(foreach ($turn in $messages.Results) {
            "$($turn.Id)#$($turn.Turn)|$($turn.Status)|$(@($turn.Actions) -join ',')|$(($turn.Reply -replace "`r", '') -replace "`n", ' / ')"
        })

    $text = ($lines -join "`n") + "`n"
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
    if ($OutFile) { [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile), $text, [Text.UTF8Encoding]::new($false)) }
    Write-Host "Fingerprint of $(@($lines).Count) answers: $hash"
}
