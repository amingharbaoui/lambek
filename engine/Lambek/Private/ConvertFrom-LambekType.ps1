function ConvertFrom-LambekType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Type
    )

    $simpleTypes = [System.Collections.Generic.List[object]]::new()

    # Split "s o^l" into simple types
    foreach ($part in $Type.Trim() -split '\s+') {
        if ($part -notmatch '^(?<base>[a-z]+)(\^(?<adjoint>l+|r+))?$') {
            throw "Invalid type '$part' in '$Type'."
        }

        # Adjoint order: o^ll = -2, o^l = -1, o = 0, o^r = 1, o^rr = 2
        $order = 0
        $adjoint = $Matches['adjoint']
        if ($adjoint) {
            if ($adjoint.StartsWith('l')) {
                $order = -$adjoint.Length
            }
            else {
                $order = $adjoint.Length
            }
        }

        $simpleTypes.Add([pscustomobject]@{ Base = $Matches['base']; Order = $order })
    }

    return $simpleTypes.ToArray()
}
