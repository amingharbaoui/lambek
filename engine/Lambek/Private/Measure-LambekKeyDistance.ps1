function Measure-LambekKeyDistance {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Source,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Target
    )

    # Typing cost: a slip to a key next door, two letters swapped, or a doubled letter costs half an edit (Native/Lambek.cs)
    return [LambekMeasure]::KeyDistance($Source, $Target, (Get-LambekKeyNeighbor))
}

function Get-LambekKeyNeighbor {
    # Keys side by side on QWERTY and AZERTY keyboards, both ways
    if ($script:KeyNeighbors) { return , $script:KeyNeighbors }

    $neighbors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($layout in @(@('qwertyuiop', 'asdfghjkl', 'zxcvbnm'), @('azertyuiop', 'qsdfghjklm', 'wxcvbn'))) {
        for ($row = 0; $row -lt $layout.Count; $row++) {
            $keys = $layout[$row]
            for ($i = 0; $i -lt $keys.Length; $i++) {
                if ($i + 1 -lt $keys.Length) {
                    [void] $neighbors.Add("$($keys[$i])$($keys[$i + 1])")
                    [void] $neighbors.Add("$($keys[$i + 1])$($keys[$i])")
                }
                # The row below is shifted half a key: key i sits over keys i - 1 and i
                if ($row + 1 -lt $layout.Count) {
                    $below = $layout[$row + 1]
                    foreach ($k in ($i - 1), $i) {
                        if ($k -ge 0 -and $k -lt $below.Length) {
                            [void] $neighbors.Add("$($keys[$i])$($below[$k])")
                            [void] $neighbors.Add("$($below[$k])$($keys[$i])")
                        }
                    }
                }
            }
        }
    }
    $script:KeyNeighbors = $neighbors
    return , $neighbors
}
