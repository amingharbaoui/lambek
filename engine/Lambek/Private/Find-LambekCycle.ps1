function Find-LambekCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $NodeCount,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Edges
    )

    # Adjacency list
    $next = @{}
    for ($node = 0; $node -lt $NodeCount; $node++) {
        $next[$node] = [System.Collections.Generic.List[int]]::new()
    }
    foreach ($edge in $Edges) {
        $next[$edge.From].Add($edge.To)
    }

    # Tarjan (1972): strongly connected components
    $state = @{
        Counter    = 0
        Index      = @{}
        LowLink    = @{}
        Stack      = [System.Collections.Generic.Stack[int]]::new()
        OnStack    = [System.Collections.Generic.HashSet[int]]::new()
        Components = [System.Collections.Generic.List[object]]::new()
        Next       = $next
    }

    for ($node = 0; $node -lt $NodeCount; $node++) {
        if (-not $state.Index.ContainsKey($node)) {
            Invoke-LambekTarjanVisit -Node $node -State $state
        }
    }

    # A cycle is a component with several nodes, or a node that points to itself
    $cycles = [System.Collections.Generic.List[object]]::new()
    foreach ($component in $state.Components) {
        $isCycle = $component.Count -gt 1 -or $next[$component[0]].Contains($component[0])
        if ($isCycle) {
            $cycles.Add([int[]] @($component | Sort-Object))
        }
    }

    return , $cycles.ToArray()
}

function Invoke-LambekTarjanVisit {
    param(
        [int] $Node,
        [hashtable] $State
    )

    $State.Index[$Node] = $State.Counter
    $State.LowLink[$Node] = $State.Counter
    $State.Counter++
    $State.Stack.Push($Node)
    [void] $State.OnStack.Add($Node)

    foreach ($target in $State.Next[$Node]) {
        if (-not $State.Index.ContainsKey($target)) {
            Invoke-LambekTarjanVisit -Node $target -State $State
            $State.LowLink[$Node] = [math]::Min($State.LowLink[$Node], $State.LowLink[$target])
        }
        elseif ($State.OnStack.Contains($target)) {
            $State.LowLink[$Node] = [math]::Min($State.LowLink[$Node], $State.Index[$target])
        }
    }

    # Root of a component: pop it from the stack
    if ($State.LowLink[$Node] -eq $State.Index[$Node]) {
        $component = [System.Collections.Generic.List[int]]::new()
        do {
            $member = $State.Stack.Pop()
            [void] $State.OnStack.Remove($member)
            $component.Add($member)
        } while ($member -ne $Node)

        $State.Components.Add($component.ToArray())
    }
}
