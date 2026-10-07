BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'ConvertTo-LambekAnswer' {

    It 'answers "<Text>"' -ForEach @(
        @{ Text = 'Delete the files older than 30 days in C:\Temp larger than 5 GB'; Answer = 'I''ll delete the files older than 30 days larger than 5 GB in C:\Temp.' }
        @{ Text = 'list the files smaller than 500 KB in C:\Data'; Answer = 'I''ll list the files smaller than 500 KB in C:\Data.' }
        @{ Text = 'rename report.txt to "summary.txt"'; Answer = 'I''ll rename report.txt to summary.txt.' }
        @{ Text = 'create a folder named "logs" in C:\Temp'; Answer = 'I''ll create a folder named "logs" in C:\Temp.' }
        @{ Text = 'generate a powershell function named Get-Report'; Answer = 'I''ll generate a PowerShell function named Get-Report.' }
        @{ Text = 'supprime les fichiers .log de plus de 5 Go dans "D:\Mes Logs"'; Answer = 'Je vais supprimer les fichiers .log de plus de 5 Go dans « D:\Mes Logs ».' }
        @{ Text = 'supprime les fichiers de plus de 1 an dans C:\Temp'; Answer = 'Je vais supprimer les fichiers de plus de 1 an dans C:\Temp.' }
    ) {
        $lines = (New-LambekPlan $Text | ConvertTo-LambekAnswer) -split "`n"
        $lines[0] | Should -BeExactly $Answer
    }

    It 'numbers the steps of a plan' {
        $answer = New-LambekPlan 'create the folder D:\Archive then move the .log files in C:\Temp to D:\Archive' | ConvertTo-LambekAnswer
        $lines = $answer -split "`n"
        $lines[0] | Should -Be 'I''ll do this in 2 steps:'
        $lines[1] | Should -Be '1. Create the folder D:\Archive.'
        $lines[2] | Should -Be '2. Move the .log files from C:\Temp to D:\Archive.'
    }

    It 'says nothing back for a ready plan when brief' {
        New-LambekPlan 'delete the .log files in C:\Temp' | ConvertTo-LambekAnswer -Brief | Should -BeNullOrEmpty
    }

    It 'keeps the questions when brief' {
        New-LambekPlan 'move the files' | ConvertTo-LambekAnswer -Brief | Should -Be "I need a few details:`n- Where to?`n- From which folder?"
    }

    It 'asks the question when the plan is not ready' {
        New-LambekPlan 'move the files in C:\A' | ConvertTo-LambekAnswer | Should -Be 'I need one more detail. Where to?'
    }

    It 'explains the risk: <Expected>' -ForEach @(
        @{ Text = 'list the files in C:\Data'; Expected = 'This only reads. Nothing on your computer changes.' }
        @{ Text = 'create the folder D:\Archive'; Expected = 'This only adds something new. Nothing that exists changes.' }
        @{ Text = 'move the files in C:\A to D:\B'; Expected = 'This changes things on your computer. Simulate first to see exactly what.' }
        @{ Text = 'delete the .log files in C:\Temp'; Expected = 'This changes files, but they can be brought back. Simulate first, then confirm with a code.' }
        @{ Text = 'delete the .log files in C:\Temp permanently'; Expected = 'This cannot be undone. Simulate first, then confirm with a code.' }
        @{ Text = 'generate a powershell function named Get-Report'; Expected = 'Here is the code, ready to copy.' }
    ) {
        $lines = (New-LambekPlan $Text | ConvertTo-LambekAnswer) -split "`n"
        $lines[-1] | Should -Be $Expected
    }

    It 'says why a step waits for another' {
        $answer = New-LambekPlan 'create the folder D:\Archive then move the .log files in C:\Temp to D:\Archive' | ConvertTo-LambekAnswer
        $answer | Should -BeLike '*Step 2 waits for step 1 because step 1 changes D:\Archive.*'
    }

    It 'says what it can do when nothing matches' {
        New-LambekPlan 'what is the weather' | ConvertTo-LambekAnswer | Should -Be "On this computer, I take care of files and code. Tell me what you'd like to do."
    }

    It 'answers small talk in the language of the message' -ForEach @(
        @{ Text = 'salut'; Expected = 'Bonjour ! Que voulez-vous faire ?' }
        @{ Text = 'Hello!'; Expected = 'Hello! What would you like to do?' }
        @{ Text = 'merci beaucoup'; Expected = 'Avec plaisir.' }
        @{ Text = 'Salut Lambek, ça va ?'; Expected = 'Très bien, merci. Que voulez-vous faire ?' }
        @{ Text = 'parles tu anglais ?'; Expected = "Je comprends le français et l'anglais. Écris dans la langue que tu préfères." }
        @{ Text = 'who are you?'; Expected = "I'm Lambek. *" }
    ) {
        New-LambekPlan $Text | ConvertTo-LambekAnswer | Should -BeLike $Expected
    }

    It 'understands small talk with a typo' {
        New-LambekPlan 'saisttu parler fracais ?' | ConvertTo-LambekAnswer | Should -BeLike 'Je comprends le français*'
    }

    It 'asks only for what is really missing' {
        New-LambekPlan 'move to D:\Archive' | ConvertTo-LambekAnswer | Should -Be 'I need one more detail. Which files or folders?'
    }

    It 'moves from the first folder to the second' {
        (New-LambekPlan 'move the .log files in C:\Temp to D:\Archive' | ConvertTo-LambekAnswer).Split("`n")[0] | Should -Be "I'll move the .log files from C:\Temp to D:\Archive."
    }

    It 'lists its domains with an example when asked what it can do' {
        $answer = New-LambekPlan 'what can you do' | ConvertTo-LambekAnswer
        $answer | Should -BeLike 'I can help with files and code. Say what you want in your own words, for example: *'
    }

    It 'does not treat a request with more words as small talk' {
        New-LambekPlan 'hello how many folders are in my account' | ConvertTo-LambekAnswer | Should -BeLike "On this computer, I take care of*"
    }

    It 'asks in French' {
        New-LambekPlan 'cree un dossier dans D:\Archive' | ConvertTo-LambekAnswer | Should -Be 'Il me manque un détail. Quel nom doit-il porter ?'
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
