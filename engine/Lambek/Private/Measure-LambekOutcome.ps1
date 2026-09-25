function Measure-LambekOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results
    )

    $total = $Results.Count
    $correct = @($Results | Where-Object Outcome -EQ 'Correct').Count
    $clarified = @($Results | Where-Object Outcome -EQ 'Clarified').Count
    $wrong = @($Results | Where-Object Outcome -EQ 'Wrong').Count
    $readyCases = @($Results | Where-Object { $_.Expected.Status -eq 'Ready' })
    $recognized = @($readyCases | Where-Object Outcome -EQ 'Correct').Count

    $recognition = 0.0
    if ($readyCases.Count -gt 0) {
        $recognition = $recognized / $readyCases.Count
    }

    return [pscustomobject]@{
        Total             = $total
        Correct           = $correct
        Clarified         = $clarified
        Wrong             = $wrong
        Accuracy          = [math]::Round($correct / [math]::Max($total, 1), 4)
        RecognitionRate   = [math]::Round($recognition, 4)
        ClarificationRate = [math]::Round($clarified / [math]::Max($total, 1), 4)
        WrongActionRate   = [math]::Round($wrong / [math]::Max($total, 1), 4)
    }
}
