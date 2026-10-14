function Optimize-LambekSpeech {
    <#
    .SYNOPSIS
        Fits the satellites that choose how Lambek says an answer, on the ways of saying answers a careful writer accepts.
    .DESCRIPTION
        Each case is told and asked in a conversation of its own, never written down and never mixed with what the
        user told. Every way Lambek builds of saying the answer is measured by the satellites, and the fusion is
        fitted as for the intents (bias and covariance of each satellite, chi-square limit): the best way is the one
        the case gives. Then each case is left out in turn, the fusion fitted on the others, and it is
        counted whether the way chosen for the case left out is its best one. The weights are those of the simplex
        (in steps of 0.05) that choose the best way for the most cases.
    .EXAMPLE
        Optimize-LambekSpeech -Path ./bench/speech.json -Language fr -OutFile ./engine/Lambek/Data/Speech/fr.speech.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Language,

        [string] $OutFile
    )

    $cases = @((Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json).Cases | Where-Object { $_.Language -eq $Language })
    $names = [string[]] @(Get-LambekSpeechSatellite)
    $saved = @{
        Told = $script:Told; Board = $script:Board; Journal = $script:ToldJournal; Incognito = $script:Incognito; Pending = $script:CategoryPending
        Proofs = $script:LastProofs; Problems = $script:ProblemStores; Frames = $script:SpeechFrames; Capture = $script:SpeechCapture
    }
    $found = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($case in $cases) {
            # A conversation of its own, that nothing before is in and that is never written down
            $script:Told = $null; $script:Board = $null; $script:ToldJournal = [System.Collections.Generic.List[object]]::new(); $script:Incognito = $true
            $script:CategoryPending = $null; $script:LastProofs = $null; $script:ProblemStores = $null; $script:SpeechFrames = $null
            $script:SpeechCapture = [System.Collections.Generic.List[object]]::new()
            foreach ($told in @($case.Told)) { $null = New-LambekPlan -Text $told }
            $null = New-LambekPlan -Text $case.Ask
            $ways = @($(if ($script:SpeechCapture.Count -gt 0) { $script:SpeechCapture[0] }) | Where-Object { $_ -and $_.Right })
            $missing = @(@($case.Best) | Where-Object { $best = $_; @($ways | Where-Object { $_.Text -ceq $best }).Count -eq 0 })
            if ($missing.Count -gt 0) {
                Write-Warning "$($case.Ask): '$($missing[0])' is not one of the ways Lambek reads right."
                continue
            }
            $found.Add([pscustomobject]@{ Case = $case; Ways = $ways })
        }
    }
    finally {
        $script:Told = $saved.Told; $script:Board = $saved.Board; $script:ToldJournal = $saved.Journal; $script:Incognito = $saved.Incognito
        $script:CategoryPending = $saved.Pending; $script:LastProofs = $saved.Proofs; $script:ProblemStores = $saved.Problems
        $script:SpeechFrames = $saved.Frames; $script:SpeechCapture = $saved.Capture
    }
    if ($found.Count -eq 0) { throw "No case of $Language to fit on." }

    $fit = {
        param([object[]] $entries)
        $rows = [System.Collections.Generic.List[double[]]]::new()
        $right = [System.Collections.Generic.List[bool]]::new()
        $request = [System.Collections.Generic.List[int]]::new()
        $number = 0
        foreach ($entry in $entries) {
            foreach ($way in $entry.Ways) { $rows.Add([double[]] $way.Satellites); $right.Add(@($entry.Case.Best) -ccontains $way.Text); $request.Add($number) }
            $number++
        }
        # The geometry of the satellites (bias, covariance) as for the intents; the weights, those that choose the
        # best way most often, searched on the simplex. The chi-square limit: the largest a best way of the cases had
        $families = [string[][]] @(, [string[]] @('Fluency', 'Whole'))
        $fusion = [LambekFusion]::Fit($names, [double[][]] $rows.ToArray(), [bool[]] $right.ToArray(), [int[]] $request.ToArray(), $families, [string[]] @())
        $fusion.Weights = [LambekFusion]::Simplex([double[][]] $rows.ToArray(), [bool[]] $right.ToArray(), [int[]] $request.ToArray(), 20)
        $fusion.Variance = $fusion.Spread($fusion.Weights)
        $limit = 0.0
        for ($i = 0; $i -lt $rows.Count; $i++) {
            if (-not $right[$i]) { continue }
            $limit = [math]::Max($limit, $fusion.ChiSquare($rows[$i], $fusion.Fuse($rows[$i], $fusion.Weights)))
        }
        $fusion.ChiSquareLimit = $limit
        $fusion
    }
    $chosen = {
        param($weighed, $entry)
        $scored = @(foreach ($way in $entry.Ways) { [pscustomobject]@{ Text = $way.Text; Score = $weighed.Fuse([double[]] $way.Satellites, $weighed.Weights) } })
        @($scored | Sort-Object -Stable @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Text' })[0].Text
    }
    $fusion = & $fit $found.ToArray()
    $kept = @($found | Where-Object { @($_.Case.Best) -ccontains (& $chosen $fusion $_) }).Count
    # Each case left out in turn
    $alone = 0
    for ($i = 0; $i -lt $found.Count; $i++) {
        $others = @(for ($j = 0; $j -lt $found.Count; $j++) { if ($j -ne $i) { $found[$j] } })
        if ($others.Count -eq 0) { continue }
        if (@($found[$i].Case.Best) -ccontains (& $chosen (& $fit $others) $found[$i])) { $alone++ }
    }
    if ($OutFile) { Set-Content -LiteralPath $OutFile -Value $fusion.Save() -Encoding utf8NoBOM }

    [pscustomobject]@{
        PSTypeName = 'Lambek.SpeechFusion'
        Language   = $Language
        Cases      = $found.Count
        Ways       = ($found | ForEach-Object { $_.Ways.Count } | Measure-Object -Sum).Sum
        Weights    = [ordered]@{} + (Get-LambekNamedValue -Names $names -Values $fusion.Weights)
        Best       = "$kept / $($found.Count)"
        LeftOut    = "$alone / $($found.Count)"
        ChiSquare  = [math]::Round($fusion.ChiSquareLimit, 3)
        Chosen     = @($found | ForEach-Object { [pscustomobject]@{ Ask = $_.Case.Ask; Chosen = (& $chosen $fusion $_); Best = @($_.Case.Best) } })
        Fusion     = $fusion
    }
}
