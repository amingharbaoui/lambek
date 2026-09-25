function Measure-LambekJaccard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $SetA,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $SetB
    )

    $a = [System.Collections.Generic.HashSet[string]]::new($SetA)
    $b = [System.Collections.Generic.HashSet[string]]::new($SetB)

    if ($a.Count -eq 0 -and $b.Count -eq 0) {
        return 1.0
    }

    # |A n B| / |A u B|
    $intersection = [System.Collections.Generic.HashSet[string]]::new($a)
    $intersection.IntersectWith($b)

    $union = [System.Collections.Generic.HashSet[string]]::new($a)
    $union.UnionWith($b)

    return [double] ($intersection.Count / $union.Count)
}
