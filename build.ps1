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
    # Measured on Lambek as it is shipped: nothing learned on this machine (words, forms, habits) may change a figure
    $env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-benchmark-$PID"
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
    # (the fresh split: messages written for this step and measured once, with no baseline)
    foreach ($split in 'calibration', 'test', 'fresh') {
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

    # Real sentences, none written for Lambek (bench/real.json, drawn at random by tools/Get-LambekRealSentences.ps1):
    # a part of the roadmap enters only when Correct goes up here and nothing falls elsewhere. Shown next to the score
    # written in bench/baseline.json before step 4.7
    $real = Join-Path $PSScriptRoot 'bench/real.json'
    foreach ($split in 'calibration', 'test') {
        $report = Invoke-LambekMessageBenchmark -Path $real -Split $split
        $before = $null
        if ($baseline -and $baseline.PSObject.Properties['Real'] -and $baseline.Real.PSObject.Properties[$split]) { $before = $baseline.Real.$split }
        Write-Host ''
        Write-Host "Real sentences ($split)"
        foreach ($name in 'Cases', 'Correct', 'Unanswered', 'NotUnderstood', 'Abstained', 'Asked', 'Wrong', 'WrongActions', 'UnansweredRate', 'WrongRate', 'WrongBound', 'Determinism', 'MedianMs', 'P95Ms') {
            $was = ''
            if ($before -and $before.PSObject.Properties[$name]) { $was = "(before 4.7 $($before.$name))" }
            Write-Host ("  {0,-16} {1,-10} {2}" -f $name, $report.$name, $was)
        }
        if ($split -eq 'test' -and -not $report.TestFrozen) {
            Write-Warning 'The test split of bench/real.json is not the frozen one (TestHash): its figures cannot be compared.'
        }
    }

    # The same messages without the dictionaries: Lambek reads and speaks with the words it learned only (the
    # roadmap removes the dictionaries once these figures are those above, with nothing said wrong). In a session of
    # its own, so that nothing the dictionaries gave above (a lemma kept, a reading kept) is used again here
    $empty = Join-Path ([IO.Path]::GetTempPath()) "lambek-no-dictionaries-$PID"
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $alone = {
        param($Engine, $Root, $Messages)
        Import-Module (Join-Path $Engine 'Lambek/Lambek.psd1') -Force
        Import-LambekPack -Path (Join-Path $Root 'dsl/files') | Out-Null
        Import-LambekPack -Path (Join-Path $Root 'dsl/code') | Out-Null
        # (warmed as the session above was, by the requests first: the times are compared with those above)
        Invoke-LambekBenchmark -Path (Join-Path $Root 'bench/requests.json') -Split calibration | Out-Null
        foreach ($split in 'calibration', 'test', 'fresh') {
            $report = Invoke-LambekMessageBenchmark -Path $Messages -Split $split
            Write-Output ''
            Write-Output "Free messages ($split, without dictionaries)"
            foreach ($name in 'Turns', 'Correct', 'Unanswered', 'Wrong', 'WrongActions', 'Determinism', 'MedianMs') {
                Write-Output ("  {0,-16} {1}" -f $name, $report.$name)
            }
        }
    }
    $before = $env:LAMBEK_DICTIONARIES
    $env:LAMBEK_DICTIONARIES = $empty
    try {
        $command = "& { $alone } -Engine '$($engine -replace "'", "''")' -Root '$($PSScriptRoot -replace "'", "''")' -Messages '$($messages -replace "'", "''")'"
        & ([Environment]::ProcessPath) -NoProfile -NonInteractive -Command $command | ForEach-Object { Write-Host $_ }
    }
    finally { $env:LAMBEK_DICTIONARIES = $before }

    # The forms of words, learned without a dictionary, on treebanks they never learned from; next to them, what the
    # dictionaries Lambek reads today give on the same words
    foreach ($treebank in @(@{ Language = 'fr'; File = 'fr_gsd-ud-test.conllu' }, @{ Language = 'fr'; File = 'fr_parisstories-ud-test.conllu' }, @{ Language = 'en'; File = 'en_ewt-ud-test.conllu' })) {
        $report = Invoke-LambekFormBenchmark -Path (Join-Path $PSScriptRoot "bench/forms/$($treebank.File)") -Language $treebank.Language -Dictionary
        Write-Host ''
        Write-Host "Forms ($($treebank.Language), $($treebank.File))"
        foreach ($name in 'Words', 'Upos', 'Feats', 'AllTags', 'Lemma', 'Unseen', 'UnseenLemma', 'UnseenUpos', 'Speak', 'SpeakUnseen', 'DictionaryKnown', 'DictionaryLemma', 'Determinism', 'WordsPerSecond') {
            Write-Host ("  {0,-16} {1}" -f $name, $report.$name)
        }
    }

    # The router of acts, on messages it never saw: what it says a message is, and what it is.
    # The confusion matrix reads by line: for the messages of each act, what the router said ('-': it abstained)
    $acts = Join-Path $PSScriptRoot 'bench/acts.json'
    foreach ($split in 'calibration', 'test') {
        $report = Invoke-LambekActBenchmark -Path $acts -Split $split
        Write-Host ''
        Write-Host "Acts ($split)"
        foreach ($name in 'Cases', 'Routed', 'Right', 'Wrong', 'Abstained', 'Coverage', 'Precision', 'WrongBound', 'Determinism', 'MedianMs') {
            Write-Host ("  {0,-16} {1}" -f $name, $report.$name)
        }
        $columns = @($report.Confusion[0].PSObject.Properties.Name | Where-Object { $_ -ne 'Act' })
        Write-Host ("  {0,-10} {1}" -f '', (($columns | ForEach-Object { $_.Substring(0, [math]::Min(4, $_.Length)).PadLeft(5) }) -join ''))
        foreach ($row in $report.Confusion) {
            Write-Host ("  {0,-10} {1}" -f $row.Act, (($columns | ForEach-Object { "$($row.$_)".PadLeft(5) }) -join ''))
        }
        if ($split -eq 'test' -and -not $report.TestFrozen) {
            Write-Warning 'The test split of bench/acts.json is not the frozen one (TestHash): its figures cannot be compared.'
        }
    }

    # Sentences written less well (a typo, no accents, capitals, politeness, a filler word, no punctuation): the same
    # understanding as the clean sentence as often as can be, and never an action noise made (tools/Measure-LambekRobustness.ps1)
    Write-Host ''
    Write-Host 'Robustness (calibration sentences spoiled)'
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'tools/Measure-LambekRobustness.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'A spoiled sentence made an action the clean one did not make.' }

    # Contrast: the same requests turned so that they must not act (a negation, a question of how, what someone else
    # wanted, whether it is safe, a condition to check): none may act (tools/Measure-LambekContrast.ps1)
    Write-Host ''
    Write-Host 'Contrast (calibration requests turned so that they must not act)'
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'tools/Measure-LambekContrast.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'A request turned so that it must not act was ready to act.' }
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
    # And every reply to the real sentences
    $real = Invoke-LambekMessageBenchmark -Path (Join-Path $PSScriptRoot 'bench/real.json')
    $lines = @($lines) + @(foreach ($turn in $real.Results) {
            "$($turn.Id)#$($turn.Turn)|$($turn.Status)|$(@($turn.Actions) -join ',')|$(($turn.Reply -replace "`r", '') -replace "`n", ' / ')"
        })
    # And what the forms models read in every word of their test treebanks
    foreach ($treebank in @(@{ Language = 'fr'; File = 'fr_gsd-ud-test.conllu' }, @{ Language = 'fr'; File = 'fr_parisstories-ud-test.conllu' }, @{ Language = 'en'; File = 'en_ewt-ud-test.conllu' })) {
        $model = & (Get-Module Lambek) { param($language) Get-LambekFormModel -Language $language } $treebank.Language
        $index = 0
        $lines = @($lines) + @(foreach ($sentence in [LambekTreebank]::Read((Join-Path $PSScriptRoot "bench/forms/$($treebank.File)"))) {
                $index++
                $read = $model.Read([string[]] @($sentence | ForEach-Object Form))
                "$($treebank.File)#$($index.ToString($invariant))|$(($read | ForEach-Object { "$($_.Lemma)/$($_.Upos)/$($_.Feats)" }) -join ' ')"
            })
    }

    # And what the router of acts says of every message of its bench, with its margin
    $routes = Invoke-LambekActBenchmark -Path (Join-Path $PSScriptRoot 'bench/acts.json')
    $lines = @($lines) + @(foreach ($route in $routes.Results) {
            "$($route.Id)|$($route.Act)|$($route.Proposed)|$(([double] $route.Margin).ToString('R', $invariant))"
        })

    $text = ($lines -join "`n") + "`n"
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
    if ($OutFile) { [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile), $text, [Text.UTF8Encoding]::new($false)) }
    Write-Host "Fingerprint of $(@($lines).Count) answers: $hash"
}
