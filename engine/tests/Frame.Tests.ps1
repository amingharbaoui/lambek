BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'An order for another time, for someone else, or under a condition' {

    It 'does not act, even to read, and says what it read: <Text>' -ForEach @(
        @{ Text = 'affiche les fichiers dans C:\Temp seulement si la sauvegarde est vérifiée'; Frame = 'si la sauvegarde est vérifiée' }
        @{ Text = 'hier, Paul a voulu afficher les fichiers dans C:\Temp'; Frame = 'hier' }
        @{ Text = 'Paul veut afficher les fichiers dans C:\Temp'; Frame = 'Paul veut' }
    ) {
        $plan = New-LambekPlan -Text $Text
        $plan.Status | Should -Not -Be 'Ready'
        @($plan.Steps.Questions) -join ' ' | Should -BeLike "*$Frame*"
    }

    It 'does not act in English either: <Text>' -ForEach @(
        @{ Text = 'list the files in C:\Temp only if the backup is verified' }
        @{ Text = 'my colleague wants to list the files in C:\Temp' }
        @{ Text = 'yesterday Paul wanted to show the files in C:\Temp' }
    ) {
        (New-LambekPlan -Text $Text).Status | Should -Not -Be 'Ready'
    }

    It 'still acts on a request for now, said for me: <Text>' -ForEach @(
        @{ Text = 'affiche les fichiers dans C:\Temp' }
        @{ Text = "je veux afficher les fichiers dans C:\Temp" }
        @{ Text = "affiche les fichiers dans C:\Temp s'il te plaît" }
        @{ Text = "aujourd'hui, affiche les fichiers dans C:\Temp" }
        @{ Text = 'can you list the files in C:\Temp' }
    ) {
        (New-LambekPlan -Text $Text).Status | Should -Be 'Ready'
    }
}
