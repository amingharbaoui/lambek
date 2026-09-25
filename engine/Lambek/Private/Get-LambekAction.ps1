function Get-LambekAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Id
    )

    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            if ($action.Id -eq $Id) {
                return [pscustomobject]@{ Pack = $pack; Action = $action }
            }
        }
    }

    throw "Action '$Id' is not loaded."
}
