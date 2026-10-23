BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'The words said around a request' {

    It 'reads the request without them: <Text>' -ForEach @(
        @{ Text = 'euh efface les fichiers .tmp dans C:\Data'; Read = 'efface les fichiers .tmp dans C:\Data' }
        @{ Text = 'stp renomme report.txt en "notes.md" merci'; Read = 'renomme report.txt en "notes.md"' }
        @{ Text = "s'il te plaît, affiche les fichiers .tmp dans C:\Data merci."; Read = 'affiche les fichiers .tmp dans C:\Data.' }
        @{ Text = 'bonjour, est-ce que tu peux lister les fichiers dans C:\Temp ?'; Read = 'lister les fichiers dans C:\Temp ?' }
        @{ Text = 'hey, delete the .bak files in E:\Backup thanks'; Read = 'delete the .bak files in E:\Backup' }
        @{ Text = 'um could you copy the .pdf files in C:\A to D:\B please'; Read = 'copy the .pdf files in C:\A to D:\B' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) ConvertTo-LambekBareRequest -Text $Text } | Should -BeExactly $Read
    }

    It 'leaves a sentence that is only courtesy, or a question asked politely, as it was: <Text>' -ForEach @(
        @{ Text = 'salut' }
        @{ Text = 'merci beaucoup' }
        @{ Text = 'well done' }
        @{ Text = 'peux-tu me dire la capitale du Japon ?' }
        @{ Text = 'could you tell me the capital of Japan?' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) ConvertTo-LambekBareRequest -Text $Text } | Should -BeExactly $Text
    }

    It 'plans the same with a hesitation or thanks around the request as without them' {
        $plain = New-LambekPlan 'efface les fichiers .tmp dans C:\Data'
        $polite = New-LambekPlan 'euh, efface les fichiers .tmp dans C:\Data stp'
        $polite.Status | Should -Be $plain.Status
        @($polite.Steps | ForEach-Object Action) | Should -Be @($plain.Steps | ForEach-Object Action)
    }
}
