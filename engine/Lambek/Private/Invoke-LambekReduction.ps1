function Invoke-LambekReduction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $SimpleTypes
    )

    $n = $SimpleTypes.Count
    $leftover = [System.Collections.Generic.List[int]]::new()
    $pairs = [System.Collections.Generic.List[object]]::new()

    if ($n -eq 0) {
        return [pscustomobject]@{ Leftover = $leftover.ToArray(); Pairs = $pairs.ToArray() }
    }

    # cost[i, j] = smallest number of simple types left over in positions i..j
    # choice[i, j] = -1 when i stays, otherwise the position that i cancels with
    $cost = [int[, ]]::new($n + 1, $n + 1)
    $choice = [int[, ]]::new($n + 1, $n + 1)

    for ($length = 1; $length -le $n; $length++) {
        for ($i = 0; $i -le $n - $length; $i++) {
            $j = $i + $length - 1

            # Option 1: i is not cancelled
            $best = 1 + (Get-LambekCost -Cost $cost -From ($i + 1) -To $j)
            $bestChoice = -1

            # Option 2: i cancels with m (x^(k) . x^(k+1) -> 1), everything between must cancel first
            for ($m = $i + 1; $m -le $j; $m++) {
                $left = $SimpleTypes[$i]
                $right = $SimpleTypes[$m]
                $canCancel = $left.Base -eq $right.Base -and $right.Order -eq $left.Order + 1

                if ($canCancel -and (Get-LambekCost -Cost $cost -From ($i + 1) -To ($m - 1)) -eq 0) {
                    $candidate = Get-LambekCost -Cost $cost -From ($m + 1) -To $j
                    if ($candidate -lt $best) {
                        $best = $candidate
                        $bestChoice = $m
                    }
                }
            }

            $cost[$i, $j] = $best
            $choice[$i, $j] = $bestChoice
        }
    }

    # Rebuild the cancellations
    $ranges = [System.Collections.Generic.Stack[int[]]]::new()
    $ranges.Push(@(0, ($n - 1)))

    while ($ranges.Count -gt 0) {
        $range = $ranges.Pop()
        $i = $range[0]
        $j = $range[1]
        if ($i -gt $j) { continue }

        $m = $choice[$i, $j]
        if ($m -eq -1) {
            $leftover.Add($i)
            $ranges.Push(@(($i + 1), $j))
        }
        else {
            $pairs.Add([pscustomobject]@{ Left = $i; Right = $m })
            $ranges.Push(@(($m + 1), $j))
            $ranges.Push(@(($i + 1), ($m - 1)))
        }
    }

    return [pscustomobject]@{
        Leftover = @($leftover | Sort-Object)
        Pairs    = @($pairs | Sort-Object Left)
    }
}

function Get-LambekCost {
    param(
        [int[, ]] $Cost,
        [int] $From,
        [int] $To
    )

    if ($From -gt $To) {
        return 0
    }
    return $Cost[$From, $To]
}
