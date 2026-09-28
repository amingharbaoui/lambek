function Get-LambekCardHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ActionId,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Parameters
    )

    # Action and parameters only, so the hash does not depend on wording or language
    $parts = foreach ($name in ($Parameters.Keys | Sort-Object)) {
        "$name=$(Format-LambekValue -Value $Parameters[$name])"
    }
    return Get-LambekHash -Text "$ActionId|$($parts -join ';')"
}
