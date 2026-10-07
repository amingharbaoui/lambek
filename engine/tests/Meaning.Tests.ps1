BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Exact meaning of a request' {

    Context 'Exceptions' {
        It 'leaves out what follows "except" or "sauf": <Text>' -ForEach @(
            @{ Text = 'delete the files in C:\A except the .log files'; Name = 'ExceptExtension'; Value = '.log'; Filter = '*-NotIn*' }
            @{ Text = 'supprime les fichiers dans C:\A sauf les images'; Name = 'ExceptKind'; Value = 'image'; Filter = '*-NotIn*' }
            @{ Text = 'delete the files in C:\A except report.txt'; Name = 'ExceptName'; Value = 'report.txt'; Filter = '*Name -NE*' }
        ) {
            $step = (New-LambekPlan $Text).Steps[0]
            $step.Status | Should -Be 'Ready'
            $step.Parameters[$Name] | Should -Be $Value
            $step.Script | Should -BeLike $Filter
        }

        It 'still asks when nothing follows the exception' {
            (New-LambekPlan 'delete the files except in C:\A').Status | Should -Be 'NeedsInput'
        }
    }

    Context 'Several values' {
        It 'keeps every extension and every kind named' {
            (New-LambekPlan 'delete the .log and .tmp files in C:\Temp').Steps[0].Script | Should -BeLike "*-In @('.log', '.tmp')*"
            (New-LambekPlan 'copy the images and videos from C:\A to D:\B').Steps[0].Parameters.Kind | Should -Be @('image', 'video')
        }

        It 'says the values back as a list' {
            ConvertTo-LambekAnswer -Plan (New-LambekPlan 'delete the .log and .tmp files in C:\Temp') | Should -BeLike '*the .log and .tmp files*'
        }

        It 'reads a bare extension the machine knows: <Text>' -ForEach @(
            @{ Text = 'copy the pdf files from C:\A to D:\B'; Name = 'Extension' }
            @{ Text = 'copie les pdf de C:\A vers D:\B'; Name = 'Extension' }
            @{ Text = 'supprime les fichiers pdf dans C:\A'; Name = 'Extension' }
            @{ Text = 'supprime les fichiers dans C:\A sans toucher aux pdf'; Name = 'ExceptExtension' }
            @{ Text = 'list the newest file in C:\A except the pdf'; Name = 'ExceptExtension' }
        ) {
            $step = (New-LambekPlan $Text).Steps[0]
            $step.Status | Should -Be 'Ready'
            $step.Parameters[$Name] | Should -Be '.pdf'
        }

        It 'never reads a word of the languages as an extension' {
            $request = ConvertTo-LambekRequest 'list the old files in C:\A'
            @($request.Entities | Where-Object Type -EQ 'extension').Count | Should -Be 0
        }

        It 'keeps an exception and a kind together: <Text>' -ForEach @(
            @{ Text = 'supprime tout dans C:\A sauf les images et les pdf' }
        ) {
            $step = (New-LambekPlan $Text).Steps[0]
            $step.Status | Should -Be 'Ready'
            $step.Parameters.ExceptKind | Should -Be 'image'
            $step.Parameters.ExceptExtension | Should -Be '.pdf'
        }
    }

    Context 'Order and count' {
        It 'sorts and keeps the first ones: <Text>' -ForEach @(
            @{ Text = 'list the 5 largest files in C:\Data'; Order = 'largest'; Count = 5; Sort = '*Sort-Object Length -Descending*' }
            @{ Text = 'supprime le fichier le plus ancien dans C:\Temp'; Order = 'oldest'; Count = 1; Sort = '*Sort-Object LastWriteTime*' }
            @{ Text = 'déplace les 3 plus gros fichiers de C:\A vers D:\B'; Order = 'largest'; Count = 3; Sort = '*Sort-Object Length -Descending*' }
            @{ Text = 'list the newest file in C:\Logs'; Order = 'newest'; Count = 1; Sort = '*Sort-Object LastWriteTime -Descending*' }
        ) {
            $step = (New-LambekPlan $Text).Steps[0]
            $step.Status | Should -Be 'Ready'
            $step.Parameters.Order | Should -Be $Order
            $step.Parameters.Count | Should -Be $Count
            $step.Script | Should -BeLike $Sort
            $step.Script | Should -BeLike "*Select-Object -First $Count*"
            $step.Check.IsValid | Should -BeTrue
        }

        It 'asks how many when a change names several without a number' {
            $plan = New-LambekPlan 'delete the largest files in C:\Temp'
            $plan.Status | Should -Be 'NeedsInput'
            $plan.Questions | Should -Contain 'Step 1: How many?'
        }

        It 'asks which ones for a number alone' {
            (New-LambekPlan 'delete 5 files in C:\Temp').Questions[0] | Should -BeLike '*newest, oldest, largest or smallest*'
        }

        It 'speaks of one file in the singular' {
            ConvertTo-LambekAnswer -Plan (New-LambekPlan 'supprime le fichier le plus ancien dans C:\Temp') | Should -BeLike '*supprimer le fichier le plus ancien dans C:\Temp*'
            ConvertTo-LambekAnswer -Plan (New-LambekPlan 'delete the newest file in C:\Temp') | Should -BeLike '*delete the newest file in C:\Temp*'
        }
    }

    Context 'Every word counts' {
        It 'does not change files past a word it cannot use: <Text>' -ForEach @(
            @{ Text = 'delete the old files in C:\Temp'; Question = 'Step 1: By "old", do you mean older than 30 days? Say yes to do it, or give another threshold.' }
            @{ Text = 'delete the obsolete files in C:\Temp'; Question = 'Step 1: What does "obsolete" mean here?' }
            @{ Text = 'supprime les enregistrement dans C:\Temp'; Question = 'Step 1: Que veut dire « enregistrement » ici ?' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Status | Should -Be 'NeedsInput'
            $plan.Questions | Should -Contain $Question
        }

        It 'still reads files past such a word, since reading changes nothing' {
            (New-LambekPlan 'list the old files in C:\Temp').Status | Should -Be 'Ready'
        }

        It 'takes the value it asked for from the reply' {
            $plan = New-LambekPlan 'delete the old files in C:\Temp'
            $reply = Resolve-LambekFollowUp -Plan $plan -Text '30 days'
            $reply.Plan.Status | Should -Be 'Ready'
            $reply.Plan.Steps[0].Parameters.OlderThan | Should -Be ([timespan]::FromDays(30))
        }
    }

    Context 'Words read from what they look like' {
        It 'reads a word of manner as changing no file: <Text>' -ForEach @(
            @{ Text = 'supprime rapidement les fichiers .log dans C:\Temp' }
            @{ Text = 'delete the .log files in C:\Temp quickly' }
        ) {
            $step = (New-LambekPlan $Text).Steps[0]
            $step.Status | Should -Be 'Ready'
            $step.Parameters.Extension | Should -Be '.log'
        }

        It 'reads a word an extension shortens, and says so' {
            $plan = New-LambekPlan 'supprime les fichiers zippes dans C:\Temp'
            $plan.Steps[0].Parameters.Extension | Should -Be '.zip'
            ConvertTo-LambekAnswer -Plan $plan | Should -BeLike '*« zippes » : compris comme .zip.*'
        }

        It 'knows the kinds of the packs: <Text>' -ForEach @(
            @{ Text = 'supprime les fichiers temporaires dans C:\Temp'; Kind = 'temporary' }
            @{ Text = 'delete the backup files in C:\Temp'; Kind = 'backup' }
        ) {
            (New-LambekPlan $Text).Steps[0].Parameters.Kind | Should -Be $Kind
        }

        It 'still asks when nothing fits: <Text>' -ForEach @(
            @{ Text = 'supprime les screenshots dans C:\Temp' }
        ) {
            (New-LambekPlan $Text).Status | Should -Be 'NeedsInput'
        }
    }

    Context 'Questions' {
        It 'reads a question about files as a listing: <Text>' -ForEach @(
            @{ Text = 'je veux savoir quels fichiers prennent le plus de place dans C:\Data'; Order = 'largest' }
            @{ Text = 'which files take up the most space in C:\Data?'; Order = 'largest' }
            @{ Text = 'quels sont les fichiers les plus récents dans C:\Data ?'; Order = 'newest' }
            @{ Text = 'what files are in C:\Data'; Order = $null }
        ) {
            $step = (New-LambekPlan $Text).Steps[0]
            $step.Status | Should -Be 'Ready'
            $step.Action | Should -Be 'files.list'
            $step.Parameters.Path | Should -Be 'C:\Data'
            $step.Parameters['Order'] | Should -Be $Order
        }

        It 'lists them all, in order, when a reading gives no count' {
            $step = (New-LambekPlan 'liste les plus gros fichiers dans C:\Data').Steps[0]
            $step.Status | Should -Be 'Ready'
            $step.Script | Should -BeLike '*Sort-Object Length -Descending*'
            $step.Script | Should -Not -BeLike '*Select-Object -First*'
        }

        It 'is not a request without files to place or sort: <Text>' -ForEach @(
            @{ Text = 'what time is it' }
            @{ Text = 'quelle heure est-il' }
        ) {
            $plan = New-LambekPlan $Text
            @($plan.Steps | Where-Object Action).Count | Should -Be 0
        }
    }

    Context 'Pronouns in one request' {
        It 'gives the files of the step before to a pronoun: <Text>' -ForEach @(
            @{ Text = 'copie les images de C:\A vers D:\B puis supprime-les'; Path = 'C:\A'; Kind = 'image' }
            @{ Text = 'copy the .log files from C:\A to D:\B then delete them'; Path = 'C:\A'; Extension = '.log' }
        ) {
            $plan = New-LambekPlan $Text
            $plan.Status | Should -Be 'Ready'
            $plan.Steps[1].Action | Should -Be 'files.delete'
            $plan.Steps[1].Parameters.Path | Should -Be $Path
            if ($Kind) { $plan.Steps[1].Parameters.Kind | Should -Be $Kind }
            if ($Extension) { $plan.Steps[1].Parameters.Extension | Should -Be $Extension }
            $plan.Steps[1].Parameters.Contains('Destination') | Should -BeFalse
        }

        It 'orders the delete after the copy' {
            $plan = New-LambekPlan 'copie les images de C:\A vers D:\B puis supprime-les'
            $plan.Order | Should -Be @(1, 2)
        }

        It 'does not guess a place for a noun that names new files' {
            (New-LambekPlan 'copie les images de C:\A vers D:\B puis supprime les fichiers').Status | Should -Be 'NeedsInput'
        }
    }
}
