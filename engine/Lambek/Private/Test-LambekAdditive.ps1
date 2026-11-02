function Test-LambekAdditive {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Step,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Items
    )

    # Whether the step only adds what is not there yet: each of its effects puts something new in a place,
    # nothing leaves its place and nothing already there is written over
    $effects = @((Get-LambekAction -Id $Step.Action).Action['Effect'] | Where-Object { $_ })
    if ($effects.Count -eq 0) { return $false }
    foreach ($effect in $effects) {
        switch ($effect) {
            'arrived' {
                $destination = [string] $Step.Parameters['Destination']
                if (-not $destination) { return $false }
                # A file there would be written over by what arrives
                if ((Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $destination -PathType Container)) { return $false }
                foreach ($item in $Items) {
                    if (-not $item.Name -or (Test-Path -LiteralPath (Join-Path $destination $item.Name))) { return $false }
                }
            }
            'exists' {
                foreach ($path in @($Step.Writes | Where-Object { $_ })) { if (Test-Path -LiteralPath $path) { return $false } }
            }
            default { return $false }
        }
    }
    return $true
}
