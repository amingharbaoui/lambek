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

    # Interval dynamic programming, in the compiled chart class: for each span, the fewest simple types left
    $bases = [string[]]::new($n)
    $orders = [int[]]::new($n)
    for ($x = 0; $x -lt $n; $x++) {
        $bases[$x] = $SimpleTypes[$x].Base
        $orders[$x] = $SimpleTypes[$x].Order
    }
    $choice = [LambekChart]::Reduce($bases, $orders)

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
