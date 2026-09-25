function Approve-LambekPlan {
    <#
    .SYNOPSIS
        Approves a simulated plan. High-risk plans need the confirmation code shown by the simulation.
    .EXAMPLE
        $simulation = Invoke-LambekPlan -Plan $plan -Simulate
        $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Lambek.Simulation')]
        [pscustomobject] $Simulation,

        [string] $Confirmation,

        [ValidateRange(1, 1440)]
        [int] $ValidMinutes = 15,

        [string] $AuditPath = $script:AuditPath
    )

    process {
        # Checks
        if ($Simulation.Status -ne 'Ready') {
            throw 'A plan whose simulation failed cannot be approved.'
        }
        if ($Simulation.Risk -eq 'high' -and $Confirmation -cne $Simulation.ConfirmationCode) {
            throw "This plan is high risk. Type the confirmation code $($Simulation.ConfirmationCode) to approve it."
        }

        # Approval bound to the plan and to the state of the files
        $now = [datetime]::UtcNow
        $approval = [pscustomobject]@{
            PSTypeName = 'Lambek.Approval'
            PlanHash   = $Simulation.PlanHash
            StateHash  = $Simulation.StateHash
            Risk       = $Simulation.Risk
            ApprovedAt = $now
            ExpiresAt  = $now.AddMinutes($ValidMinutes)
            User       = [Environment]::UserName
        }

        Write-LambekAudit -Path $AuditPath -EventName 'Approved' -PlanHash $Simulation.PlanHash -Detail "risk $($Simulation.Risk)"
        return $approval
    }
}
