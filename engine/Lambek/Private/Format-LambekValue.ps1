function Format-LambekValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return ''
    }
    if ($Value -is [array]) {
        return (@($Value | ForEach-Object { Format-LambekValue -Value $_ }) -join ' ')
    }
    if ($Value -is [timespan]) {
        return $Value.TotalSeconds.ToString([cultureinfo]::InvariantCulture) + 's'
    }
    if ($Value -is [double] -or $Value -is [long] -or $Value -is [int]) {
        return ([double] $Value).ToString([cultureinfo]::InvariantCulture)
    }
    return [string] $Value
}
