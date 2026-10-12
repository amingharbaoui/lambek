function Get-LambekRateBound {
    # What a count of failures out of a number of cases lets one claim about the true rate: the exact upper bound of
    # Clopper-Pearson, one-sided. 0 failures out of 251 claims a rate under 1.19 % at 95 %, not a rate of 0
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $Failures,

        [Parameter(Mandatory)]
        [int] $Cases,

        [double] $Confidence = 0.95
    )

    if ($Cases -le 0) { return 1.0 }
    if ($Failures -ge $Cases) { return 1.0 }
    $alpha = 1.0 - $Confidence
    if ($Failures -le 0) { return 1.0 - [math]::Pow($alpha, 1.0 / $Cases) }

    # The bound is the rate p at which seeing this few failures or fewer has probability alpha; the chance falls as p grows
    $low = 0.0
    $high = 1.0
    for ($step = 0; $step -lt 100; $step++) {
        $p = ($low + $high) / 2
        # P(X <= Failures) for X ~ Binomial(Cases, p), summed in logarithms so long benches do not underflow
        $logTerm = $Cases * [math]::Log(1.0 - $p)
        $logSum = $logTerm
        for ($i = 0; $i -lt $Failures; $i++) {
            $logTerm += [math]::Log(($Cases - $i) / ($i + 1.0)) + [math]::Log($p / (1.0 - $p))
            $top = [math]::Max($logSum, $logTerm)
            $logSum = $top + [math]::Log([math]::Exp($logSum - $top) + [math]::Exp($logTerm - $top))
        }
        if ([math]::Exp($logSum) -gt $alpha) { $low = $p } else { $high = $p }
    }
    return $high
}
