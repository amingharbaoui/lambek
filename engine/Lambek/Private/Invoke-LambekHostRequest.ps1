function Invoke-LambekHostRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line,

        [Parameter(Mandatory)]
        [string] $AuditPath
    )

    $id = $null
    try {
        # Request: { "id": 1, "method": "ask", "params": { ... } }
        try {
            $request = $Line | ConvertFrom-Json -AsHashtable
        }
        catch {
            throw 'The request is not valid JSON.'
        }
        if ($request -isnot [hashtable] -or -not $request.ContainsKey('method')) {
            throw 'The request needs a method.'
        }

        $id = $request['id']
        $params = @{}
        if ($request.ContainsKey('params') -and $request.params -is [hashtable]) {
            $params = $request.params
        }
        $state = $script:HostState

        switch ($request.method) {
            'ping' {
                $result = [ordered]@{ name = 'Lambek'; version = (Get-Module Lambek).Version.ToString() }
            }
            'packs' {
                $result = @(Get-LambekPack | ForEach-Object {
                        [ordered]@{ name = $_.Name; version = $_.Version; description = $_.Description; actions = @($_.Actions) }
                    })
            }
            'ask' {
                if (-not $params.ContainsKey('text') -or [string]::IsNullOrWhiteSpace($params.text)) {
                    throw 'ask needs a text.'
                }
                $plan = New-LambekPlan -Text $params.text

                # Plans are kept in memory by id (at most 50)
                $planId = $plan.PlanHash
                if (-not $planId) { $planId = Get-LambekHash -Text "draft|$($params.text)" }
                $state.Plans[$planId] = $plan
                while ($state.Plans.Count -gt 50) { $state.Plans.RemoveAt(0) }

                $result = ConvertTo-LambekHostPlan -Id $planId -Plan $plan
            }
            'simulate' {
                $plan = Get-LambekHostPlan -State $state -Params $params
                $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $AuditPath
                $state.Simulations[$params.id] = $simulation

                $result = [ordered]@{
                    id               = $params.id
                    status           = $simulation.Status
                    risk             = $simulation.Risk
                    confirmationCode = $simulation.ConfirmationCode
                    answer           = ConvertTo-LambekAnswer -Plan $plan -Simulation $simulation
                    steps            = @($simulation.Steps | ForEach-Object {
                            [ordered]@{ step = $_.Step; action = $_.Action; status = $_.Status; count = $_.Count; affected = @($_.Affected | Select-Object -First 50); message = $_.Message }
                        })
                }
            }
            'approve' {
                $plan = Get-LambekHostPlan -State $state -Params $params
                if (-not $state.Simulations.ContainsKey($params.id)) {
                    throw 'Simulate the plan before approving it.'
                }
                $confirmation = ''
                if ($params.ContainsKey('confirmation')) { $confirmation = [string] $params.confirmation }

                $approval = Approve-LambekPlan -Simulation $state.Simulations[$params.id] -Confirmation $confirmation -AuditPath $AuditPath
                $state.Approvals[$params.id] = $approval
                $result = [ordered]@{ id = $params.id; approved = $true; expiresAt = $approval.ExpiresAt.ToString('o') }
            }
            'run' {
                $plan = Get-LambekHostPlan -State $state -Params $params
                $approval = $null
                if ($state.Approvals.ContainsKey($params.id)) { $approval = $state.Approvals[$params.id] }

                $execution = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $AuditPath
                $result = [ordered]@{
                    id     = $params.id
                    status = $execution.Status
                    reason = $execution.Reason
                    answer = ConvertTo-LambekAnswer -Plan $plan -Execution $execution
                    steps  = @($execution.Steps | ForEach-Object {
                            [ordered]@{
                                step   = $_.Step
                                action = $_.Action
                                status = $_.Status
                                error  = $_.Error
                                output = @($_.Output | Select-Object -First 100 | ForEach-Object { ConvertTo-LambekHostValue -Value $_ })
                            }
                        })
                }
            }
            'audit' {
                $limit = 50
                if ($params.ContainsKey('limit')) { $limit = [int] $params.limit }
                $entries = @()
                $valid = $true
                if (Test-Path -LiteralPath $AuditPath) {
                    $entries = @(Get-Content -LiteralPath $AuditPath -Tail $limit | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
                    $valid = (Test-LambekAudit -Path $AuditPath).IsValid
                }
                $result = [ordered]@{ valid = $valid; entries = $entries }
            }
            default {
                throw "Unknown method '$($request.method)'."
            }
        }

        $response = [ordered]@{ id = $id; result = $result }
    }
    catch {
        $response = [ordered]@{ id = $id; error = [ordered]@{ message = $_.Exception.Message } }
    }

    return ($response | ConvertTo-Json -Depth 12 -Compress)
}

function Get-LambekHostPlan {
    param(
        [hashtable] $State,
        [hashtable] $Params
    )

    if (-not $Params.ContainsKey('id') -or -not $State.Plans.Contains($Params.id)) {
        throw 'Unknown plan id. Ask again.'
    }
    return $State.Plans[$Params.id]
}
