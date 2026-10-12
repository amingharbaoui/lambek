function Invoke-LambekBenchmark {
    <#
    .SYNOPSIS
        Runs the annotated benchmark and measures recognition, clarification, wrong actions, determinism, and speed.
    .EXAMPLE
        Invoke-LambekBenchmark -Path ./bench/requests.json -Split test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('all', 'calibration', 'test', 'hard')]
        [string] $Split = 'all',

        [pscustomobject] $Scoring = (Get-LambekScoring)
    )

    $cases = Get-LambekBenchmarkCase -Path $Path -Split $Split
    $results = [System.Collections.Generic.List[object]]::new()
    $times = [System.Collections.Generic.List[double]]::new()
    $deterministic = 0

    foreach ($case in $cases) {
        # Run twice: the second run must give exactly the same card
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $evidence = Get-LambekIntentEvidence -Request (ConvertTo-LambekRequest -Text $case.Text)
        $card = New-LambekIntentCard -Evidence $evidence -Scoring $Scoring
        $times.Add($stopwatch.Elapsed.TotalMilliseconds)

        $again = New-LambekIntentCard -Evidence (Get-LambekIntentEvidence -Request (ConvertTo-LambekRequest -Text $case.Text)) -Scoring $Scoring
        $first = "$($card.Status)|$($card.Action)|$($card.CardHash)|$($card.Confidence)"
        $second = "$($again.Status)|$($again.Action)|$($again.CardHash)|$($again.Confidence)"
        if ($first -eq $second) { $deterministic++ }

        $results.Add([pscustomobject]@{
                Id         = $case.Id
                Text       = $case.Text
                Tags       = @($case.Tags)
                Expected   = $case.Expected
                Status     = $card.Status
                Action     = $card.Action
                Parameters = $card.Parameters
                Confidence = $card.Confidence
                Outcome    = Get-LambekBenchmarkOutcome -Expected $case.Expected -Card $card
            })
    }

    # Metrics per tag
    $tags = @($results | ForEach-Object { $_.Tags } | Sort-Object -Unique)
    $byTag = foreach ($tag in $tags) {
        $tagged = @($results | Where-Object { $_.Tags -contains $tag })
        $metrics = Measure-LambekOutcome -Results $tagged
        [pscustomobject]@{
            Tag       = $tag
            Total     = $metrics.Total
            Correct   = $metrics.Correct
            Clarified = $metrics.Clarified
            Wrong     = $metrics.Wrong
        }
    }

    # Speed
    $sorted = @($times | Sort-Object)
    $median = $sorted[[int][math]::Floor(($sorted.Count - 1) / 2)]
    $p95 = $sorted[[int][math]::Ceiling(0.95 * $sorted.Count) - 1]

    $metrics = Measure-LambekOutcome -Results $results.ToArray()

    [pscustomobject]@{
        PSTypeName        = 'Lambek.BenchmarkReport'
        Split             = $Split
        Total             = $metrics.Total
        Correct           = $metrics.Correct
        Clarified         = $metrics.Clarified
        Wrong             = $metrics.Wrong
        Accuracy          = $metrics.Accuracy
        RecognitionRate   = $metrics.RecognitionRate
        ClarificationRate = $metrics.ClarificationRate
        WrongActionRate   = $metrics.WrongActionRate
        # The highest wrong-action rate these cases cannot rule out, at 95 %: what the benchmark really proves
        WrongActionBound  = [math]::Round((Get-LambekRateBound -Failures $metrics.Wrong -Cases $metrics.Total), 4)
        Determinism       = [math]::Round($deterministic / $cases.Count, 4)
        MedianMs          = [math]::Round($median, 1)
        P95Ms             = [math]::Round($p95, 1)
        ByTag             = @($byTag)
        Failures          = @($results | Where-Object Outcome -NE 'Correct')
        Scoring           = $Scoring
    }
}
