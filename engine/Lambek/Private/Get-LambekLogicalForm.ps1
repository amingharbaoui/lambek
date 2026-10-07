function Get-LambekLogicalForm {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Step
    )

    # The meaning of a step as a term without variables, in the spirit of Liang's lambda-DCS:
    # the set of objects is an intersection of restrictions, "except" is a complement, "the 2 largest" a superlative,
    # and the verb applies to the set and to its other arguments. The same plan always gives the same text
    if (-not $Step.Action) { return $null }
    $verb = ($Step.Action -split '\.')[-1]
    $values = $Step.Parameters

    # Arguments that are not the objects: where to, the new name, how much to free, where to create
    $arguments = @('Destination', 'NewName', 'FreeSize', 'Parent', 'Language')
    $restrictions = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    $others = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    $head = 'object'
    if ($values.Contains('Kind')) { $head = (Format-LambekValue -Value $values['Kind']).ToLowerInvariant() }

    foreach ($name in $values.Keys) {
        if ($name -in 'Kind', 'Order', 'Count', 'Permanent') { continue }
        $value = Format-LambekValue -Value $values[$name]
        $relation = $name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1)
        if ($name -in $arguments) { [void] $others.Add("$relation($value)"); continue }
        if ($name -like 'Except*') {
            $relation = $name.Substring(6, 1).ToLowerInvariant() + $name.Substring(7)
            [void] $restrictions.Add("not($relation($value))")
            continue
        }
        [void] $restrictions.Add("$relation($value)")
    }

    # The set, then the superlative on it (argmax by the order, as many as asked, one by default)
    $set = (@($head) + @($restrictions)) -join ' and '
    if ($values.Contains('Order')) {
        $count = 1
        if ($values.Contains('Count')) { $count = $values['Count'] }
        $set = "top($count, $(Format-LambekValue -Value $values['Order']), $set)"
    }
    elseif ($values.Contains('Count')) { $set = "some($($values['Count']), $set)" }
    else { $set = "all($set)" }
    if ($values.Contains('Permanent') -and $values['Permanent']) { [void] $others.Add('permanent') }

    return "$verb($((@($set) + @($others)) -join ', '))"
}
