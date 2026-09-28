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
        $trace = [System.Collections.Generic.List[object]]::new()
        $clock = [System.Diagnostics.Stopwatch]::StartNew()

        # One Action Card per clause
        Send-LambekProgress -Stage 'Split'
        $clauses = @(Split-LambekClause -Text $Text)
        Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Split' -Detail "$($clauses.Count) step(s)"

        for ($i = 0; $i -lt $clauses.Count; $i++) {
            $units = 3 * $clauses.Count + 2
            Send-LambekProgress -Stage 'Read' -Step ($i + 1) -Percent (100 * (1 + 3 * $i) / $units)
            $request = ConvertTo-LambekRequest -Text $clauses[$i]
            $words = @($request.Entities | ForEach-Object { $_.Type }) -join ', '
            $detail = "$($request.Language), $($request.Terms.Count) term(s)"
            if ($words) { $detail += ", entities: $words" }
            if ($request.Corrections.Count -gt 0) { $detail += ", corrected: $(($request.Corrections | ForEach-Object { "$($_.From)->$($_.To)" }) -join ' ')" }
            Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Read' -Detail $detail -Step ($i + 1)

            Send-LambekProgress -Stage 'Match' -Step ($i + 1) -Percent (100 * (2 + 3 * $i) / $units)
            $card = $request | Resolve-LambekIntent
            $grammar = 'does not reduce to s'
            if ($card.IsSentence) { $grammar = 'reduces to s' }
            Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Type' -Detail "$($card.Types) $grammar" -Step ($i + 1)
            $match = 'no action'
            if ($card.Action) { $match = "$($card.Action) ($($card.Confidence))" }
            Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Match' -Detail "$match, $($card.Status)" -Step ($i + 1)

            $step = [pscustomobject]@{
                Step       = $i + 1
                Clause     = $clauses[$i]
                Language   = $card.Language
                Status     = $card.Status
                Confidence = $card.Confidence
                Types      = $card.Types
                Implied    = @($card.Implied)
                Action     = $card.Action
                Risk       = $card.Risk
                Parameters = $card.Parameters
                Questions  = @($card.Questions)
                Reads      = @()
                Writes     = @()
                Output     = $null
                Script     = $null
                Check      = $null
                CardHash   = $card.CardHash
            }

            Send-LambekProgress -Stage 'Check' -Step ($i + 1) -Percent (100 * (3 + 3 * $i) / $units) -Types (Format-LambekShownType -Step $step)
            $step = Complete-LambekStep -Step $step
            $steps.Add($step)
            if ($step.Script) {
                $check = 'passed'
                if (-not $step.Check.IsValid) { $check = 'blocked' }
                $detail = "script written, AST firewall $check"
                if ($step.Output -eq 'mcp') { $detail = "MCP call written, input schema $check" }
                Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Check' -Detail $detail -Step ($i + 1)
            }
        }

        Send-LambekProgress -Stage 'Order' -Percent (100 * (3 * $clauses.Count + 1) / (3 * $clauses.Count + 2))
        $plan = ConvertTo-LambekPlan -Text $Text -Steps $steps.ToArray() -Dependency $Dependency
        Add-LambekTrace -Trace $trace -Clock $clock -Stage 'Order' -Detail "$($plan.Edges.Count) dependency(ies), order $($plan.Order -join ', ')"
        $plan | Add-Member -NotePropertyName Trace -NotePropertyValue $trace.ToArray()
        $plan
    }
}

function Add-LambekTrace {
    param(
        [System.Collections.Generic.List[object]] $Trace,
        [System.Diagnostics.Stopwatch] $Clock,
        [string] $Stage,
        [string] $Detail,
        [int] $Step = 0
    )

    $Trace.Add([pscustomobject]@{
            Stage        = $Stage
            Step         = $Step
            Detail       = $Detail
            Milliseconds = [math]::Round($Clock.Elapsed.TotalMilliseconds, 1)
        })
    $Clock.Restart()
}
