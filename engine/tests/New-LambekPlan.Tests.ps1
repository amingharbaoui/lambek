BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'New-LambekPlan' {

    Context 'Single step' {
        It 'builds a ready plan with a checked script' {
            $plan = New-LambekPlan 'Delete the files older than 30 days in C:\Temp larger than 5 GB'
            $plan.Status | Should -Be 'Ready'
            $plan.Steps.Count | Should -Be 1
            $plan.Steps[0].Check.IsValid | Should -BeTrue
            $plan.Steps[0].Script | Should -BeLike "*Get-ChildItem -LiteralPath 'C:\Temp'*"
            $plan.Steps[0].Script | Should -BeLike '*Length -GT 5368709120*'
        }

        It 'generates PowerShell code' {
            $plan = New-LambekPlan 'generate a powershell function named Get-Report'
            $plan.Status | Should -Be 'Ready'
            $plan.Steps[0].Output | Should -Be 'code'
            $plan.Steps[0].Script | Should -BeLike 'function Get-Report {*'
        }
    }

    Context 'Several steps' {
        BeforeAll {
            $plan = New-LambekPlan 'create the folder D:\Archive then move the .log files in C:\Temp to D:\Archive then delete the .tmp files in C:\Temp'
        }

        It 'creates one step per clause' {
            $plan.Steps.Count | Should -Be 3
            $plan.Steps.Action | Should -Be @('files.create', 'files.move', 'files.delete')
        }

        It 'starts a new step at "and" before an action: <Text>' -ForEach @(
            @{ Text = 'list the files in C:\A and delete the .tmp files in C:\A' }
            @{ Text = 'liste les fichiers dans C:\A et supprime les .tmp dans C:\A' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Steps.Count | Should -Be 2
            $plan.Status | Should -Be 'Ready'
        }

        It 'keeps "and" inside a step when it goes on with the same files' {
            (New-LambekPlan 'déplace les fichiers de C:\A et remets-les dans D:\B').Steps.Count | Should -Be 1
            (New-LambekPlan 'find the files named "copy and delete" in C:\A').Steps.Count | Should -Be 1
        }

        It 'links steps that use the same folder' {
            $plan.Edges.Count | Should -Be 2
            ($plan.Edges | Where-Object { $_.From -eq 1 -and $_.To -eq 2 }) | Should -Not -BeNullOrEmpty
            ($plan.Edges | Where-Object { $_.From -eq 2 -and $_.To -eq 3 }) | Should -Not -BeNullOrEmpty
        }

        It 'orders the steps' {
            $plan.Status | Should -Be 'Ready'
            $plan.Order | Should -Be @(1, 2, 3)
        }

        It 'works in French' {
            $french = New-LambekPlan 'cree le dossier D:\Archive puis deplace les fichiers .log dans C:\Temp vers D:\Archive'
            $french.Status | Should -Be 'Ready'
            $french.Edges.Count | Should -Be 1
        }

        It 'puts independent steps on the same level' {
            $independent = New-LambekPlan 'list the files in C:\A then list the files in D:\B'
            $independent.Edges.Count | Should -Be 0
            $independent.Levels.Count | Should -Be 1
        }
    }

    Context 'Problems' {
        It 'refuses a loop between steps' {
            $plan = New-LambekPlan 'list the files in C:\A then list the files in D:\B' -Dependency '1->2', '2->1'
            $plan.Status | Should -Be 'Invalid'
            $plan.Cycles.Count | Should -Be 1
            $plan.Questions | Should -Contain 'Steps 1, 2 depend on each other in a loop.'
            $plan.PlanHash | Should -BeNullOrEmpty
        }

        It 'rejects a dependency to a step that does not exist' {
            { New-LambekPlan 'list the files in C:\A' -Dependency '1->5' } | Should -Throw
        }

        It 'asks the missing information of each step' {
            $plan = New-LambekPlan 'move the files then list the files in C:\A'
            $plan.Status | Should -Be 'NeedsInput'
            $plan.Questions | Should -Contain 'Step 1: Where to?'
        }

        It 'runs an action said with a folder alone' -ForEach @(
            @{ Text = 'delete everything in C:\Temp' }
            @{ Text = 'list Downloads' }
            @{ Text = 'move C:\Temp to D:\Archive' }
            @{ Text = 'list the files on my desktop' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Status | Should -Be 'Ready'
            $plan.Questions | Should -BeNullOrEmpty
        }

        It 'reads the first folder as the source and the next one as the place: <Text>' -ForEach @(
            @{ Text = 'déplace mes téléchargements sur le bureau'; Source = 'Downloads'; Destination = 'Desktop' }
            @{ Text = 'deplace le fichiers dans pictures et mets le dans desktop'; Source = 'Pictures'; Destination = 'Desktop' }
            @{ Text = 'déplace les images de mes téléchargements dans mes images'; Source = 'Downloads'; Destination = 'Pictures' }
            @{ Text = 'copy the pdf files from C:\A into C:\B'; Source = 'C:\A'; Destination = 'C:\B' }
            @{ Text = 'move the files in C:\A to C:\B'; Source = 'C:\A'; Destination = 'C:\B' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Status | Should -Be 'Ready'
            $plan.Steps[0].Parameters.Source | Should -BeLike "*$Source"
            $plan.Steps[0].Parameters.Destination | Should -BeLike "*$Destination"
        }

        It 'reads "the folder X" as the folder itself: <Text>' -ForEach @(
            @{ Text = 'dans le dossier Pictures sais tu déplacer mes images vers Downloads'; Source = 'Pictures'; Destination = 'Downloads' }
            @{ Text = 'déplace les fichiers dans le dossier C:\Temp vers D:\X'; Source = 'C:\Temp'; Destination = 'D:\X' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Status | Should -Be 'Ready'
            $plan.Steps[0].Parameters.Source | Should -BeLike "*$Source"
            $plan.Steps[0].Parameters.Destination | Should -BeLike "*$Destination"
        }

        It 'reads the folder after the kind of file: <Text>' -ForEach @(
            @{ Text = 'deplace les images de pictures vers desktop'; Source = 'Pictures'; Destination = 'Desktop' }
            @{ Text = 'move all my pictures from pictures to desktop'; Source = 'Pictures'; Destination = 'Desktop' }
            @{ Text = 'copie les images depuis documents vers C:\Out'; Source = 'Documents'; Destination = 'C:\Out' }
            @{ Text = 'deplace toutes mes images de pictures vers desktop'; Source = 'Pictures'; Destination = 'Desktop' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Status | Should -Be 'Ready'
            $plan.Steps[0].Parameters.Source | Should -BeLike "*$Source"
            $plan.Steps[0].Parameters.Destination | Should -BeLike "*$Destination"
            $plan.Steps[0].Parameters.Kind | Should -Be 'image'
        }

        It 'keeps "de musique" a kind of file when no kind came before' {
            $plan = New-LambekPlan 'copie les fichiers de musique vers C:\Out'
            $plan.Steps[0].Parameters.Kind | Should -Be 'audio'
            $plan.Steps[0].Parameters.Contains('Source') | Should -BeFalse
            $plan.Questions | Should -Contain 'Step 1: Depuis quel dossier ?'
        }

        It 'reads a place said before the verb as part of the sentence' {
            $plan = New-LambekPlan 'dans le dossier Pictures sais tu déplacer mon image vers Downloads'
            $plan.Steps[0].Types | Should -BeLike 's s^l d^l d s *'
            $plan.Steps[0].Implied | Should -BeNullOrEmpty
        }

        It 'reads put and mettre as a move to the place that follows: <Text>' -ForEach @(
            @{ Text = 'mets les images de mes téléchargements dans mes images'; Source = 'Downloads'; Destination = 'Pictures' }
            @{ Text = 'move the .log files in C:\Temp and put them in D:\Old'; Source = 'C:\Temp'; Destination = 'D:\Old' }
            @{ Text = 'remet les fichiers qui sont dans desktop verrs pictures'; Source = 'Desktop'; Destination = 'Pictures' }
            @{ Text = 'déplace les fichiers de C:\A dnas D:\B'; Source = 'C:\A'; Destination = 'D:\B' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Status | Should -Be 'Ready'
            $plan.Steps[0].Action | Should -Be 'files.move'
            $plan.Steps[0].Parameters.Source | Should -BeLike "*$Source"
            $plan.Steps[0].Parameters.Destination | Should -BeLike "*$Destination"
        }

        It 'never repairs a word inside a path' {
            (New-LambekPlan 'list the files in C:\Vera\docs').Steps[0].Parameters.Path | Should -Be 'C:\Vera\docs'
        }

        It 'says which type the folder supplies' {
            (New-LambekPlan 'déplace mes téléchargements sur le bureau').Steps[0].Implied | Should -Be 'p'
            (New-LambekPlan 'move the files in C:\A to C:\B').Steps[0].Implied | Should -BeNullOrEmpty
        }

        It 'still asks for the place with one folder only' {
            $plan = New-LambekPlan 'move the files in C:\A'
            $plan.Status | Should -Be 'NeedsInput'
        }

        It 'still asks for the files when no folder is given' -ForEach @(
            @{ Text = 'move to Downloads' }
            @{ Text = 'delete' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Status | Should -Be 'NeedsInput'
        }

        It 'blocks a generated script that fails the safety check' {
            $plan = New-LambekPlan 'create a class named Get-Report'
            $plan.Status | Should -Be 'Invalid'
            $plan.Steps[0].Status | Should -Be 'Blocked'
        }

        It 'writes a function in another language than PowerShell' {
            $plan = New-LambekPlan 'generate a python function named Get-Report'
            $plan.Steps[0].Status | Should -Be 'Ready'
            $plan.Steps[0].Script | Should -BeLike 'def get_report():*'
        }

        It 'keeps an injection attempt inside a string' {
            $plan = New-LambekPlan "rename report.txt to ""x'; Remove-Item C:\ -Recurse; '"""
            $plan.Status | Should -Be 'Ready'
            $plan.Steps.Count | Should -Be 1
            $plan.Steps[0].Check.IsValid | Should -BeTrue
            $plan.Steps[0].Script | Should -Be "Rename-Item -LiteralPath 'report.txt' -NewName 'x''; Remove-Item C:\ -Recurse; '''"
        }
    }

    Context 'Plan hash' {
        It 'is the same for the same plan' {
            $first = New-LambekPlan 'delete the .tmp files in C:\Temp'
            $second = New-LambekPlan 'remove the .tmp files in C:\Temp'
            $first.PlanHash | Should -Be $second.PlanHash
        }

        It 'changes when the order changes' {
            $first = New-LambekPlan 'list the files in C:\A then list the files in D:\B'
            $second = New-LambekPlan 'list the files in D:\B then list the files in C:\A'
            $first.PlanHash | Should -Not -Be $second.PlanHash
        }
    }
}
