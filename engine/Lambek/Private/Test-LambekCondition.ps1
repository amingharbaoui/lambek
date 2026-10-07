function Test-LambekCondition {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()]
        [string] $Condition,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Parameters
    )

    # "?Name", "!Name" and "?Name=value", as in the templates, one after the other: all must hold
    foreach ($part in @($Condition -split '\s+' | Where-Object { $_ })) {
        if ($part -notmatch '^(?<sign>[?!])(?<name>[A-Za-z]+)(?:=(?<value>[\w.-]+))?$') { return $false }
        $isSet = $Parameters.Contains($Matches['name'])
        if ($isSet -and $Matches['value']) { $isSet = [string] $Parameters[$Matches['name']] -eq $Matches['value'] }
        if ($Matches['sign'] -eq '?' -and -not $isSet) { return $false }
        if ($Matches['sign'] -eq '!' -and $isSet) { return $false }
    }
    return $true
}

function Get-LambekActionNote {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Action,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Parameters,

        [Parameter(Mandatory)]
        [string] $Language
    )

    # How the action goes about it, when the pack says: one text, or lines that hold under a condition
    if (-not $Action.ContainsKey('Note') -or -not $Action.Note.ContainsKey($Language)) { return [string[]] @() }
    $notes = foreach ($line in @($Action.Note[$Language])) {
        if ($line -match '^(?<condition>(?:[?!][A-Za-z]+(?:=[\w.-]+)?\s+)+)(?<text>.*)$') {
            if (Test-LambekCondition -Condition $Matches['condition'] -Parameters $Parameters) { $Matches['text'] }
        }
        else { $line }
    }
    return [string[]] @($notes)
}
