function Format-LambekShownType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Step
    )

    # The types of a step, then each type the parameters supply, marked with a star: "s p^l o^l o p*"
    $types = @("$($Step.Types)")
    if ($Step.PSObject.Properties['Implied']) {
        $types += @($Step.Implied | Where-Object { $_ } | ForEach-Object { "$_*" })
    }
    return (@($types | Where-Object { $_ }) -join ' ')
}
