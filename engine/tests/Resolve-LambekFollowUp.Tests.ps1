BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Resolve-LambekFollowUp' {

    BeforeAll {
        $plan = New-LambekPlan 'delete the .log files older than 30 days in C:\Temp'
    }

    Context 'Editing nodes from the chat' {
        It 'changes <Name> with "<Text>"' -ForEach @(
            @{ Text = 'use .tmp instead'; Name = 'Extension'; Expected = '.tmp' }
            @{ Text = 'larger than 1 GB'; Name = 'MinSize'; Expected = 1GB }
            @{ Text = 'in D:\Logs'; Name = 'Path'; Expected = 'D:\Logs' }
            @{ Text = 'older than 7 days'; Name = 'OlderThan'; Expected = [timespan]::FromDays(7) }
        ) {
            $result = Resolve-LambekFollowUp -Plan $plan -Text $Text
            $result.Kind | Should -Be 'edit'
            $result.Plan.Steps[0].Parameters[$Name] | Should -Be $Expected
            $result.Plan.Status | Should -Be 'Ready'
        }

        It 'answers the question of an incomplete plan' {
            $incomplete = New-LambekPlan 'delete the .log files'
            $result = Resolve-LambekFollowUp -Plan $incomplete -Text 'C:\Temp'
            $result.Kind | Should -Be 'edit'
            $result.Plan.Status | Should -Be 'Ready'
            $result.Answer | Should -BeLike "Updated. I'll delete the .log files in C:\Temp.*"
        }

        It 'takes a short reply as the missing name: <Text>' -ForEach @(
            @{ Text = 'exemple'; Expected = 'exemple' }
            @{ Text = 'notes.txt'; Expected = 'notes.txt' }
            @{ Text = 'rapport final'; Expected = 'rapport final' }
        ) {
            $create = New-LambekPlan 'cree un fichier dans C:\Temp'
            $result = Resolve-LambekFollowUp -Plan $create -Text $Text
            $result.Kind | Should -Be 'edit'
            $result.Plan.Steps[0].Parameters.Name | Should -Be $Expected
            $result.Plan.Status | Should -Be 'Ready'
        }

        It 'does not take a question or small talk as a name: <Text>' -ForEach @(
            @{ Text = "c'est quoi ça ?" }
            @{ Text = 'merci' }
            @{ Text = 'thank you' }
        ) {
            $create = New-LambekPlan 'cree un fichier dans C:\Temp'
            $result = Resolve-LambekFollowUp -Plan $create -Text $Text
            $result.Kind | Should -Be 'new'
        }

        It 'reads an action word as a new request, not as a value: <Text>' -ForEach @(
            @{ Text = 'delete' }
            @{ Text = 'supprime' }
            @{ Text = 'list' }
        ) {
            $move = New-LambekPlan 'move the files'
            $result = Resolve-LambekFollowUp -Plan $move -Text $Text
            $result.Kind | Should -Be 'new'
        }

        It 'answers small talk in the language of the plan' {
            $create = New-LambekPlan 'cree un fichier dans C:\Temp'
            (Resolve-LambekFollowUp -Plan $create -Text 'ok').Answer | Should -Be 'Très bien. Dites-moi quand vous avez besoin de quelque chose.'
        }

        It 'does not run a plan that still needs details' {
            $create = New-LambekPlan 'cree un fichier dans C:\Temp'
            (Resolve-LambekFollowUp -Plan $create -Text 'ok').Kind | Should -Be 'new'
        }

        It 'takes a reply as the missing destination: <Text>' -ForEach @(
            @{ Text = 'D:\Archive'; Expected = 'D:\Archive' }
            @{ Text = 'Downloads'; Expected = 'Downloads' }
            @{ Text = 'téléchargements'; Expected = 'Downloads' }
        ) {
            $move = New-LambekPlan 'move the .log files in C:\Temp'
            $result = Resolve-LambekFollowUp -Plan $move -Text $Text
            $result.Kind | Should -Be 'edit'
            $result.Plan.Steps[0].Parameters.Source | Should -Be 'C:\Temp'
            $result.Plan.Steps[0].Parameters.Destination | Should -BeLike "*$Expected"
        }

        It 'gives the destination of a move' {
            $move = New-LambekPlan 'move the files in C:\Temp'
            $result = Resolve-LambekFollowUp -Plan $move -Text 'to D:\Archive'
            $result.Plan.Steps[0].Parameters.Destination | Should -Be 'D:\Archive'
        }

        It 'targets a step by its number' {
            $two = New-LambekPlan 'list the files in C:\A then delete the .tmp files in D:\B'
            $result = Resolve-LambekFollowUp -Plan $two -Text 'step 1 in C:\Other'
            $result.Plan.Steps[0].Parameters.Path | Should -Be 'C:\Other'
            $result.Plan.Steps[1].Parameters.Path | Should -Be 'D:\B'
        }

        It 'targets the node selected in the app' {
            $two = New-LambekPlan 'list the files in C:\A then delete the .tmp files in D:\B'
            $result = Resolve-LambekFollowUp -Plan $two -Text 'in C:\Other' -Step 1
            $result.Plan.Steps[0].Parameters.Path | Should -Be 'C:\Other'
            $result.Plan.Steps[1].Parameters.Path | Should -Be 'D:\B'
        }
    }

    Context 'Other messages' {
        It 'explains the plan' {
            $result = Resolve-LambekFollowUp -Plan $plan -Text 'explain'
            $result.Kind | Should -Be 'explain'
            $result.Answer | Should -BeLike '*reduce to s*'
            $result.Answer | Should -BeLike '*AST firewall*'
        }

        It 'explains in French' {
            $french = New-LambekPlan 'supprime les fichiers .log dans C:\Temp'
            (Resolve-LambekFollowUp -Plan $french -Text 'pourquoi').Answer | Should -BeLike '*pare-feu AST*'
        }

        It 'understands "<Text>" as run' -ForEach @(
            @{ Text = 'run it' }
            @{ Text = 'go' }
            @{ Text = 'yes please' }
        ) {
            (Resolve-LambekFollowUp -Plan $plan -Text $Text).Kind | Should -Be 'run'
        }

        It 'starts a new plan for a new command' {
            $result = Resolve-LambekFollowUp -Plan $plan -Text 'list the files in C:\Data'
            $result.Kind | Should -Be 'new'
            $result.Plan.Steps[0].Action | Should -Be 'files.list'
        }

        It 'never changes the original plan' {
            Resolve-LambekFollowUp -Plan $plan -Text 'use .tmp instead' | Out-Null
            $plan.Steps[0].Parameters.Extension | Should -Be '.log'
        }
    }
}

Describe 'Plan trace' {
    It 'lists every task with its time' {
        $plan = New-LambekPlan 'delete the .log files in C:\Temp'
        $plan.Trace.Stage | Should -Be @('Split', 'Read', 'Type', 'Match', 'Check', 'Order')
        $plan.Trace | ForEach-Object { $_.Milliseconds | Should -BeGreaterOrEqual 0 }
    }
}
