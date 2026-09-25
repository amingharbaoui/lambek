function Format-LambekType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $SimpleTypes
    )

    $parts = foreach ($simpleType in $SimpleTypes) {
        if ($simpleType.Order -lt 0) {
            "$($simpleType.Base)^$('l' * -$simpleType.Order)"
        }
        elseif ($simpleType.Order -gt 0) {
            "$($simpleType.Base)^$('r' * $simpleType.Order)"
        }
        else {
            $simpleType.Base
        }
    }

    return ($parts -join ' ')
}
