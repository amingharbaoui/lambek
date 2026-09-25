function Get-LambekEntityContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $Position,

        [Parameter(Mandatory)]
        [pscustomobject] $Grammar,

        [ValidateRange(1, 5)]
        [int] $Depth = 2
    )

    # Words that are not expanded (verbs link to everything)
    $verbPositions = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($item in $Grammar.Assignment) {
        if ($item.Type -match '(^|\s)s(\s|$)') {
            [void] $verbPositions.Add($item.Position)
        }
    }

    # Follow grammar links from the entity
    $context = [System.Collections.Generic.List[string]]::new()
    $visited = [System.Collections.Generic.HashSet[int]]::new()
    [void] $visited.Add($Position)
    $frontier = @($Position)

    for ($level = 1; $level -le $Depth; $level++) {
        $next = [System.Collections.Generic.List[int]]::new()

        foreach ($link in $Grammar.Links) {
            $other = -1
            if ($frontier -contains $link.LeftPosition) { $other = $link.RightPosition }
            if ($frontier -contains $link.RightPosition) { $other = $link.LeftPosition }
            if ($other -lt 0 -or $visited.Contains($other)) { continue }

            [void] $visited.Add($other)
            $context.Add($Grammar.Words[$other])
            if (-not $verbPositions.Contains($other)) {
                $next.Add($other)
            }
        }

        $frontier = $next.ToArray()
    }

    return $context.ToArray()
}
