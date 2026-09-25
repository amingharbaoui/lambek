function New-LambekPlan {
    <#
    .SYNOPSIS
        Compiles a request into a validated plan: Action Cards, dependency graph, order, and checked scripts.
    .EXAMPLE
        New-LambekPlan 'create the folder D:\Archive then move the .log files in C:\Temp to D:\Archive'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a plan in memory and changes nothing on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateLength(1, 4000)]
        [string] $Text,

        [AllowEmptyCollection()]
        [ValidatePattern('^\d+->\d+$')]
        [string[]] $Dependency = @()
    )

    process {
        $steps = [System.Collections.Generic.List[object]]::new()
        $questions = [System.Collections.Generic.List[string]]::new()

        # One Action Card per clause
        $clauses = @(Split-LambekClause -Text $Text)
        for ($i = 0; $i -lt $clauses.Count; $i++) {
            $number = $i + 1
            $card = ConvertTo-LambekRequest -Text $clauses[$i] | Resolve-LambekIntent

            $step = [pscustomobject]@{
                Step       = $number
                Clause     = $clauses[$i]
                Status     = $card.Status
                Action     = $card.Action
                Risk       = $card.Risk
                Parameters = $card.Parameters
                Reads      = @()
                Writes     = @()
                Output     = $null
                Script     = $null
                Check      = $null
                CardHash   = $card.CardHash
            }

            foreach ($question in $card.Questions) {
                $questions.Add("Step ${number}: $question")
            }

            if ($card.Status -eq 'Ready') {
                $definition = (Get-LambekAction -Id $card.Action)
                $action = $definition.Action
                $step.Output = $action.Output

                # Resources read and written
                $step.Reads = @($action.Reads | Where-Object { $card.Parameters.Contains($_) } | ForEach-Object { [string] $card.Parameters[$_] })
                $step.Writes = @($action.Writes | Where-Object { $card.Parameters.Contains($_) } | ForEach-Object { [string] $card.Parameters[$_] })

                # Supported values (for example, only PowerShell code)
                $unsupported = $null
                if ($action.ContainsKey('Supported')) {
                    foreach ($name in $action.Supported.Keys) {
                        if ($card.Parameters.Contains($name) -and $card.Parameters[$name] -notin $action.Supported[$name]) {
                            $unsupported = "$name '$($card.Parameters[$name])' is not supported yet."
                        }
                    }
                }

                # Template
                $template = $null
                if ($action.ContainsKey('Template')) {
                    $template = $action.Template
                }
                elseif ($action.ContainsKey('Templates')) {
                    $key = [string] $card.Parameters[$action.TemplateKey]
                    if ($action.Templates.ContainsKey($key)) {
                        $template = $action.Templates[$key]
                    }
                    else {
                        $unsupported = "$($action.TemplateKey) '$key' has no template yet."
                    }
                }

                if ($unsupported) {
                    $step.Status = 'Unsupported'
                    $questions.Add("Step ${number}: $unsupported")
                }
                else {
                    try {
                        $step.Script = ConvertTo-LambekScript -Template $template -Parameters $card.Parameters
                        $step.Check = Test-LambekScript -Script $step.Script -AllowedCommand $definition.Pack.Commands
                        if (-not $step.Check.IsValid) {
                            $step.Status = 'Blocked'
                            $rules = ($step.Check.Violations | ForEach-Object { $_.Rule } | Select-Object -Unique) -join ', '
                            $questions.Add("Step ${number}: the script did not pass the safety check ($rules).")
                        }
                    }
                    catch {
                        $step.Status = 'Blocked'
                        $questions.Add("Step ${number}: $($_.Exception.Message)")
                    }
                }
            }

            $steps.Add($step)
        }

        # Dependencies: a step that writes a resource goes before a later step that uses it
        $edges = [System.Collections.Generic.List[object]]::new()
        for ($a = 0; $a -lt $steps.Count; $a++) {
            for ($b = $a + 1; $b -lt $steps.Count; $b++) {
                $reason = Get-LambekConflict -First $steps[$a] -Second $steps[$b]
                if ($reason) {
                    $edges.Add([pscustomobject]@{ From = $a; To = $b; Reason = $reason })
                }
            }
        }

        foreach ($item in $Dependency) {
            $from = [int] $item.Split('->')[0] - 1
            $to = [int] $item.Split('->')[-1] - 1
            if ($from -lt 0 -or $to -lt 0 -or $from -ge $steps.Count -or $to -ge $steps.Count) {
                throw "Dependency '$item' refers to a step that does not exist."
            }
            $edges.Add([pscustomobject]@{ From = $from; To = $to; Reason = 'manual' })
        }

        # Cycles (Tarjan) and order (Kahn)
        $cycles = Find-LambekCycle -NodeCount $steps.Count -Edges $edges.ToArray()
        $sorting = Get-LambekTopologicalOrder -NodeCount $steps.Count -Edges $edges.ToArray()

        foreach ($cycle in $cycles) {
            $numbers = ($cycle | ForEach-Object { $_ + 1 }) -join ', '
            $questions.Add("Steps $numbers depend on each other in a loop.")
        }

        # Plan status
        $statuses = @($steps | ForEach-Object { $_.Status })
        $status = 'Ready'
        if ($cycles.Count -gt 0 -or $statuses -contains 'Blocked') {
            $status = 'Invalid'
        }
        elseif ($statuses | Where-Object { $_ -ne 'Ready' }) {
            $status = 'NeedsInput'
        }

        # Plan hash: every step in execution order
        $order = @($sorting.Order | ForEach-Object { $_ + 1 })
        $planHash = $null
        if ($status -eq 'Ready') {
            $planHash = Get-LambekPlanHash -Steps $steps.ToArray() -Order $order
        }

        # Plan risk: the highest risk of its steps
        $risk = 'low'
        foreach ($step in $steps) {
            if ($step.Risk -eq 'high') { $risk = 'high' }
            elseif ($step.Risk -eq 'medium' -and $risk -ne 'high') { $risk = 'medium' }
        }

        [pscustomobject]@{
            PSTypeName = 'Lambek.Plan'
            Status     = $status
            Risk       = $risk
            Original   = $Text
            Steps      = $steps.ToArray()
            Edges      = @($edges | ForEach-Object { [pscustomobject]@{ From = $_.From + 1; To = $_.To + 1; Reason = $_.Reason } })
            Cycles     = @($cycles | ForEach-Object { , [int[]] @($_ | ForEach-Object { $_ + 1 }) })
            Order      = $order
            Levels     = @($sorting.Levels | ForEach-Object { , [int[]] @($_ | ForEach-Object { $_ + 1 }) })
            Questions  = $questions.ToArray()
            PlanHash   = $planHash
        }
    }
}

function Get-LambekConflict {
    param(
        [pscustomobject] $First,
        [pscustomobject] $Second
    )

    # Write then read, write then write, read then write
    foreach ($written in $First.Writes) {
        foreach ($used in @($Second.Reads) + @($Second.Writes)) {
            if (Test-LambekPathOverlap -PathA $written -PathB $used) {
                return "step $($First.Step) changes $written"
            }
        }
    }
    foreach ($read in $First.Reads) {
        foreach ($written in $Second.Writes) {
            if (Test-LambekPathOverlap -PathA $read -PathB $written) {
                return "step $($Second.Step) changes $written"
            }
        }
    }
    return $null
}
