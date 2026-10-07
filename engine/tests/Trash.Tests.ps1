BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null

    function Invoke-TestPlan {
        param([pscustomobject] $Plan, [string] $Audit)
        $simulation = Invoke-LambekPlan -Plan $Plan -Simulate -AuditPath $Audit
        $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $Audit
        return Invoke-LambekPlan -Plan $Plan -Approval $approval -AuditPath $Audit
    }
}

Describe 'Trash' {

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $audit = Join-Path $root 'audit.jsonl'
        New-Item -Path (Join-Path $root 'sub') -ItemType Directory -Force | Out-Null
        'a' | Set-Content -LiteralPath (Join-Path $root 'a.tmp')
        'b' | Set-Content -LiteralPath (Join-Path $root 'sub/b.tmp')
        'c' | Set-Content -LiteralPath (Join-Path $root 'c.txt')
        $trash = & (Get-Module Lambek) { $script:TrashPath }
        Clear-LambekTrash -All -Confirm:$false
    }

    It 'moves deleted files to the trash instead of erasing them' {
        $result = Invoke-TestPlan -Plan (New-LambekPlan "delete the .tmp files in ""$root""") -Audit $audit
        $result.Status | Should -Be 'Completed' -Because (($result.Steps.Error + $result.Reason) -join ' ')
        Test-Path (Join-Path $root 'a.tmp') | Should -BeFalse
        Test-Path (Join-Path $root 'c.txt') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $trash -File -Recurse).Count | Should -Be 2
    }

    It 'puts every file back where it was' {
        Invoke-TestPlan -Plan (New-LambekPlan "delete the .tmp files in ""$root""") -Audit $audit | Out-Null
        $result = Invoke-TestPlan -Plan (New-LambekPlan 'restore the deleted files') -Audit $audit
        $result.Status | Should -Be 'Completed' -Because (($result.Steps.Error + $result.Reason) -join ' ')
        Test-Path (Join-Path $root 'a.tmp') | Should -BeTrue
        Test-Path (Join-Path $root 'sub/b.tmp') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $trash -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'erases for good when asked' {
        $plan = New-LambekPlan "delete the .tmp files in ""$root"" permanently"
        $plan.Steps[0].Parameters.Permanent | Should -Be 'yes'
        Invoke-TestPlan -Plan $plan -Audit $audit | Out-Null
        Test-Path (Join-Path $root 'a.tmp') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $trash -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'understands "restaure-les" after a deletion' {
        (New-LambekPlan 'restaure-les').Steps[0].Action | Should -Be 'files.restore'
    }

    It 'empties only the deletions older than the days kept' {
        $old = Join-Path $trash ([datetime]::Now.AddDays(-40).ToString('yyyyMMdd-HHmmss'))
        $new = Join-Path $trash ([datetime]::Now.AddDays(-2).ToString('yyyyMMdd-HHmmss'))
        foreach ($batch in $old, $new) {
            New-Item -Path $batch -ItemType Directory -Force | Out-Null
            'x' | Set-Content -LiteralPath (Join-Path $batch 'x.tmp')
        }
        Clear-LambekTrash -Confirm:$false
        Test-Path $old | Should -BeFalse
        Test-Path $new | Should -BeTrue
    }
}
