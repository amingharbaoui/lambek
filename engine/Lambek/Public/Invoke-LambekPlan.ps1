function Invoke-LambekPlan {
    <#
    .SYNOPSIS
        Simulates or runs a plan in a sandbox. Running checks the approval, the plan hash, the scripts, and the files first.
    .EXAMPLE
        Invoke-LambekPlan -Plan $plan -Simulate
    .EXAMPLE
        Invoke-LambekPlan -Plan $plan -Approval $approval
    #>
    [CmdletBinding(DefaultParameterSetName = 'Run')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Lambek.Plan')]
        [pscustomobject] $Plan,

        [Parameter(Mandatory, ParameterSetName = 'Simulate')]
        [switch] $Simulate,

        [Parameter(ParameterSetName = 'Run')]
        [PSTypeName('Lambek.Approval')]
        [pscustomobject] $Approval,

        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 60,

        [string] $AuditPath = $script:AuditPath
    )

    process {
        if ($Plan.Status -ne 'Ready') {
            throw "Only a ready plan can be simulated or run (status: $($Plan.Status))."
        }

        # Simulation
        if ($Simulate) {
            $simulation = Get-LambekSimulation -Plan $Plan -TimeoutSeconds $TimeoutSeconds
            Write-LambekAudit -Path $AuditPath -EventName 'Simulated' -PlanHash $Plan.PlanHash -Detail $simulation.Status
            return $simulation
        }

        # Plan binding: every check must pass again right before running
        $reason = $null
        $planHash = Get-LambekPlanHash -Steps $Plan.Steps -Order $Plan.Order

        if ($null -eq $Approval -and $Plan.Risk -ne 'low') {
            $reason = "A $($Plan.Risk)-risk plan needs an approval."
        }
        elseif ($planHash -ne $Plan.PlanHash) {
            $reason = 'The plan was changed after it was built.'
        }
        elseif ($null -ne $Approval -and $Approval.PlanHash -ne $planHash) {
            $reason = 'The approval is for another plan.'
        }
        elseif ($null -ne $Approval -and [datetime]::UtcNow -gt $Approval.ExpiresAt) {
            $reason = 'The approval has expired.'
        }

        if (-not $reason) {
            foreach ($step in $Plan.Steps) {
                try {
                    $definition = Get-LambekAction -Id $step.Action
                }
                catch {
                    $reason = "Step $($step.Step) uses an action that is no longer loaded."
                    continue
                }

                # MCP calls are rebuilt from the current tool definition
                if ($step.Output -eq 'mcp') {
                    $call = ConvertTo-LambekMcpCall -Action $definition.Action -Parameters $step.Parameters
                    if ($call.Violations.Count -gt 0 -or $call.Script -ne $step.Script) {
                        $reason = "Step $($step.Step): the MCP tool changed since the plan was built."
                    }
                    continue
                }
                if (-not (Test-LambekScript -Script $step.Script -AllowedCommand $definition.Pack.Commands).IsValid) {
                    $reason = "Step $($step.Step) no longer passes the safety check."
                }
            }
        }

        if (-not $reason -and $null -ne $Approval) {
            $current = Get-LambekSimulation -Plan $Plan -TimeoutSeconds $TimeoutSeconds
            if ($current.StateHash -ne $Approval.StateHash) {
                $reason = 'The files changed since the approval. Simulate and approve again.'
            }
        }

        $results = [System.Collections.Generic.List[object]]::new()

        if ($reason) {
            Write-LambekAudit -Path $AuditPath -EventName 'Refused' -PlanHash $planHash -Detail $reason
            return [pscustomobject]@{
                PSTypeName = 'Lambek.Execution'
                Status     = 'Refused'
                Reason     = $reason
                PlanHash   = $planHash
                Steps      = @()
                AuditPath  = $AuditPath
            }
        }

        # Deletions kept longer than the trash keeps them are gone for good now
        try { Clear-LambekTrash -Confirm:$false }
        catch { Write-Verbose "The trash could not be emptied: $($_.Exception.Message)" }

        # Run the steps in order, stop at the first failure
        $status = 'Completed'
        foreach ($number in $Plan.Order) {
            $step = $Plan.Steps[$number - 1]
            Send-LambekProgress -Stage 'Run' -Step $number -Percent (100 * [array]::IndexOf(@($Plan.Order), $number) / @($Plan.Order).Count)

            if ($status -ne 'Completed') {
                $results.Add([pscustomobject]@{ Step = $number; Action = $step.Action; Status = 'Skipped'; Output = @(); Error = $null; Count = 0 })
                continue
            }

            if ($step.Output -eq 'code') {
                $results.Add([pscustomobject]@{ Step = $number; Action = $step.Action; Status = 'Completed'; Output = @($step.Script); Error = $null; Count = 0 })
                Write-LambekAudit -Path $AuditPath -EventName 'StepCompleted' -PlanHash $planHash -Step $number -Action $step.Action -Detail 'code generated'
                continue
            }

            if ($step.Output -eq 'mcp') {
                $run = Invoke-LambekMcpTool -Script $step.Script -TimeoutSeconds $TimeoutSeconds
            }
            else {
                $commands = (Get-LambekAction -Id $step.Action).Pack.Commands
                $run = Invoke-LambekSandbox -Script $step.Script -Commands $commands -TimeoutSeconds $TimeoutSeconds
            }

            if ($run.Succeeded) {
                # The postcondition, checked on the disk: what should be gone is gone, what should be there is there
                $wrong = @()
                if ($step.Output -eq 'command') { $wrong = @((Test-LambekEffect -Step $step -Items @($run.Items)).Wrong) }
                $summary = $null
                if ($step.Output -eq 'command') { $summary = Get-LambekItemSummary -Items @($run.Items) }
                $results.Add([pscustomobject]@{ Step = $number; Action = $step.Action; Status = 'Completed'; Output = $run.Output; Error = $null; Count = $run.Items.Count; Unverified = $wrong; Summary = $summary })
                # Remembered for the adaptation: the scorers that agreed with a plan the user ran, the places used
                Add-LambekHistory -Step $step
                # And each scorer's bias moves towards what this run showed (Kalman)
                Add-LambekDrift -Step $step
                # The user's own adapter of the proposer (LoRA) learns the request that was run; the base never changes
                if (-not $script:Incognito -and $step.PSObject.Properties['Clause'] -and $step.Clause) {
                    try { $null = Add-LambekProposalExample -Text $step.Clause -Action $step.Action }
                    catch { Write-Verbose "The proposer did not learn this request: $($_.Exception.Message)" }
                }
                $detail = "$($run.Items.Count) item(s), checked"
                if ($wrong.Count -gt 0) { $detail = "$($run.Items.Count) item(s), $($wrong.Count) not as planned" }
                Write-LambekAudit -Path $AuditPath -EventName 'StepCompleted' -PlanHash $planHash -Step $number -Action $step.Action -Detail $detail
            }
            else {
                $status = 'Failed'
                $results.Add([pscustomobject]@{ Step = $number; Action = $step.Action; Status = 'Failed'; Output = $run.Output; Error = $run.Error; Count = 0 })
                Write-LambekAudit -Path $AuditPath -EventName 'StepFailed' -PlanHash $planHash -Step $number -Action $step.Action -Detail $run.Error
            }
        }

        Write-LambekAudit -Path $AuditPath -EventName $status -PlanHash $planHash

        # A plan that ran is remembered, and the words not understood before it may now be learned
        $learned = @()
        if ($status -eq 'Completed') {
            try {
                Add-LambekMemory -Plan $Plan | Out-Null
                $learned = @(Invoke-LambekPursuit -Plan $Plan)
                # No word to learn: the whole sentence said before may be a turn of phrase for this plan
                if ($learned.Count -eq 0) { $learned = @(Invoke-LambekFormLearning -Plan $Plan) }
            }
            catch { Write-Verbose "The memory could not learn from this plan: $($_.Exception.Message)" }
        }

        [pscustomobject]@{
            PSTypeName = 'Lambek.Execution'
            Status     = $status
            Reason     = $null
            PlanHash   = $planHash
            Steps      = $results.ToArray()
            AuditPath  = $AuditPath
            Learned    = $learned
        }
    }
}
