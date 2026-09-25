function Get-LambekTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Action,

        [Parameter(Mandatory)]
        [string] $Language
    )

    if ($Action.Title.ContainsKey($Language)) {
        return $Action.Title[$Language]
    }
    return $Action.Title['en']
}
