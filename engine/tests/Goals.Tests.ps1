BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Goals, contracts and dialogue' {

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $audit = Join-Path $root 'audit.jsonl'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        # 1 KB, 2 KB and 4 KB of data, and a document of 8 KB
        foreach ($file in @(@('a.bin', 1KB), @('b.bin', 2KB), @('c.bin', 4KB), @('report.pdf', 8KB))) {
            [IO.File]::WriteAllBytes((Join-Path $root $file[0]), [byte[]]::new($file[1]))
        }
    }

    It 'frees the space asked with the fewest files: the largest first' {
        $plan = New-LambekPlan "free 3 KB in ""$root"" except the documents"
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Action | Should -Be 'files.free'

        $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
        $simulation.Steps[0].Affected | Should -Be @((Join-Path $root 'c.bin'))

        $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit
        $result = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
        $result.Status | Should -Be 'Completed' -Because (($result.Steps.Error + $result.Reason) -join ' ')
        Test-Path (Join-Path $root 'c.bin') | Should -BeFalse
        Test-Path (Join-Path $root 'report.pdf') | Should -BeTrue
        Test-Path (Join-Path $root 'a.bin') | Should -BeTrue
    }

    It 'checks on the disk that the step did what it promised' {
        $plan = New-LambekPlan "delete the .bin files in ""$root"""
        $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
        $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit
        $result = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
        $result.Steps[0].Unverified | Should -BeNullOrEmpty
        (Get-Content -LiteralPath $audit | Select-Object -Last 2 | Select-Object -First 1) | Should -BeLike '*checked*'
    }

    It 'says when something did not change as planned' {
        $step = [pscustomobject]@{ Action = 'files.delete'; Parameters = [ordered]@{ Path = $root } }
        $check = InModuleScope Lambek -Parameters @{ Step = $step; Item = (Get-Item (Join-Path $root 'a.bin')) } { Test-LambekEffect -Step $Step -Items @($Item) }
        $check.Verified | Should -BeFalse
        $check.Wrong | Should -Be @((Join-Path $root 'a.bin'))
    }

    It 'acts on the files of the plan before when told "them": <Text>' -ForEach @(
        @{ First = 'list the .log files in C:\Temp'; Text = 'delete them'; Action = 'files.delete'; Name = 'Path'; Value = 'C:\Temp' }
        @{ First = 'liste les images dans C:\Photos'; Text = 'déplace-les vers D:\Backup'; Action = 'files.move'; Name = 'Source'; Value = 'C:\Photos' }
    ) {
        $reply = Resolve-LambekFollowUp -Plan (New-LambekPlan $First) -Text $Text
        $reply.Plan.Status | Should -Be 'Ready'
        $reply.Plan.Steps[0].Action | Should -Be $Action
        $reply.Plan.Steps[0].Parameters[$Name] | Should -Be $Value
    }

    It 'reads its own answers back to the same plan: <Text>' -ForEach @(
        @{ Text = 'delete the .log files in C:\Temp' }
        @{ Text = 'move the .log files in C:\Temp to D:\Archive' }
        @{ Text = 'list the 5 largest files in C:\Data' }
        @{ Text = 'copy the images and videos from C:\A to D:\B' }
        @{ Text = 'delete the files in C:\A except the .log files' }
        @{ Text = 'supprime les fichiers .tmp dans C:\Temp' }
        @{ Text = 'déplace les 3 plus gros fichiers de C:\A vers D:\B' }
        @{ Text = 'free 10 GB in C:\Temp' }
    ) {
        # The sentence Lambek says is parsed again: it must give the same card, or the answer would say something else
        $plan = New-LambekPlan $Text
        $sentence = InModuleScope Lambek -Parameters @{ Step = $plan.Steps[0] } {
            Get-LambekStepSentence -Step $Step -Language $Step.Language -Units (Get-LambekLexicon -Language $Step.Language).Answer.Units
        }
        $again = New-LambekPlan $sentence
        $again.Steps[0].CardHash | Should -Be $plan.Steps[0].CardHash -Because $sentence
    }
}
