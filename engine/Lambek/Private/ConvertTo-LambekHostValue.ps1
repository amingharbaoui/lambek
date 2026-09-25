function ConvertTo-LambekHostValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value
    )

    # Plain values stay as they are
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double]) {
        return $Value
    }
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('o')
    }
    if ($Value -is [timespan]) {
        return Format-LambekValue -Value $Value
    }

    # Objects become a small table of their first properties
    $table = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Select-Object -First 8)) {
        $item = $property.Value
        if ($item -is [datetime]) { $item = $item.ToUniversalTime().ToString('o') }
        elseif ($null -ne $item -and $item -isnot [string] -and $item -isnot [long] -and $item -isnot [int] -and $item -isnot [double] -and $item -isnot [bool]) {
            $item = [string] $item
        }
        $table[$property.Name] = $item
    }
    return $table
}
