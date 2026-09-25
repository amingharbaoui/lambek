function Get-LambekPlanHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Steps,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [int[]] $Order
    )

    # Every step in execution order: number, card hash, and exact script
    $parts = foreach ($number in $Order) {
        $step = $Steps[$number - 1]
        "$($step.Step):$($step.Action):$($step.CardHash):$($step.Script)"
    }

    return Get-LambekHash -Text ($parts -join "`n")
}
