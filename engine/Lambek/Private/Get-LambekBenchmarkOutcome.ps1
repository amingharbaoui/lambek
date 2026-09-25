function Get-LambekBenchmarkOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Expected,

        [Parameter(Mandatory)]
        [pscustomobject] $Card
    )

    # Parameters in canonical form
    $actual = [ordered]@{}
    foreach ($name in $Card.Parameters.Keys) {
        $actual[$name] = Format-LambekValue -Value $Card.Parameters[$name]
    }

    # Expected a ready card
    if ($Expected.Status -eq 'Ready') {
        if ($Card.Status -ne 'Ready') {
            return 'Clarified'
        }
        if ($Card.Action -ne $Expected.Action) {
            return 'Wrong'
        }

        $expectedParameters = $Expected.Parameters
        if ($actual.Count -ne $expectedParameters.Count) {
            return 'Wrong'
        }
        foreach ($name in $expectedParameters.Keys) {
            if (-not $actual.Contains($name) -or $actual[$name] -cne [string] $expectedParameters[$name]) {
                return 'Wrong'
            }
        }
        return 'Correct'
    }

    # Expected a question: acting is always wrong, another question is still safe
    if ($Card.Status -eq 'Ready') {
        return 'Wrong'
    }
    if ($Card.Status -eq $Expected.Status) {
        return 'Correct'
    }
    return 'Clarified'
}
