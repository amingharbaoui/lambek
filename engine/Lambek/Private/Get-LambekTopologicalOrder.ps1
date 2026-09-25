function Get-LambekTopologicalOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $NodeCount,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Edges
    )

    # In-degree of each node
    $inDegree = [int[]]::new($NodeCount)
    $next = @{}
    for ($node = 0; $node -lt $NodeCount; $node++) {
        $next[$node] = [System.Collections.Generic.List[int]]::new()
    }
    foreach ($edge in $Edges) {
        $next[$edge.From].Add($edge.To)
        $inDegree[$edge.To]++
    }

    # Kahn (1962): take every node without incoming edge, level by level
    $order = [System.Collections.Generic.List[int]]::new()
    $levels = [System.Collections.Generic.List[object]]::new()
    $ready = @(0..($NodeCount - 1) | Where-Object { $inDegree[$_] -eq 0 })

    while ($ready.Count -gt 0) {
        $level = @($ready | Sort-Object)
        $levels.Add([int[]] $level)
        $newReady = [System.Collections.Generic.List[int]]::new()

        foreach ($node in $level) {
            $order.Add($node)
            foreach ($target in $next[$node]) {
                $inDegree[$target]--
                if ($inDegree[$target] -eq 0) {
                    $newReady.Add($target)
                }
            }
        }

        $ready = $newReady.ToArray()
    }

    # Nodes left out are part of a cycle
    $isComplete = $order.Count -eq $NodeCount

    return [pscustomobject]@{
        IsComplete = $isComplete
        Order      = $order.ToArray()
        Levels     = $levels.ToArray()
    }
}
