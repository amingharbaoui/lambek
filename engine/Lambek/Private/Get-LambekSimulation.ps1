function Get-LambekSimulation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        [int] $TimeoutSeconds = 60
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $fingerprint = [System.Collections.Generic.List[string]]::new()
    $status = 'Ready'

    foreach ($number in $Plan.Order) {
        $step = $Plan.Steps[$number - 1]
        Send-LambekProgress -Stage 'Simulate' -Step $number -Percent (100 * [array]::IndexOf(@($Plan.Order), $number) / @($Plan.Order).Count)
        $affected = @()
        $summary = $null
        $bytes = 0L
        $stepStatus = 'Ready'
        $message = $null

        if ($step.Output -eq 'code') {
            $message = 'Generates code only, nothing is changed.'
        }
        elseif ($step.Output -eq 'mcp') {
            # MCP tools have no dry run: the simulation shows the exact call and sends nothing
            $call = $step.Script | ConvertFrom-Json -AsHashtable
            $message = "Would call $($call.tool) on $($call.server). Nothing was sent."
            $fingerprint.Add("mcp|$($step.Script)")
        }
        else {
            # Every command that is not read-only must support -WhatIf
            $commands = (Get-LambekAction -Id $step.Action).Pack.Commands
            foreach ($name in $commands) {
                # (path arithmetic and discarding output change nothing either)
                $isReadOnly = $name -match '^(Get|Select|Where|Sort|Measure|Test|Group|Format)-' -or $name -in 'Join-Path', 'Split-Path', 'Out-Null'
                $supportsWhatIf = (Get-Command -Name $name).Parameters.ContainsKey('WhatIf')
                if (-not $isReadOnly -and -not $supportsWhatIf) {
                    throw "Command '$name' cannot be simulated because it does not support -WhatIf."
                }
            }

            # Run with -WhatIf in the sandbox
            $run = Invoke-LambekSandbox -Script $step.Script -Commands $commands -Simulate -TimeoutSeconds $TimeoutSeconds

            if (-not $run.Succeeded) {
                $stepStatus = 'Failed'
                $message = $run.Error
                $status = 'Failed'
            }
            elseif ($run.Items.Count -gt 0) {
                $summary = Get-LambekItemSummary -Items @($run.Items)
                foreach ($item in $run.Items) {
                    $affected += [string] $item.FullName
                    if ($item.PSObject.Properties['Length'] -and $item.Length -is [long]) { $bytes += $item.Length }
                    $fingerprint.Add("$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)")
                }
            }
            elseif ($step.Script -match '\$items\s*=') {
                # The action works on the items it selects: none selected, nothing changes
                foreach ($path in $step.Writes) { $fingerprint.Add("$path|none") }
            }
            else {
                # The action creates something: what it writes is what changes
                foreach ($path in $step.Writes) {
                    $affected += $path
                    $fingerprint.Add("$path|$(Test-Path -LiteralPath $path)")
                }
            }
        }

        if (-not $message) {
            $message = "$($step.Action) would affect $($affected.Count) item(s)."
        }

        $results.Add([pscustomobject]@{
                Step     = $step.Step
                Action   = $step.Action
                Risk     = $step.Risk
                Status   = $stepStatus
                Count    = $affected.Count
                Bytes    = $bytes
                Affected = $affected
                Summary  = $summary
                Message  = $message
            })
    }

    # State hash: the exact files the plan would touch
    $sorted = $fingerprint | Sort-Object
    $stateHash = Get-LambekHash -Text ($sorted -join "`n")

    $confirmationCode = $null
    if ($Plan.Risk -eq 'high') {
        $confirmationCode = $Plan.PlanHash.Substring(0, 6).ToUpperInvariant()
    }

    return [pscustomobject]@{
        PSTypeName       = 'Lambek.Simulation'
        Status           = $status
        Risk             = $Plan.Risk
        PlanHash         = $Plan.PlanHash
        StateHash        = $stateHash
        ConfirmationCode = $confirmationCode
        Steps            = $results.ToArray()
    }
}
