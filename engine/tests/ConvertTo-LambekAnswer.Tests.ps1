BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'ConvertTo-LambekAnswer' {

    It 'answers "<Text>"' -ForEach @(
        @{ Text = 'Delete the files older than 30 days in C:\Temp larger than 5 GB'; Answer = 'I will delete the files older than 30 days larger than 5 GB in C:\Temp.' }
        @{ Text = 'list the files smaller than 500 KB in C:\Data'; Answer = 'I will list the files smaller than 500 KB in C:\Data.' }
        @{ Text = 'rename report.txt to "summary.txt"'; Answer = 'I will rename report.txt to summary.txt.' }
        @{ Text = 'create a folder named "logs" in C:\Temp'; Answer = 'I will create a folder named logs in C:\Temp.' }
        @{ Text = 'generate a powershell function named Get-Report'; Answer = 'I will generate a PowerShell function named Get-Report.' }
        @{ Text = 'supprime les fichiers .log de plus de 5 Go dans "D:\Mes Logs"'; Answer = 'Je vais supprimer les fichiers .log de plus de 5 Go dans D:\Mes Logs.' }
        @{ Text = 'supprime les fichiers de plus de 1 an dans C:\Temp'; Answer = 'Je vais supprimer les fichiers de plus de 1 an dans C:\Temp.' }
    ) {
        New-LambekPlan $Text | ConvertTo-LambekAnswer | Should -BeExactly $Answer
    }

    It 'numbers the steps of a plan' {
        $answer = New-LambekPlan 'create the folder D:\Archive then move the .log files in C:\Temp to D:\Archive' | ConvertTo-LambekAnswer
        $lines = $answer -split [Environment]::NewLine
        $lines[0] | Should -Be 'I will do 2 steps:'
        $lines[1] | Should -Be '1. Create the folder D:\Archive.'
        $lines[2] | Should -Be '2. Move the .log files from C:\Temp to D:\Archive.'
    }

    It 'asks the question when the plan is not ready' {
        New-LambekPlan 'move the files' | ConvertTo-LambekAnswer | Should -Be 'Where to?'
    }

    It 'asks in French' {
        New-LambekPlan 'cree un dossier dans D:\Archive' | ConvertTo-LambekAnswer | Should -Be 'Quel nom doit-il porter ?'
    }
}

Describe 'Format-LambekHumanValue' {

    It 'writes <Expected>' -ForEach @(
        @{ Name = 'MinSize'; Value = 5368709120L; Expected = '5 GB' }
        @{ Name = 'MinSize'; Value = 1572864L; Expected = '1.5 MB' }
        @{ Name = 'OlderThan'; Value = [timespan]::FromDays(30); Expected = '30 days' }
        @{ Name = 'OlderThan'; Value = [timespan]::FromDays(1); Expected = '1 day' }
        @{ Name = 'OlderThan'; Value = [timespan]::FromDays(14); Expected = '2 weeks' }
        @{ Name = 'OlderThan'; Value = [timespan]::FromDays(365); Expected = '1 year' }
        @{ Name = 'Kind'; Value = 'Directory'; Expected = 'folder' }
    ) {
        InModuleScope Lambek -Parameters $_ {
            $units = (Get-LambekLexicon -Language 'en').Answer.Units
            Format-LambekHumanValue -Name $Name -Value $Value -Units $units | Should -Be $Expected
        }
    }
}
