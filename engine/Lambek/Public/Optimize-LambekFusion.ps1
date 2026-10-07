function Optimize-LambekFusion {
    <#
    .SYNOPSIS
        Measures the scorers on the calibration split and fits the GPS fusion: bias and covariance of each scorer,
        BLUE weights, chi-square limit, isotonic calibration and conformal threshold.
    .EXAMPLE
        Optimize-LambekFusion -Path ./bench/requests.json -OutFile ./engine/Lambek/Data/fusion.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('all', 'calibration', 'test', 'hard')]
        [string] $Split = 'calibration',

        [string] $OutFile
    )

    # One row per request and action: what each scorer says, and whether it is the action the request means.
    # A request with a question for answer has no known action: it teaches nothing and is left out
    $names = Get-LambekSignalName
    $rows = [System.Collections.Generic.List[double[]]]::new()
    $right = [System.Collections.Generic.List[bool]]::new()
    $request = [System.Collections.Generic.List[int]]::new()
    $number = 0
    foreach ($case in Get-LambekBenchmarkCase -Path $Path -Split $Split) {
        if ($case.Expected.Status -notin 'Ready', 'Unknown') { continue }
        $evidence = Get-LambekIntentEvidence -Request (ConvertTo-LambekRequest -Text $case.Text)
        foreach ($row in Get-LambekSignalRow -Evidence $evidence) {
            $rows.Add($row.Values)
            $right.Add($case.Expected.Status -eq 'Ready' -and $row.Action -eq $case.Expected.Action)
            $request.Add($number)
        }
        $number++
    }

    # Families that fail together: the words, and the structure
    $families = [string[][]] @(, [string[]] @('Cosine', 'WordJaccard', 'NGramJaccard', 'Edit')) + @(, [string[]] @('Grammar', 'Structure'))
    $actions = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($pack in $script:Packs.Values) { foreach ($action in $pack.Actions) { [void] $actions.Add($action.Id) } }
    $fusion = [LambekFusion]::Fit([string[]] $names, [double[][]] $rows.ToArray(), [bool[]] $right.ToArray(), [int[]] $request.ToArray(), $families, [string[]] @($actions))
    if ($OutFile) { Set-Content -LiteralPath $OutFile -Value $fusion.Save() -Encoding utf8NoBOM }

    [pscustomobject]@{
        PSTypeName  = 'Lambek.Fusion'
        Requests    = $number
        Rows        = $rows.Count
        Weights     = [ordered]@{} + (Get-LambekNamedValue -Names $names -Values $fusion.Weights)
        Bias        = [ordered]@{} + (Get-LambekNamedValue -Names $names -Values $fusion.Bias)
        Sigma       = [math]::Round([math]::Sqrt($fusion.Variance), 4)
        Independent = [math]::Round($fusion.Independent($fusion.Weights), 2)
        ChiSquare   = [math]::Round($fusion.ChiSquareLimit, 3)
        Conformal   = [math]::Round($fusion.ConformalScore, 4)
        Fusion      = $fusion
    }
}

function Get-LambekSignalName {
    # The satellites: two structural (grammar, meaning on the reduction), four on the words
    return [string[]] @('Grammar', 'Structure', 'Cosine', 'WordJaccard', 'NGramJaccard', 'Edit')
}

function Get-LambekSignalRow {
    param([pscustomobject] $Evidence)

    # For each action, the scores of its best example (best by the words, as the choice does)
    $scoring = Get-LambekScoring
    $fields = @{ Cosine = 'Cosine'; WordJaccard = 'WordJaccard'; NGramJaccard = 'NGramJaccard'; Edit = 'EditSimilarity' }
    foreach ($candidate in $Evidence.Candidates) {
        $best = $null
        $bestText = -1.0
        foreach ($example in $candidate.Examples) {
            $text = 0.0
            foreach ($name in $fields.Keys) { $text += $scoring.Weights[$name] * $example.($fields[$name]) }
            if ($text -gt $bestText) { $bestText = $text; $best = $example }
        }
        $structure = 0.5
        if ($candidate.PSObject.Properties['StructureScore']) { $structure = [double] $candidate.StructureScore }
        [pscustomobject]@{
            Action = $candidate.Action.Id
            Values = [double[]] @([double] $candidate.GrammarScore, $structure, [double] $best.Cosine, [double] $best.WordJaccard, [double] $best.NGramJaccard, [double] $best.EditSimilarity)
        }
    }
}

function Get-LambekNamedValue {
    param([string[]] $Names, [double[]] $Values)
    $named = [ordered]@{}
    for ($k = 0; $k -lt $Names.Count; $k++) { $named[$Names[$k]] = [math]::Round($Values[$k], 4) }
    return $named
}
