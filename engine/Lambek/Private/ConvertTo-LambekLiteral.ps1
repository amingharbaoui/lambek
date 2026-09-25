function ConvertTo-LambekLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return '$null'
    }
    if ($Value -is [bool]) {
        if ($Value) { return '$true' }
        return '$false'
    }
    if ($Value -is [timespan]) {
        $seconds = $Value.TotalSeconds.ToString([cultureinfo]::InvariantCulture)
        return "[timespan]::FromSeconds($seconds)"
    }
    if ($Value -is [double] -or $Value -is [long] -or $Value -is [int]) {
        return ([double] $Value).ToString('R', [cultureinfo]::InvariantCulture)
    }

    # Strings always become single-quoted literals, so they are never executed
    $escaped = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string] $Value)
    return "'$escaped'"
}
