BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Resolve-Text {
        param([string] $Text)
        ConvertTo-LambekRequest $Text | Resolve-LambekIntent
    }
}

Describe 'Dialogue act' {

    It 'keeps an order an order: <Text>' -ForEach @(
        @{ Text = 'delete the .log files in C:\Temp' }
        @{ Text = 'can you list the files in C:\Data' }
        @{ Text = 'I want to delete the .tmp files in C:\Temp' }
        @{ Text = 'we need to move the files in C:\A to D:\B' }
        @{ Text = 'in my folder C:\Work delete the .bak files' }
        @{ Text = 'which files in C:\Data are older than 30 days' }
        @{ Text = 'delete them' }
        @{ Text = 'create a folder' }
        @{ Text = 'je veux supprimer les fichiers .log dans C:\Temp' }
        @{ Text = 'j''aimerais que tu supprimes les fichiers .tmp dans C:\Temp' }
        @{ Text = 'il faut déplacer les fichiers de C:\A vers D:\B' }
        @{ Text = 'on doit supprimer les fichiers de C:\Temp' }
        @{ Text = 'supprime-les' }
    ) {
        $card = Resolve-Text $Text
        $card.Act | Should -Be 'Order'
        $card.Action | Should -Not -BeNullOrEmpty
    }

    It 'reads what the user tells as a report, and chooses no action: <Text>' -ForEach @(
        @{ Text = 'yesterday I deleted the files in C:\Temp' }
        @{ Text = 'my colleague wants to delete the files in C:\Temp' }
        @{ Text = 'my boss moved to Paris last year' }
        @{ Text = 'she deleted her account last week' }
        @{ Text = 'hier j''ai supprimé les fichiers dans C:\Temp' }
        @{ Text = 'ils ont déplacé la réunion à jeudi' }
    ) {
        $card = Resolve-Text $Text
        $card.Act | Should -Be 'Report'
        $card.Status | Should -Be 'Unknown'
        $card.Action | Should -BeNullOrEmpty
    }

    It 'reads a question about how things are as a question, and chooses no action: <Text>' -ForEach @(
        @{ Text = 'how do I delete the .log files in C:\Temp' }
        @{ Text = 'is it safe to delete the files in C:\Temp' }
        @{ Text = 'what would happen if I deleted the files in C:\Temp' }
        @{ Text = 'what is a .log file' }
        @{ Text = 'pourquoi supprimer la peine de mort' }
    ) {
        $card = Resolve-Text $Text
        $card.Act | Should -Be 'Question'
        $card.Status | Should -Be 'Unknown'
        $card.Action | Should -BeNullOrEmpty
    }

    It 'reads a sentence about something else as such, and chooses no action: <Text>' -ForEach @(
        @{ Text = 'the delete key on my keyboard is broken' }
        @{ Text = 'list three reasons to learn French' }
        @{ Text = 'find me a good restaurant in Brussels' }
        @{ Text = 'la liste des courses est sur la table' }
        @{ Text = 'trouve une idée de cadeau pour ma mère' }
    ) {
        $card = Resolve-Text $Text
        $card.Act | Should -Be 'Other'
        $card.Status | Should -Be 'Unknown'
        $card.Action | Should -BeNullOrEmpty
    }

    It 'says how it read the sentence, and proposes no request in its place' {
        $plan = New-LambekPlan 'yesterday I deleted the files in C:\Temp'
        $plan.Steps[0].Act | Should -Be 'Report'
        $plan.PSObject.Properties['Suggestion'] | Should -BeNullOrEmpty
        $plan | ConvertTo-LambekAnswer | Should -BeLike 'I read that as something you are telling me*'
        New-LambekPlan 'how do I delete the .log files in C:\Temp' | ConvertTo-LambekAnswer | Should -BeLike 'That is a question*'
        New-LambekPlan 'find me a good restaurant in Brussels' | ConvertTo-LambekAnswer | Should -BeLike '*something other than what I take care of*'
        New-LambekPlan 'hier j''ai supprimé les fichiers dans C:\Temp' | ConvertTo-LambekAnswer | Should -BeLike 'Je lis cela comme une information*'
    }

    It 'still answers small talk, and still asks what to do when nothing is recognised' {
        New-LambekPlan 'hello' | ConvertTo-LambekAnswer | Should -BeLike 'Hello*'
        (Resolve-Text 'what time is it').Act | Should -Be 'Order'
    }

    It 'reads every sentence as an order in a language that has no words for the rest yet' {
        (Resolve-Text 'lösche die .log dateien in C:\Temp').Act | Should -Be 'Order'
    }
}
