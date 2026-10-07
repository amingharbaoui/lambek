# The chart itself is the class LambekChart, in Native/Lambek.cs
function Invoke-LambekChart {
    [CmdletBinding()]
    param(
        # Each word with its candidate types: @{ Candidates = @('s o^l', ...) }
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]] $TypedWords,

        # Readings kept per form: the smallest choice vectors, as the old odometer met them first
        [ValidateRange(1, 64)]
        [int] $Keep = 4,

        # Work budget: the same input always stops at the same place, whatever the machine
        [ValidateRange(1, 100000000)]
        [long] $Fuel = 2000000,

        # Keep only forms that can still become a sentence (count invariant against the words outside the cell)
        [switch] $SentenceOnly,

        # Keep only the shortest forms of each cell (0: all of them)
        [ValidateRange(0, 1000)]
        [int] $Beam = 0
    )

    # One chart for every choice of types at once (CKY over words).
    # Cell [i, j] maps each irreducible form the words i..j can reduce to, to the choices of types that give it.
    $chart = [LambekChart]::new()
    $leaves = [int[][]]::new($TypedWords.Count)
    for ($w = 0; $w -lt $TypedWords.Count; $w++) {
        $candidates = @($TypedWords[$w].Candidates)
        $leaves[$w] = [int[]]::new($candidates.Count)
        for ($c = 0; $c -lt $candidates.Count; $c++) {
            $id = $chart.Id('')
            foreach ($simpleType in ConvertFrom-LambekType -Type $candidates[$c]) {
                $id = $chart.Join($id, $chart.Id("$($simpleType.Base)|$($simpleType.Order)"))
            }
            $leaves[$w][$c] = $id
        }
    }
    return , $chart.Run($leaves, $Keep, $Fuel, [bool] $SentenceOnly, $Beam)
}

function Compare-LambekChoice {
    param([int[]] $First, [int[]] $Second)

    # Word by word, the first word first: the order the odometer used
    for ($x = 0; $x -lt [math]::Min($First.Count, $Second.Count); $x++) {
        if ($First[$x] -lt $Second[$x]) { return -1 }
        if ($First[$x] -gt $Second[$x]) { return 1 }
    }
    return $First.Count.CompareTo($Second.Count)
}

function Get-LambekFormCount {
    param([string] $Form)

    # How many simple types a form leaves
    if (-not $Form) { return 0 }
    return @($Form -split ' ').Count
}
