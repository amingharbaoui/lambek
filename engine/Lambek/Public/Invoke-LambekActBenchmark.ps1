function Invoke-LambekActBenchmark {
    <#
    .SYNOPSIS
        Measures the router of acts on messages it never saw: what it says each message is, against what it is.
    .DESCRIPTION
        Each case is a message and its act (Talk, Order, Tell, Ask, World...). The router is asked as New-LambekPlan asks
        it: the language is found from the message, never given. A case is Right when the router says its act, Wrong when
        it says another, Abstained when it says nothing (the readers then decide alone, as before the router).

        The report gives the precision of what the router says (Right out of Routed), how often it speaks (Coverage),
        the highest wrong rate the cases cannot rule out (WrongBound), each act alone, and the confusion matrix: for
        each act, what the router said of its messages ('-' when it abstained). Every case is routed twice, the second
        time in the other order: the acts must be the same.
    .EXAMPLE
        Invoke-LambekActBenchmark -Path ./bench/acts.json -Split test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('all', 'calibration', 'test')]
        [string] $Split = 'all'
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Benchmark file not found: $Path" }
    $data = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    $every = @($data.Cases)
    $cases = @($every | Where-Object { $Split -eq 'all' -or $_.Split -eq $Split })
    if ($cases.Count -eq 0) { throw "No act case for split '$Split'." }

    # The test split is frozen: its hash is written in the file, and a change to it is said
    $testHash = Get-LambekMessageBenchmarkHash -Cases @($every | Where-Object Split -EQ 'test')
    $frozen = $data.PSObject.Properties['TestHash'] -and $data.TestHash -eq $testHash

    # (the language the chat was last in would help the router; the bench gives it none)
    $hint = $script:LanguageHint
    $script:LanguageHint = $null
    try {
        $acts = @((Get-LambekRouter).Acts)
        $results = foreach ($case in $cases) {
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            $route = Get-LambekRoute -Text $case.Text
            $milliseconds = $clock.Elapsed.TotalMilliseconds
            $outcome = if (-not $route.Act) { 'Abstained' } elseif ($route.Act -eq $case.Act) { 'Right' } else { 'Wrong' }
            [pscustomobject]@{
                Id = $case.Id; Split = $case.Split; Language = $case.Language; Text = $case.Text; Expected = $case.Act
                Act = $route.Act; Proposed = $route.Proposed; Margin = $route.Margin; Outcome = $outcome; Milliseconds = $milliseconds
            }
        }
        # Twice, the other way round: the router must say the same whatever came before
        $again = @{}
        for ($i = $cases.Count - 1; $i -ge 0; $i--) { $again[$cases[$i].Id] = (Get-LambekRoute -Text $cases[$i].Text).Act }
    }
    finally { $script:LanguageHint = $hint }

    $results = @($results)
    $same = @($results | Where-Object { $again[$_.Id] -eq $_.Act }).Count
    $routed = @($results | Where-Object Act)
    $right = @($results | Where-Object Outcome -EQ 'Right').Count
    $wrong = @($results | Where-Object Outcome -EQ 'Wrong').Count

    $byAct = foreach ($act in $acts) {
        $mine = @($results | Where-Object Expected -EQ $act)
        $said = @($results | Where-Object Act -EQ $act)
        $good = @($mine | Where-Object Outcome -EQ 'Right').Count
        [pscustomobject]@{
            Act       = $act
            Cases     = $mine.Count
            Right     = $good
            Abstained = @($mine | Where-Object Outcome -EQ 'Abstained').Count
            # Of the messages of this act, how many the router named; of what it named this act, how many were
            Recall    = $(if ($mine.Count) { [math]::Round($good / $mine.Count, 4) } else { $null })
            Precision = $(if ($said.Count) { [math]::Round($good / $said.Count, 4) } else { $null })
        }
    }

    # For each act, what the router said of its messages
    $columns = @($acts) + '-'
    $confusion = foreach ($act in $acts) {
        $row = [ordered]@{ Act = $act }
        foreach ($column in $columns) {
            $row[$column] = @($results | Where-Object { $_.Expected -eq $act -and $(if ($column -eq '-') { -not $_.Act } else { $_.Act -eq $column }) }).Count
        }
        [pscustomobject]$row
    }

    $times = @($results | ForEach-Object Milliseconds | Sort-Object)
    [pscustomobject]@{
        PSTypeName  = 'Lambek.ActBenchmark'
        Split       = $Split
        Cases       = $results.Count
        Routed      = $routed.Count
        Right       = $right
        Wrong       = $wrong
        Abstained   = $results.Count - $routed.Count
        Coverage    = [math]::Round($routed.Count / $results.Count, 4)
        Precision   = $(if ($routed.Count) { [math]::Round($right / $routed.Count, 4) } else { $null })
        WrongBound  = $(if ($routed.Count) { [math]::Round((Get-LambekRateBound -Failures $wrong -Cases $routed.Count), 4) } else { $null })
        Determinism = [math]::Round($same / $results.Count, 4)
        MedianMs    = [math]::Round($times[[int][math]::Floor(($times.Count - 1) / 2)], 2)
        TestFrozen  = [bool] $frozen
        TestHash    = $testHash
        ByAct       = @($byAct)
        Confusion   = @($confusion)
        Results     = $results
        Failures    = @($results | Where-Object Outcome -EQ 'Wrong')
    }
}
