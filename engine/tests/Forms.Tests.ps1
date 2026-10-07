BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Invoke-TestPlan {
        param([pscustomobject] $Plan, [string] $Audit)
        $simulation = Invoke-LambekPlan -Plan $Plan -Simulate -AuditPath $Audit
        $approval = $null
        if ($simulation.ConfirmationCode) { $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $Audit }
        return Invoke-LambekPlan -Plan $Plan -Approval $approval -AuditPath $Audit
    }

    # Nothing learned before, in memory or on the disk
    function Clear-Form {
        InModuleScope Lambek {
            $script:Forms = @{}
            $script:Incognito = $false
            if (Test-Path -LiteralPath $script:FormsPath) { Remove-Item -LiteralPath $script:FormsPath }
        }
    }
}

Describe 'Turns of phrase learned from a rephrasing' {

    BeforeEach {
        Clear-Form
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $here = Join-Path $root 'here'
        $there = Join-Path $root 'there'
        New-Item -Path $here, $there -ItemType Directory | Out-Null
        'x' | Set-Content -LiteralPath (Join-Path $here 'x.txt')
        'y' | Set-Content -LiteralPath (Join-Path $there 'y.txt')
        $audit = Join-Path $root 'audit.jsonl'
    }

    AfterAll {
        Clear-Form
    }

    It 'learns the sentence not understood once its rephrasing ran, and reads it with other values' {
        $plan = New-LambekPlan "what is inside ""$here"""
        $plan.Status | Should -Not -Be 'Ready'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "list the files in ""$here"""
        $reply.Plan.Status | Should -Be 'Ready'
        $reply.Plan.Rephrased.Key | Should -Be 'what is inside _quoted_'
        $result = Invoke-TestPlan -Plan $reply.Plan -Audit $audit
        $result.Status | Should -Be 'Completed'
        $result.Learned[0].Word | Should -Be "what is inside ""$here"""

        $again = New-LambekPlan "what is inside ""$there"""
        $again.Status | Should -Be 'Ready'
        $again.Steps[0].Action | Should -Be 'files.list'
        $again.Steps[0].Parameters.Path | Should -Be $there
        # How it was read is said
        ($again | ConvertTo-LambekAnswer) | Should -BeLike "*read as list the files in ""$there""*"
    }

    It 'learns nothing before the rephrasing has run' {
        $plan = New-LambekPlan "what is inside ""$here"""
        Resolve-LambekFollowUp -Plan $plan -Text "list the files in ""$here""" | Out-Null
        (New-LambekPlan "what is inside ""$there""").Status | Should -Not -Be 'Ready'
    }

    It 'takes for a rephrasing only a request with the same values' {
        $plan = New-LambekPlan "what is inside ""$here"""
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "list the files in ""$there"""
        $reply.Plan.PSObject.Properties['Rephrased'] | Should -BeNullOrEmpty
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "list the .txt files in ""$here"""
        $reply.Plan.PSObject.Properties['Rephrased'] | Should -BeNullOrEmpty
    }

    It 'reads only the very sentence it learned' {
        $plan = New-LambekPlan "what is inside ""$here"""
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "list the files in ""$here"""
        Invoke-TestPlan -Plan $reply.Plan -Audit $audit | Out-Null
        (New-LambekPlan "what is inside ""$there"" exactly").Status | Should -Not -Be 'Ready'
    }

    It 'still asks before a change read through a learned sentence' {
        $plan = New-LambekPlan "I would like the .txt files in ""$here"" deleted"
        $plan.Status | Should -Not -Be 'Ready'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "delete the .txt files in ""$here"""
        Invoke-TestPlan -Plan $reply.Plan -Audit $audit | Out-Null
        $again = New-LambekPlan "I would like the .txt files in ""$there"" deleted"
        $again.Steps[0].Action | Should -Be 'files.delete'
        $again.Steps[0].Risk | Should -Not -Be 'low'
        # Nothing was deleted by reading it
        Test-Path -LiteralPath (Join-Path $there 'y.txt') | Should -BeTrue
        (Invoke-LambekPlan -Plan $again -Simulate -AuditPath $audit).ConfirmationCode | Should -Not -BeNullOrEmpty
    }

    It 'learns a sentence that is not about files' {
        $plan = New-LambekPlan 'whip up a python function named "report"'
        $plan.Status | Should -Not -Be 'Ready'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text 'generate a python function named "report"'
        $reply.Plan.Rephrased | Should -Not -BeNullOrEmpty
        InModuleScope Lambek -Parameters @{ Plan = $reply.Plan } { Invoke-LambekFormLearning -Plan $Plan | Out-Null }
        $again = New-LambekPlan 'whip up a python function named "invoice"'
        $again.Status | Should -Be 'Ready'
        $again.Steps[0].Action | Should -Be 'code.generate'
        $again.Steps[0].Parameters.Name | Should -Be 'invoice'
    }

    It 'keeps what it learned in a file, and reads it back' {
        $plan = New-LambekPlan "what is inside ""$here"""
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "list the files in ""$here"""
        Invoke-TestPlan -Plan $reply.Plan -Audit $audit | Out-Null
        $path = InModuleScope Lambek { $script:FormsPath }
        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).en.'what is inside _quoted_'.To | Should -Be 'list the files in {0}'
        InModuleScope Lambek { $script:Forms = $null }
        (New-LambekPlan "what is inside ""$there""").Status | Should -Be 'Ready'
    }

    It 'writes nothing in an incognito chat' {
        InModuleScope Lambek { $script:Incognito = $true }
        $plan = New-LambekPlan "what is inside ""$here"""
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "list the files in ""$here"""
        Invoke-TestPlan -Plan $reply.Plan -Audit $audit | Out-Null
        Test-Path -LiteralPath (InModuleScope Lambek { $script:FormsPath }) | Should -BeFalse
    }
}
