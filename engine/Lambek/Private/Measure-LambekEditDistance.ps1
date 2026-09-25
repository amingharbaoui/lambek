function Measure-LambekEditDistance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Source,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Target
    )

    $n = $Source.Length
    $m = $Target.Length

    # Matrix init
    $d = [int[, ]]::new($n + 1, $m + 1)
    for ($i = 0; $i -le $n; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0, $j] = $j }

    # Damerau-Levenshtein (optimal string alignment)
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $cost = 1
            if ($Source[$i - 1] -ceq $Target[$j - 1]) { $cost = 0 }

            $deletion = $d[($i - 1), $j] + 1
            $insertion = $d[$i, ($j - 1)] + 1
            $substitution = $d[($i - 1), ($j - 1)] + $cost
            $best = [math]::Min([math]::Min($deletion, $insertion), $substitution)

            $isSwap = $i -gt 1 -and $j -gt 1 -and $Source[$i - 1] -ceq $Target[$j - 2] -and $Source[$i - 2] -ceq $Target[$j - 1]
            if ($isSwap) {
                $best = [math]::Min($best, $d[($i - 2), ($j - 2)] + 1)
            }

            $d[$i, $j] = $best
        }
    }

    # Result
    $distance = $d[$n, $m]
    $longest = [math]::Max($n, $m)
    $similarity = 1.0
    if ($longest -gt 0) { $similarity = 1.0 - ($distance / $longest) }

    return [pscustomobject]@{
        Distance   = $distance
        Similarity = [double] $similarity
    }
}
