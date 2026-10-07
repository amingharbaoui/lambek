BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Add-RunPlan {
        param([string] $Text, [int] $Times = 1)
        $plan = New-LambekPlan $Text
        InModuleScope Lambek -Parameters @{ Step = $plan.Steps[0]; Times = $Times } {
            for ($i = 0; $i -lt $Times; $i++) { Add-LambekHistory -Step $Step }
        }
    }
}

Describe 'Adaptation from the plans the user runs' {

    BeforeEach {
        $history = Join-Path $TestDrive "$([guid]::NewGuid()).jsonl"
        InModuleScope Lambek -Parameters @{ Path = $history } { $script:HistoryPath = $Path; $script:History = $null; $script:Incognito = $false }
    }

    It 'remembers each plan run, with how each scorer voted' {
        Add-RunPlan 'copy the .log files in C:\A to D:\Backup'
        $line = Get-Content -LiteralPath $history | ConvertFrom-Json
        $line.Action | Should -Be 'files.copy'
        $line.Votes.Grammar | Should -BeGreaterThan 0
        $line.Habits.Destination | Should -Be 'D:\Backup'
    }

    It 'makes a place a habit after it was used a few times, and says so' {
        Add-RunPlan 'copy the .log files in C:\A to D:\Backup' -Times 3
        $plan = New-LambekPlan 'copy the .pdf files in C:\Docs'
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Parameters.Destination | Should -Be 'D:\Backup'
        $plan.Steps[0].FromHabit | Should -Be @('Destination')
        ConvertTo-LambekAnswer -Plan $plan | Should -BeLike '*D:\Backup, as usual*'
    }

    It 'does not make a habit of a place used once, or of two places used alike' {
        Add-RunPlan 'copy the .log files in C:\A to D:\Backup'
        (New-LambekPlan 'copy the .pdf files in C:\Docs').Status | Should -Be 'NeedsInput'
        Add-RunPlan 'copy the .log files in C:\A to E:\Other' -Times 2
        Add-RunPlan 'copy the .log files in C:\A to D:\Backup' -Times 1
        (New-LambekPlan 'copy the .pdf files in C:\Docs').Status | Should -Be 'NeedsInput'
    }

    It 'lets old habits fade' {
        Add-RunPlan 'copy the .log files in C:\A to D:\Backup' -Times 3
        InModuleScope Lambek { Get-LambekHabit -ActionId 'files.copy' -Name 'Destination' -Now ([datetime]::UtcNow.AddDays(90)) } | Should -BeNullOrEmpty
    }

    It 'moves the weights only as evidence builds up' {
        Add-RunPlan 'delete the .log files in C:\Temp' -Times 5
        $adaptation = Get-LambekAdaptation
        $adaptation.PlansRun | Should -Be 5
        $adaptation.Evidence | Should -BeGreaterThan 4
        [math]::Abs($adaptation.Weights.Grammar - $adaptation.DefaultWeights.Grammar) | Should -BeLessThan 0.1
        ($adaptation.Weights.Values | Measure-Object -Sum).Sum | Should -BeGreaterThan 0.99
    }

    It 'never lets what it learned make a change easier to start' {
        # Learned weights that trust only the words: the grammar alone would no longer decide
        $card = InModuleScope Lambek {
            $scoring = Get-LambekScoring
            $words = [pscustomobject]@{ Weights = [ordered]@{ Grammar = 0.0; Cosine = 0.25; WordJaccard = 0.25; NGramJaccard = 0.25; Edit = 0.25 }; Threshold = $scoring.Threshold; Margin = $scoring.Margin; Margins = $scoring.Margins; Correlation = $null }
            $evidence = Get-LambekIntentEvidence -Request (ConvertTo-LambekRequest 'remove the list of files in C:\A')
            New-LambekIntentCard -Evidence $evidence -Scoring $scoring -Adapted $words
        }
        $card.Status | Should -Not -Be 'Ready'
    }

    It 'keeps nothing from an incognito chat' {
        InModuleScope Lambek { $script:Incognito = $true }
        try { Add-RunPlan 'copy the .log files in C:\A to D:\Backup' }
        finally { InModuleScope Lambek { $script:Incognito = $false } }
        Test-Path -LiteralPath $history | Should -BeFalse
    }

    It 'forgets everything on demand' {
        Add-RunPlan 'copy the .log files in C:\A to D:\Backup' -Times 3
        Clear-LambekHistory -Confirm:$false
        (Get-LambekAdaptation).PlansRun | Should -Be 0
        (New-LambekPlan 'copy the .pdf files in C:\Docs').Status | Should -Be 'NeedsInput'
    }
}
