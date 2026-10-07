BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    # Rows for two scorers measuring the truth with independent noises of known variance (fixed, not random)
    function New-TestRows {
        param([double] $NoiseA, [double] $NoiseB, [switch] $Same)
        $rows = [System.Collections.Generic.List[double[]]]::new()
        $right = [System.Collections.Generic.List[bool]]::new()
        $request = [System.Collections.Generic.List[int]]::new()
        # Walsh sequences: the two noises and the truth are orthogonal over every eight rows
        $truths = @(0, 0, 0, 0, 1, 1, 1, 1)
        $first = @(1, -1, 1, -1, 1, -1, 1, -1)
        $second = @(1, 1, -1, -1, 1, 1, -1, -1)
        for ($i = 0; $i -lt 400; $i++) {
            $truth = [double] $truths[$i % 8]
            $a = $truth + $NoiseA * $first[$i % 8]
            $b = $truth + $NoiseB * $second[$i % 8]
            if ($Same) { $b = $a }
            $rows.Add([double[]] @($a, $b))
            $right.Add($truth -eq 1)
            $request.Add([int] [math]::Floor($i / 8))
        }
        return [pscustomobject]@{ Rows = [double[][]] $rows.ToArray(); Right = [bool[]] $right.ToArray(); Request = [int[]] $request.ToArray() }
    }
}

Describe 'GPS fusion of the scorers' {

    It 'weighs independent scorers by the inverse of their variance (BLUE)' {
        $data = New-TestRows -NoiseA 0.1 -NoiseB 0.2
        $fusion = [LambekFusion]::Fit([string[]] @('A', 'B'), $data.Rows, $data.Right, $data.Request, [string[][]] @(), [string[]] @())
        [math]::Round($fusion.Weights[0] / $fusion.Weights[1], 1) | Should -Be 4
        [math]::Round($fusion.Weights[0] + $fusion.Weights[1], 6) | Should -Be 1
    }

    It 'counts two copies of one scorer as one independent signal (Kish)' {
        $data = New-TestRows -NoiseA 0.1 -NoiseB 0.1 -Same
        $fusion = [LambekFusion]::Fit([string[]] @('A', 'B'), $data.Rows, $data.Right, $data.Request, [string[][]] @(), [string[]] @())
        [math]::Round($fusion.Independent([double[]] @(0.5, 0.5)), 2) | Should -Be 1
        $other = New-TestRows -NoiseA 0.1 -NoiseB 0.1
        $apart = [LambekFusion]::Fit([string[]] @('A', 'B'), $other.Rows, $other.Right, $other.Request, [string[][]] @(), [string[]] @())
        $apart.Independent([double[]] @(0.5, 0.5)) | Should -BeGreaterThan 1.5
    }

    It 'never trusts a scorer upside down: no weight below zero' {
        $fusion = [LambekFusion]::new()
        $fusion.Names = [string[]] @('A', 'B', 'C')
        $fusion.Covariance = [double[][]] @([double[]] @(1.0, 0.9, 0.0), [double[]] @(0.9, 1.0, 0.0), [double[]] @(0.0, 0.0, 4.0))
        $weights = $fusion.Blue([bool[]] @($true, $true, $true))
        @($weights | Where-Object { $_ -lt 0 }).Count | Should -Be 0
        [math]::Round(($weights | Measure-Object -Sum).Sum, 6) | Should -Be 1
    }

    It 'inverts a matrix exactly enough: A times its inverse is the identity' {
        $matrix = [double[,]]::new(3, 3)
        $values = @(4, 1, 2, 1, 3, 0, 2, 0, 5)
        for ($k = 0; $k -lt 9; $k++) { $matrix[[math]::Floor($k / 3), ($k % 3)] = $values[$k] }
        $inverse = [LambekFusion]::Invert($matrix)
        for ($i = 0; $i -lt 3; $i++) {
            for ($j = 0; $j -lt 3; $j++) {
                $sum = 0.0
                for ($k = 0; $k -lt 3; $k++) { $sum += $matrix[$i, $k] * $inverse[$k, $j] }
                [math]::Round($sum, 9) | Should -Be $(if ($i -eq $j) { 1 } else { 0 })
            }
        }
    }

    It 'calibrates with isotonic regression: the probability never goes down as the score goes up' {
        $fusion = InModuleScope Lambek { Get-LambekFusion }
        $probabilities = @($fusion.CalibrationProbability)
        for ($k = 1; $k -lt $probabilities.Count; $k++) { $probabilities[$k] | Should -BeGreaterOrEqual $probabilities[$k - 1] }
        $fusion.Probability(-1) | Should -BeLessThan 0.1
        $fusion.Probability(1) | Should -BeGreaterThan 0.9
    }

    It 'follows the bias of a scorer with a Kalman filter' {
        $data = New-TestRows -NoiseA 0.1 -NoiseB 0.2
        $fusion = [LambekFusion]::Fit([string[]] @('A', 'B'), $data.Rows, $data.Right, $data.Request, [string[][]] @(), [string[]] @())
        $before = $fusion.DriftVariance[0]
        # Scorer A now reads 0.3 too high on every confirmed plan
        for ($k = 0; $k -lt 50; $k++) { $fusion.Observe([double[][]] @(, [double[]] @(1.3, 1.0)), [bool[]] @($true), 0.0001) }
        [math]::Round($fusion.Drift[0] + $fusion.Bias[0], 1) | Should -Be 0.3
        $fusion.DriftVariance[0] | Should -BeLessThan $before
    }

    It 'keeps what it fitted when saved and read back' {
        $fusion = InModuleScope Lambek { Get-LambekFusion }
        $again = [LambekFusion]::Load($fusion.Save())
        $again.Weights | Should -Be $fusion.Weights
        $again.ChiSquareLimit | Should -Be $fusion.ChiSquareLimit
        $again.Actions | Should -Be $fusion.Actions
    }
}

Describe 'GPS integrity of a choice' {

    It 'is available for a clear request: <Text>' -ForEach @(
        @{ Text = 'delete the .log files in C:\Temp' }
        @{ Text = 'supprime les fichiers .tmp dans C:\Temp' }
    ) {
        $card = ConvertTo-LambekRequest $Text | Resolve-LambekIntent
        $card.Status | Should -Be 'Ready'
        $gps = $card.Integrity.Gps
        $gps.Available | Should -BeTrue
        $gps.Margin | Should -BeGreaterThan $gps.Protection
        $gps.ChiSquare | Should -BeLessOrEqual $gps.Limit
        $gps.Probability | Should -BeGreaterOrEqual $gps.Needed
    }

    It 'asks instead of deleting when one signal alone decides (multipath): <Text>' -ForEach @(
        @{ Text = 'delete the listing of the .log files in C:\Temp' }
        @{ Text = 'supprime la liste des fichiers .log dans C:\Temp' }
    ) {
        $card = ConvertTo-LambekRequest $Text | Resolve-LambekIntent
        $card.Status | Should -Not -Be 'Ready'
        $card.Integrity.Gps.Available | Should -BeFalse
        $card.Integrity.Gps.Reasons | Should -Contain 'protection'
    }

    It 'gives the same verdict whatever the user taught it before' {
        $first = (ConvertTo-LambekRequest 'delete the .log files in C:\Temp' | Resolve-LambekIntent).Integrity.Gps
        InModuleScope Lambek { $fusion = Get-LambekFusion; for ($k = 0; $k -lt $fusion.Drift.Count; $k++) { $fusion.Drift[$k] = 0.5 } }
        try {
            $again = (ConvertTo-LambekRequest 'delete the .log files in C:\Temp' | Resolve-LambekIntent).Integrity.Gps
            $again.Margin | Should -Be $first.Margin
            $again.Available | Should -Be $first.Available
        }
        finally { InModuleScope Lambek { $fusion = Get-LambekFusion; for ($k = 0; $k -lt $fusion.Drift.Count; $k++) { $fusion.Drift[$k] = 0 } } }
    }

    It 'says nothing about an action it was never fitted on' {
        InModuleScope Lambek { Get-LambekGpsIntegrity -Evidence (Get-LambekIntentEvidence -Request (ConvertTo-LambekRequest 'delete the .log files in C:\Temp')) -Winner 'notes.delete' -Risk high } | Should -BeNullOrEmpty
    }

    It 'lets the meaning of the sentence vote for its action, and against the others' {
        $rows = InModuleScope Lambek { Get-LambekSignalRow -Evidence (Get-LambekIntentEvidence -Request (ConvertTo-LambekRequest 'delete the .log files in C:\Temp')) }
        $structure = [array]::IndexOf((InModuleScope Lambek { Get-LambekSignalName }), 'Structure')
        ($rows | Where-Object Action -EQ 'files.delete').Values[$structure] | Should -Be 1
        ($rows | Where-Object Action -EQ 'files.list').Values[$structure] | Should -Be 0
    }

    It 'explains its verdict when asked why' {
        $plan = New-LambekPlan 'delete the .log files in C:\Temp'
        (Resolve-LambekFollowUp -Plan $plan -Text 'why').Answer | Should -BeLike '*Integrity: margin * for a protection level of *: available.*'
    }
}

Describe 'Belief across the turns of a chat' {

    It 'stays on the action of the conversation, and starts again on a surprise' {
        InModuleScope Lambek {
            $list = @((New-LambekPlan 'list the .log files in C:\Temp').Steps[0].Reading.Rows)
            $belief = Get-LambekBelief -Belief $null -Rows $list
            $belief['files.list'] | Should -BeGreaterThan 0.5
            $again = Get-LambekBelief -Belief $belief -Rows $list -Turns 1
            $again['files.list'] | Should -BeGreaterOrEqual $belief['files.list']
            $delete = @((New-LambekPlan 'delete the .log files in C:\Temp').Steps[0].Reading.Rows)
            $moved = Get-LambekBelief -Belief $again -Rows $delete -Turns 2
            $moved['files.delete'] | Should -BeGreaterThan 0.5
        }
    }
}
