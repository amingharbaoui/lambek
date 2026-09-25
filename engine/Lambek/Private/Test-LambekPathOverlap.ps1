function Test-LambekPathOverlap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PathA,

        [Parameter(Mandatory)]
        [string] $PathB
    )

    # Same path, or one path inside the other
    $a = $PathA.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
    $b = $PathB.Replace('/', '\').TrimEnd('\').ToLowerInvariant()

    if ($a -eq $b) { return $true }
    if ($a.StartsWith("$b\")) { return $true }
    if ($b.StartsWith("$a\")) { return $true }
    return $false
}
