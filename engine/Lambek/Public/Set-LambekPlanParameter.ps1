function Set-LambekPlanParameter {
    <#
    .SYNOPSIS
        Changes one parameter of one step and returns a new, fully checked plan.
    .EXAMPLE
        Set-LambekPlanParameter -Plan $plan -Step 1 -Name Extension -Value '.tmp'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a new plan in memory and changes nothing on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Lambek.Plan')]
        [pscustomobject] $Plan,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1000)]
        [int] $Step,

        [Parameter(Mandatory)]
        [string] $Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ($Step -gt $Plan.Steps.Count) {
        throw "Step $Step does not exist."
    }

    $original = $Plan.Steps[$Step - 1]
    if (-not $original.Action) {
        throw "Step $Step has no action to edit."
    }

    $action = (Get-LambekAction -Id $original.Action).Action
    $definition = $action.Parameters | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $definition) {
        throw "Action $($original.Action) has no parameter '$Name'."
    }

    # New parameters in the order of the action definition
    $changed = [ordered]@{}
    foreach ($key in $original.Parameters.Keys) {
        $changed[$key] = $original.Parameters[$key]
    }
    if ([string]::IsNullOrWhiteSpace($Value)) {
        $changed.Remove($Name)
    }
    else {
        $changed[$Name] = ConvertFrom-LambekInput -Parameter $definition -Value $Value
    }

    $parameters = [ordered]@{}
    foreach ($item in $action.Parameters) {
        if ($changed.Contains($item.Name)) { $parameters[$item.Name] = $changed[$item.Name] }
    }

    # Rebuild this step from its parameters
    $check = Get-LambekMissingParameter -Action $action -Parameters $parameters -Language $original.Language
    $status = 'Ready'
    $cardHash = Get-LambekCardHash -ActionId $original.Action -Parameters $parameters
    if ($check.Missing.Count -gt 0) {
        $status = 'NeedsInput'
        $cardHash = $null
    }

    $rebuilt = [pscustomobject]@{
        Step       = $original.Step
        Clause     = $original.Clause
        Language   = $original.Language
        Status     = $status
        Confidence = $original.Confidence
        Types      = $original.Types
        Implied    = @(if ($original.PSObject.Properties['Implied']) { $original.Implied })
        Action     = $original.Action
        Risk       = $original.Risk
        Parameters = $parameters
        Questions  = @($check.Questions)
        Reads      = @()
        Writes     = @()
        Output     = $null
        Script     = $null
        Check      = $null
        CardHash   = $cardHash
    }
    $rebuilt = Complete-LambekStep -Step $rebuilt

    # The other steps stay as they are
    $steps = for ($i = 0; $i -lt $Plan.Steps.Count; $i++) {
        if ($i -eq $Step - 1) { $rebuilt } else { $Plan.Steps[$i] }
    }

    ConvertTo-LambekPlan -Text $Plan.Original -Steps @($steps) -Dependency $Plan.Dependencies
}
