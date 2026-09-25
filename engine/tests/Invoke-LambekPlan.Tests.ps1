BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Invoke-LambekPlan' {

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $source = Join-Path $root 'src'
        $archive = Join-Path $root 'archive'
        $audit = Join-Path $root 'audit.jsonl'

        New-Item -Path $source -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.log') -Value 'a'
        Set-Content -Path (Join-Path $source 'b.log') -Value 'b'
        Set-Content -Path (Join-Path $source 'c.tmp') -Value 'c'

        $text = "create the folder ""$archive"" then move the .log files in ""$source"" to ""$archive"" then delete the .tmp files in ""$source"""
        $plan = New-LambekPlan $text
    }

    Context 'Simulation' {
        It 'lists what each step would touch' {
            $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
            $simulation.Status | Should -Be 'Ready' -Because ($simulation.Steps.Message -join ' ')
            $simulation.Steps[1].Count | Should -Be 2
            $simulation.Steps[2].Affected | Should -Be @((Join-Path $source 'c.tmp'))
        }

        It 'changes nothing' {
            Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit | Out-Null
            Test-Path $archive | Should -BeFalse
            @(Get-ChildItem -Path $source).Count | Should -Be 3
        }

        It 'gives a confirmation code for a high-risk plan' {
            $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
            $simulation.Risk | Should -Be 'high'
            $simulation.ConfirmationCode | Should -Match '^[0-9A-F]{6}$'
        }

        It 'fails when a folder does not exist' {
            $missing = New-LambekPlan "delete the .log files in ""$(Join-Path $root 'nothing')"""
            $simulation = Invoke-LambekPlan -Plan $missing -Simulate -AuditPath $audit
            $simulation.Status | Should -Be 'Failed'
            $simulation.Steps[0].Message | Should -BeLike 'Cannot find path*'
        }

        It 'refuses a plan that is not ready' {
            $notReady = New-LambekPlan 'move the files'
            { Invoke-LambekPlan -Plan $notReady -Simulate -AuditPath $audit } | Should -Throw '*ready*'
        }
    }

    Context 'Approval' {
        It 'needs the confirmation code for a high-risk plan' {
            $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
            { Approve-LambekPlan -Simulation $simulation -AuditPath $audit } | Should -Throw '*confirmation code*'
            { Approve-LambekPlan -Simulation $simulation -Confirmation 'WRONG' -AuditPath $audit } | Should -Throw
        }

        It 'approves with the right code' {
            $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
            $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit
            $approval.PlanHash | Should -Be $plan.PlanHash
        }

        It 'approves a low-risk plan without a code' {
            $list = New-LambekPlan "list the files in ""$source"""
            $simulation = Invoke-LambekPlan -Plan $list -Simulate -AuditPath $audit
            $simulation.ConfirmationCode | Should -BeNullOrEmpty
            { Approve-LambekPlan -Simulation $simulation -AuditPath $audit } | Should -Not -Throw
        }
    }

    Context 'Execution' {
        BeforeEach {
            $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
            $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit
        }

        It 'runs every step in order' {
            $result = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
            $result.Status | Should -Be 'Completed' -Because (($result.Steps.Error + $result.Reason) -join ' ')
            $result.Steps.Status | Should -Be @('Completed', 'Completed', 'Completed')

            Test-Path (Join-Path $archive 'a.log') | Should -BeTrue
            Test-Path (Join-Path $archive 'b.log') | Should -BeTrue
            @(Get-ChildItem -Path $source).Count | Should -Be 0
        }

        It 'runs a low-risk plan without approval' {
            $list = New-LambekPlan "list the files in ""$source"""
            $result = Invoke-LambekPlan -Plan $list -AuditPath $audit
            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Output.Count | Should -Be 3
        }

        It 'returns generated code without running it' {
            $code = New-LambekPlan 'generate a powershell function named Get-Report'
            $result = Invoke-LambekPlan -Plan $code -AuditPath $audit
            $result.Steps[0].Output[0] | Should -BeLike 'function Get-Report*'
        }
    }

    Context 'Plan binding' {
        BeforeEach {
            $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
            $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit
        }

        It 'refuses a high-risk plan without approval' {
            $result = Invoke-LambekPlan -Plan $plan -AuditPath $audit
            $result.Status | Should -Be 'Refused'
            Test-Path $archive | Should -BeFalse
        }

        It 'refuses a script changed after approval' {
            $plan.Steps[2].Script = $plan.Steps[2].Script.Replace("'.tmp'", "'.log'")
            $result = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
            $result.Status | Should -Be 'Refused'
            $result.Reason | Should -BeLike '*changed*'
        }

        It 'refuses an approval made for another plan' {
            $other = New-LambekPlan "delete the .tmp files in ""$source"""
            $result = Invoke-LambekPlan -Plan $other -Approval $approval -AuditPath $audit
            $result.Status | Should -Be 'Refused'
        }

        It 'refuses when the files changed since the approval' {
            Set-Content -Path (Join-Path $source 'new.log') -Value 'new'
            $result = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
            $result.Status | Should -Be 'Refused'
            $result.Reason | Should -BeLike '*files changed*'
            Test-Path $archive | Should -BeFalse
        }

        It 'refuses an expired approval' {
            $approval.ExpiresAt = [datetime]::UtcNow.AddMinutes(-1)
            (Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit).Reason | Should -BeLike '*expired*'
        }
    }

    Context 'Audit log' {
        It 'records every event in a valid chain' {
            $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
            $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit
            Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit | Out-Null

            $events = Get-Content $audit | ForEach-Object { ($_ | ConvertFrom-Json).Event }
            $events | Should -Be @('Simulated', 'Approved', 'StepCompleted', 'StepCompleted', 'StepCompleted', 'Completed')
            (Test-LambekAudit -Path $audit).IsValid | Should -BeTrue
        }

        It 'detects a changed entry' {
            Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit | Out-Null
            Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit | Out-Null

            $lines = Get-Content $audit
            $lines[0] = $lines[0] -replace '"Detail":"[^"]*"', '"Detail":"Hidden"'
            Set-Content -Path $audit -Value $lines

            $check = Test-LambekAudit -Path $audit
            $check.IsValid | Should -BeFalse
            $check.BrokenAt | Should -Be 1
        }

        It 'detects a removed entry' {
            1..3 | ForEach-Object { Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit | Out-Null }

            $lines = Get-Content $audit
            Set-Content -Path $audit -Value @($lines[0], $lines[2])

            (Test-LambekAudit -Path $audit).BrokenAt | Should -Be 2
        }
    }
}
