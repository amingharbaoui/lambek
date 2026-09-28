function ConvertTo-LambekPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Steps,

        [AllowEmptyCollection()]
        [string[]] $Dependency = @()
    )

    $questions = [System.Collections.Generic.List[string]]::new()
    foreach ($step in $Steps) {
        foreach ($question in $step.Questions) {
            $questions.Add("Step $($step.Step): $question")
        }
    }

    # Dependencies: a step that writes a resource goes before a later step that uses it
    $edges = [System.Collections.Generic.List[object]]::new()
    for ($a = 0; $a -lt $Steps.Count; $a++) {
        for ($b = $a + 1; $b -lt $Steps.Count; $b++) {
            $reason = Get-LambekConflict -First $Steps[$a] -Second $Steps[$b]
            if ($reason) {
                $edges.Add([pscustomobject]@{ From = $a; To = $b; Reason = $reason })
            }
        }
    }

    foreach ($item in $Dependency) {
        $from = [int] $item.Split('->')[0] - 1
        $to = [int] $item.Split('->')[-1] - 1
        if ($from -lt 0 -or $to -lt 0 -or $from -ge $Steps.Count -or $to -ge $Steps.Count) {
            throw "Dependency '$item' refers to a step that does not exist."
        }
        $edges.Add([pscustomobject]@{ From = $from; To = $to; Reason = 'manual' })
    }

    # Cycles (Tarjan) and order (Kahn)
    $cycles = Find-LambekCycle -NodeCount $Steps.Count -Edges $edges.ToArray()
    $sorting = Get-LambekTopologicalOrder -NodeCount $Steps.Count -Edges $edges.ToArray()

    foreach ($cycle in $cycles) {
        $numbers = ($cycle | ForEach-Object { $_ + 1 }) -join ', '
        $questions.Add("Steps $numbers depend on each other in a loop.")
    }

    # Plan status
    $statuses = @($Steps | ForEach-Object { $_.Status })
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
        $planHash = Get-LambekPlanHash -Steps $Steps -Order $order
    }

    # Plan risk: the highest risk of its steps
    $risk = 'low'
    foreach ($step in $Steps) {
        if ($step.Risk -eq 'high') { $risk = 'high' }
        elseif ($step.Risk -eq 'medium' -and $risk -ne 'high') { $risk = 'medium' }
    }

    return [pscustomobject]@{
        PSTypeName   = 'Lambek.Plan'
        Status       = $status
        Risk         = $risk
        Original     = $Text
        Steps        = $Steps
        Edges        = @($edges | ForEach-Object { [pscustomobject]@{ From = $_.From + 1; To = $_.To + 1; Reason = $_.Reason } })
        Cycles       = @($cycles | ForEach-Object { , [int[]] @($_ | ForEach-Object { $_ + 1 }) })
        Order        = $order
        Levels       = @($sorting.Levels | ForEach-Object { , [int[]] @($_ | ForEach-Object { $_ + 1 }) })
        Questions    = $questions.ToArray()
        PlanHash     = $planHash
        Dependencies = @($Dependency)
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
