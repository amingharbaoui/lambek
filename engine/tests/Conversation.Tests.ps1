BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null

    # Each message follows the plan the previous one left
    function Invoke-TestChat {
        param([string[]] $Turns)
        $plan = New-LambekPlan $Turns[0]
        $reply = $null
        foreach ($turn in @($Turns | Select-Object -Skip 1)) {
            $reply = Resolve-LambekFollowUp -Plan $plan -Text $turn
            if ($reply.Plan -and @($reply.Plan.Steps | Where-Object Action).Count -gt 0) { $plan = $reply.Plan }
        }
        [pscustomobject]@{ Plan = $plan; Reply = $reply; Step = @($plan.Steps | Where-Object Action)[0] }
    }
}

Describe 'Conversation' {

    BeforeAll {
        $root = Join-Path $TestDrive 'chat'
        $other = Join-Path $TestDrive 'other'
        New-Item -Path $root, $other -ItemType Directory -Force | Out-Null
        1..5 | ForEach-Object { "x$_" | Set-Content -LiteralPath (Join-Path $root "f$_.log") }
    }

    It 'reads numbers written as words: <Text>' -ForEach @(
        @{ Text = 'supprime les fichiers de plus de deux jours dans "{0}"'; Name = 'OlderThan'; Value = [timespan]::FromDays(2) }
        @{ Text = 'libère trois Go dans "{0}"'; Name = 'FreeSize'; Value = 3GB }
    ) {
        $step = (New-LambekPlan ($Text -f $root)).Steps[0]
        $step.Parameters[$Name] | Should -Be $Value
    }

    It 'changes only what a fragment says: <Turns>' -ForEach @(
        @{ Turns = @('supprime les fichiers .tmp dans "{0}"', 'idem pour les .log'); Name = 'Extension'; Value = '.log' }
        @{ Turns = @('copie les images de "{0}" vers "{1}"', 'et les vidéos ?'); Name = 'Kind'; Value = 'video' }
        @{ Turns = @('liste les fichiers dans "{0}"', 'trie-les par taille'); Name = 'Order'; Value = 'largest' }
        @{ Turns = @('liste les fichiers dans "{0}"', 'trie-les par taille', 'seulement les trois premiers'); Name = 'Count'; Value = 3 }
        @{ Turns = @('liste les fichiers dans "{0}"', 'trie-les par taille', 'du plus petit au plus gros'); Name = 'Order'; Value = 'smallest' }
    ) {
        $chat = Invoke-TestChat -Turns @($Turns | ForEach-Object { $_ -f $root, $other })
        $chat.Plan.Status | Should -Be 'Ready'
        $chat.Step.Parameters[$Name] | Should -Be $Value
    }

    It 'adds to what the plan holds with "aussi": <Turns>' -ForEach @(
        @{ Turns = @('supprime les fichiers .tmp dans "{0}"', 'idem pour les .log', 'et les .bak aussi'); Name = 'Extension'; Value = @('.log', '.bak') }
        @{ Turns = @('copie les images de "{0}" vers "{1}"', 'et les vidéos ?', 'et la musique aussi'); Name = 'Kind'; Value = @('video', 'audio') }
    ) {
        $chat = Invoke-TestChat -Turns @($Turns | ForEach-Object { $_ -f $root, $other })
        @($chat.Step.Parameters[$Name]) | Should -Be $Value
    }

    It 'counts without changing anything: <Turns>' -ForEach @(
        @{ Turns = @('liste les fichiers .log dans "{0}"', 'combien il y en a ?'); Answer = 'Il y en a 5.' }
        @{ Turns = @('list the .log files in "{0}"', 'how many are there?'); Answer = 'There are 5.' }
    ) {
        $chat = Invoke-TestChat -Turns @($Turns | ForEach-Object { $_ -f $root })
        $chat.Reply.Kind | Should -Be 'explain'
        $chat.Reply.Answer | Should -Be $Answer
        @(Get-ChildItem -LiteralPath $root -Filter '*.log').Count | Should -Be 5
    }

    It 'moves to a new action on the same files, then narrows it' {
        $chat = Invoke-TestChat -Turns @("list the .log files in ""$root""", 'delete them', 'only the two oldest')
        $chat.Step.Action | Should -Be 'files.delete'
        $chat.Step.Parameters['Path'] | Should -Be $root
        $chat.Step.Parameters['Order'] | Should -Be 'oldest'
        $chat.Step.Parameters['Count'] | Should -Be 2
    }

    It 'finds the referent a pronoun agrees with: <Pronoun>' -ForEach @(
        @{ Pronoun = 'supprime-les'; Name = 'Extension'; Value = '.log' }
        @{ Pronoun = 'supprime-le'; Name = 'Name'; Value = 'rapport.txt' }
    ) {
        $plan = New-LambekPlan "liste les fichiers .log dans ""$root"""
        $plan = (Resolve-LambekFollowUp -Plan $plan -Text "liste le fichier rapport.txt dans ""$other""").Plan
        $reply = Resolve-LambekFollowUp -Plan $plan -Text $Pronoun
        $reply.Plan.Steps[0].Action | Should -Be 'files.delete'
        $reply.Plan.Steps[0].Parameters[$Name] | Should -Be $Value
    }
}
