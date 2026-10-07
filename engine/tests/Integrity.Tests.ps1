BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Integrity of a decision' {

    BeforeAll {
        # Two actions: the grammar backs the first, the words back the second
        $evidence = InModuleScope Lambek {
            function New-Candidate([string] $Id, [string] $Risk, [double] $Grammar, [double] $Text) {
                $example = [pscustomobject]@{ Cosine = $Text; WordJaccard = $Text; NGramJaccard = $Text; EditSimilarity = $Text }
                [pscustomobject]@{ Action = @{ Id = $Id; Risk = $Risk; Verbs = @() }; Pack = [pscustomobject]@{ Name = 'test' }; GrammarScore = $Grammar; Examples = @($example) }
            }
            [pscustomobject]@{ Candidates = @((New-Candidate 'test.erase' 'high' 1.0 0.3), (New-Candidate 'test.show' 'low' 0.0 0.5)) }
        }
    }

    It 'finds the scorers that would choose another action alone' {
        $integrity = InModuleScope Lambek -Parameters @{ Evidence = $evidence } { Get-LambekIntegrity -Evidence $Evidence -Scoring (Get-LambekScoring) }
        $integrity.Winner | Should -Be 'test.erase'
        @($integrity.Faults | Where-Object { $_.Without -contains 'Grammar' }).Action | Should -Be 'test.show'
    }

    It 'asks instead of acting when a risky choice rests on one family of signals' {
        $selection = InModuleScope Lambek -Parameters @{ Evidence = $evidence } { Select-LambekIntent -Evidence $Evidence -Scoring (Get-LambekScoring) }
        $selection.Status | Should -Be 'Ambiguous'
        $selection.Ranked[1].Action.Id | Should -Be 'test.show'
    }

    It 'counts how many signals are really independent' {
        $integrity = InModuleScope Lambek -Parameters @{ Evidence = $evidence } { Get-LambekIntegrity -Evidence $Evidence -Scoring (Get-LambekScoring) }
        $integrity.Signals | Should -Be 5
        $integrity.Independent | Should -BeGreaterThan 1
        $integrity.Independent | Should -BeLessThan 5
    }

    It 'puts the integrity on the card' {
        $card = ConvertTo-LambekRequest 'delete the .log files in C:\Temp' | Resolve-LambekIntent
        $card.Integrity.Winner | Should -Be 'files.delete'
        $card.Integrity.Faults | Should -BeNullOrEmpty
        $card.Readings | Should -Be 1
    }

    It 'takes the main verb as the head, past a place said first' {
        (ConvertTo-LambekRequest 'in C:\Logs delete the .log files' | Resolve-LambekGrammar).Head.Word | Should -Be 'delete'
    }

    It 'measures the correlation of the scorers on a benchmark' {
        $cases = @(
            @{ Id = 'X1'; Split = 'calibration'; Text = 'delete the .log files in C:\Temp'; Expected = @{ Status = 'Ready' } }
            @{ Id = 'X2'; Split = 'calibration'; Text = 'list the files in C:\A'; Expected = @{ Status = 'Ready' } }
            @{ Id = 'X3'; Split = 'calibration'; Text = 'copy report.txt to D:\B'; Expected = @{ Status = 'Ready' } }
        )
        $path = Join-Path $TestDrive 'bench.json'
        @{ Version = '1.0'; Cases = $cases } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
        $signal = Measure-LambekSignal -Path $path
        $signal.Correlation.Grammar.Grammar | Should -Be 1
        $signal.Correlation.Cosine.Edit | Should -Be $signal.Correlation.Edit.Cosine
        $signal.Independent | Should -BeGreaterThan 0
    }
}
