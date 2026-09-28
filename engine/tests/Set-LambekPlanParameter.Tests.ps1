BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Set-LambekPlanParameter' {

    BeforeAll {
        $plan = New-LambekPlan 'delete the .log files in C:\Temp'
    }

    It 'changes a parameter and renders a new checked script' {
        $edited = Set-LambekPlanParameter -Plan $plan -Step 1 -Name Extension -Value '.tmp'
        $edited.Status | Should -Be 'Ready'
        $edited.Steps[0].Script | Should -BeLike "*Extension -EQ '.tmp'*"
        $edited.Steps[0].Check.IsValid | Should -BeTrue
    }

    It 'gives the edited plan a new hash and keeps the original' {
        $edited = Set-LambekPlanParameter -Plan $plan -Step 1 -Name Extension -Value '.tmp'
        $edited.PlanHash | Should -Not -Be $plan.PlanHash
        $plan.Steps[0].Parameters.Extension | Should -Be '.log'
    }

    It 'gives the same hash as the same request written by hand' {
        $edited = Set-LambekPlanParameter -Plan $plan -Step 1 -Name Extension -Value '.tmp'
        $typed = New-LambekPlan 'delete the .tmp files in C:\Temp'
        $edited.PlanHash | Should -Be $typed.PlanHash
    }

    It 'reads sizes and durations: <Value>' -ForEach @(
        @{ Name = 'MinSize'; Value = '5 GB'; Expected = 5GB }
        @{ Name = 'MinSize'; Value = '1048576'; Expected = 1MB }
        @{ Name = 'OlderThan'; Value = '30 days'; Expected = [timespan]::FromDays(30) }
        @{ Name = 'OlderThan'; Value = '2592000s'; Expected = [timespan]::FromDays(30) }
    ) {
        $edited = Set-LambekPlanParameter -Plan $plan -Step 1 -Name $Name -Value $Value
        $edited.Steps[0].Parameters[$Name] | Should -Be $Expected
    }

    It 'removes a parameter with an empty value' {
        $edited = Set-LambekPlanParameter -Plan $plan -Step 1 -Name Extension -Value ''
        $edited.Steps[0].Parameters.Contains('Extension') | Should -BeFalse
    }

    It 'asks again when a required parameter is removed' {
        $edited = Set-LambekPlanParameter -Plan $plan -Step 1 -Name Path -Value ''
        $edited.Status | Should -Be 'NeedsInput'
        $edited.Questions | Should -Contain 'Step 1: In which folder?'
    }

    It 'completes a step that needed input' {
        $incomplete = New-LambekPlan 'move the files in C:\Temp'
        $edited = Set-LambekPlanParameter -Plan $incomplete -Step 1 -Name Destination -Value 'D:\Archive'
        $edited.Status | Should -Be 'Ready'
        $edited.Steps[0].Script | Should -BeLike "*Move-Item -Destination 'D:\Archive'*"
    }

    It 'updates the dependencies between steps' {
        $two = New-LambekPlan 'list the files in C:\A then delete the .tmp files in D:\B'
        $two.Edges.Count | Should -Be 0
        $edited = Set-LambekPlanParameter -Plan $two -Step 2 -Name Path -Value 'C:\A'
        $edited.Edges.Count | Should -Be 1
    }

    It 'keeps text as a literal, even an injection attempt' {
        $edited = Set-LambekPlanParameter -Plan $plan -Step 1 -Name Path -Value "C:\x'; Remove-Item C:\ -Recurse; '"
        $edited.Steps[0].Check.IsValid | Should -BeTrue
        $edited.Steps[0].Script | Should -BeLike "*-LiteralPath 'C:\x''; Remove-Item C:\ -Recurse; '''*"
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'an unknown parameter'; Name = 'Color'; Value = 'red'; Message = '*no parameter*' }
        @{ Case = 'a wrong size'; Name = 'MinSize'; Value = 'big'; Message = '*must be a size*' }
        @{ Case = 'a wrong duration'; Name = 'OlderThan'; Value = 'soon'; Message = '*must be a duration*' }
    ) {
        { Set-LambekPlanParameter -Plan $plan -Step 1 -Name $Name -Value $Value } | Should -Throw $Message
    }

    It 'rejects a choice that is not allowed' {
        $code = New-LambekPlan 'generate a powershell function named Get-Report'
        { Set-LambekPlanParameter -Plan $code -Step 1 -Name Kind -Value 'Spaceship' } | Should -Throw '*must be one of*'
    }

    It 'rejects a step that does not exist' {
        { Set-LambekPlanParameter -Plan $plan -Step 3 -Name Path -Value 'C:\A' } | Should -Throw '*does not exist*'
    }
}
