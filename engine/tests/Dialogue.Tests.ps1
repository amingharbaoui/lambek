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
        $plan = New-LambekPlan 'my boss moved to Paris last year'
        $plan.Steps[0].Act | Should -Be 'Report'
        $plan.PSObject.Properties['Suggestion'] | Should -BeNullOrEmpty
        $plan | ConvertTo-LambekAnswer | Should -BeLike 'I read that as something you are telling me*'
        New-LambekPlan 'how do I delete the .log files in C:\Temp' | ConvertTo-LambekAnswer | Should -BeLike 'That is a question*'
        New-LambekPlan 'find me a good restaurant in Brussels' | ConvertTo-LambekAnswer | Should -BeLike '*something other than what I take care of*'
        New-LambekPlan 'ils ont déplacé la réunion à jeudi' | ConvertTo-LambekAnswer | Should -BeLike 'Je lis cela comme une information*'
    }

    It 'reads the meaning of what is told: <Text>' -ForEach @(
        @{ Text = 'yesterday I deleted the files in C:\Temp'; Form = 'told(delete(all(object and path(C:\Temp))), agent(speaker), time("yesterday"))' }
        @{ Text = 'last week we moved the .pdf files from C:\A to D:\B'; Form = 'told(move(all(object and extension(.pdf) and source(C:\A)), destination(D:\B)), agent(speaker), time("last week"))' }
        @{ Text = 'she copied report.txt to D:\Backup this morning'; Form = 'told(copy(all(object and name(report.txt)), destination(D:\Backup)), agent("she"), time("this morning"))' }
        @{ Text = 'I renamed report.txt to summary.txt'; Form = 'told(rename(all(object and name(report.txt)), newName(summary.txt)), agent(speaker))' }
        @{ Text = 'hier j''ai supprimé les fichiers dans C:\Temp'; Form = 'told(delete(all(object and path(C:\Temp))), agent(speaker), time("hier"))' }
        @{ Text = 'mon collègue veut supprimer les fichiers .log de C:\Temp'; Form = 'told(wish(delete(all(object and extension(.log) and path(C:\Temp))), agent("mon collègue")))' }
    ) {
        $card = Resolve-Text $Text
        $card.Statement.Form | Should -Be $Form
        # Understood, never carried out
        $card.Status | Should -Be 'Unknown'
        $card.Action | Should -BeNullOrEmpty
    }

    It 'gives the same objects to a sentence told and to the same sentence asked' {
        $told = (Resolve-Text 'yesterday I deleted the files older than 30 days in C:\Logs except the .txt').Statement
        $asked = Resolve-Text 'delete the files older than 30 days in C:\Logs except the .txt'
        $told.Action | Should -Be $asked.Action
        ($told.Parameters | ConvertTo-Json -Compress) | Should -Be ($asked.Parameters | ConvertTo-Json -Compress)
    }

    It 'gives no meaning to a sentence only half read: <Text>' -ForEach @(
        @{ Text = 'my boss moved to Paris last year' }
        @{ Text = 'I deleted the files' }
        @{ Text = 'ils ont déplacé la réunion à jeudi' }
        @{ Text = 'delete the files in C:\Temp' }
    ) {
        (Resolve-Text $Text).Statement | Should -BeNullOrEmpty
    }

    It 'says back who, what and when' {
        New-LambekPlan 'yesterday I deleted the files in C:\Temp' | ConvertTo-LambekAnswer | Should -Be 'I understand. Who: you. What: delete the files in C:\Temp. When: yesterday. You are telling me, so I am not doing it. I am keeping it.'
        New-LambekPlan 'mon collègue veut supprimer les fichiers .log de C:\Temp' | ConvertTo-LambekAnswer | Should -BeLike 'Je comprends. Qui : mon collègue. Souhaite : supprimer les fichiers .log dans C:\Temp.*'
    }

    Context 'What was told in the conversation' {
        BeforeEach {
            # Every test starts a conversation of its own, with an empty journal, on the same day
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
        }

        It 'says that nothing was told yet' {
            New-LambekPlan 'what did I delete yesterday' | ConvertTo-LambekAnswer | Should -Be 'You have not told me anything yet.'
        }

        It 'answers "<Ask>" from what was told' -ForEach @(
            @{ Ask = 'what did I delete yesterday'; Line = '- Who: you. What: delete the files in C:\Temp. When: yesterday.' }
            @{ Ask = 'what did I delete'; Line = '- Who: you. What: delete the files in C:\Temp. When: yesterday.' }
            @{ Ask = 'did I delete the files in C:\Temp'; Line = '- Who: you. What: delete the files in C:\Temp. When: yesterday.' }
            @{ Ask = 'what did I move last week'; Line = '- Who: you. What: move the .pdf files from C:\A to D:\B. When: last week.' }
            @{ Ask = 'what did my colleague copy'; Line = '- Who: my colleague. What: copy the files named report.txt to D:\Backup. When: this morning.' }
        ) {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            New-LambekPlan 'last week we moved the .pdf files from C:\A to D:\B' | Out-Null
            New-LambekPlan 'my colleague copied report.txt to D:\Backup this morning' | Out-Null
            New-LambekPlan $Ask | ConvertTo-LambekAnswer | Should -Be ("From what you told me in this conversation:", $Line -join "`n")
        }

        It 'never says more than was told: <Ask>' -ForEach @(
            @{ Ask = 'did I delete the files in C:\Windows' }
            @{ Ask = 'what did I move yesterday' }
            @{ Ask = 'what did I copy' }
        ) {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            New-LambekPlan 'last week we moved the .pdf files from C:\A to D:\B' | Out-Null
            New-LambekPlan 'my colleague copied report.txt to D:\Backup this morning' | Out-Null
            New-LambekPlan $Ask | ConvertTo-LambekAnswer | Should -Be 'You have not told me that.'
        }

        It 'says everything that was told, once each, in the order it was told' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            New-LambekPlan 'last week we moved the .pdf files from C:\A to D:\B' | Out-Null
            $lines = @((New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer) -split "`n")
            $lines.Count | Should -Be 3
            $lines[1] | Should -BeLike '*delete the files in C:\Temp*'
            $lines[2] | Should -BeLike '*move the .pdf files*'
        }

        It 'answers in French from what was told in French' {
            New-LambekPlan 'hier j''ai supprimé les fichiers .log dans C:\Temp' | Out-Null
            New-LambekPlan 'qu''est-ce que j''ai supprimé hier' | ConvertTo-LambekAnswer | Should -Be ("D'après ce qui m'a été dit dans cette conversation :", '- Qui : vous. Quoi : supprimer les fichiers .log dans C:\Temp. Quand : hier.' -join "`n")
            New-LambekPlan 'quels fichiers j''ai déplacés' | ConvertTo-LambekAnswer | Should -Be "Cela ne m'a pas été dit."
        }

        It 'keeps nothing of a sentence read without the memory' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' -NoRecall | Out-Null
            New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer | Should -Be 'You have not told me anything yet.'
        }

        It 'keeps the plan in progress when something is told or asked about what was told' {
            $plan = New-LambekPlan 'delete the .tmp files in C:\Temp'
            $turn = Resolve-LambekFollowUp -Plan $plan -Text 'this morning I renamed report.txt to summary.txt'
            $turn.Kind | Should -Be 'explain'
            [object]::ReferenceEquals($turn.Plan, $plan) | Should -BeTrue
            (Resolve-LambekFollowUp -Plan $plan -Text 'what did I rename').Answer | Should -BeLike '*rename report.txt to summary.txt*'
        }

        It 'still reads a question about files as a listing, and an order as an order' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            (Resolve-Text 'which files in C:\Data are older than 30 days').Action | Should -Be 'files.list'
            (Resolve-Text 'delete the files in C:\Temp').Status | Should -Be 'Ready'
            (Resolve-Text 'did I delete the files in C:\Temp').Statement | Should -BeNullOrEmpty
        }
    }

    Context 'The journal of what was told' {
        BeforeAll {
            function Start-Day { param([string] $Day) & (Get-Module Lambek) { param($Day) $script:Now = [datetime] $Day } $Day }
            # Another conversation: nothing is kept in memory, the journal is read again from the disk
            function Start-Conversation { & (Get-Module Lambek) { $script:Told = $null; $script:ToldJournal = $null } }
            function Get-JournalPath { & (Get-Module Lambek) { $script:ToldPath } }
        }
        BeforeEach {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false }
            Start-Day '2026-10-06 10:00'
        }
        AfterAll {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = $null }
        }

        It 'answers in another conversation, with the day it was told and the day it was about' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            Start-Conversation
            Start-Day '2026-10-09 09:00'
            New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer | Should -Be ('From what you told me before:', '- Told on 2026-10-06. Who: you. What: delete the files in C:\Temp. When: 2026-10-05.' -join "`n")
        }

        It 'does not take the yesterday of another day for the yesterday of today' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            Start-Conversation
            Start-Day '2026-10-09 09:00'
            New-LambekPlan 'what did I delete yesterday' | ConvertTo-LambekAnswer | Should -Be 'You have not told me that.'
            Start-Day '2026-10-06 18:00'
            New-LambekPlan 'what did I delete yesterday' | ConvertTo-LambekAnswer | Should -BeLike '*delete the files in C:\Temp*'
        }

        It 'says what was told in this conversation first, then what was told before, once each' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            Start-Conversation
            Start-Day '2026-10-09 09:00'
            New-LambekPlan 'yesterday I deleted the .log files in C:\Logs' | Out-Null
            New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me in this conversation:'
                    '- Who: you. What: delete the .log files in C:\Logs. When: yesterday.'
                    'From what you told me before:'
                    '- Told on 2026-10-06. Who: you. What: delete the files in C:\Temp. When: 2026-10-05.'
                ) -join "`n")
        }

        It 'keeps the words of the day: accents, and the language it was told in' {
            New-LambekPlan 'mon collègue a copié l''été.txt vers D:\Backup ce matin' | Out-Null
            Start-Conversation
            New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer | Should -Be ('From what you told me before:', '- Told on 2026-10-06. Who: mon collègue. What: copier les fichiers nommés été.txt vers D:\Backup. When: 2026-10-06.' -join "`n")
        }

        It 'leaves out a line changed by hand and those after it, says so, and still keeps what is told next' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            New-LambekPlan 'yesterday I moved the .pdf files from C:\A to D:\B' | Out-Null
            New-LambekPlan 'yesterday I copied report.txt to D:\Backup' | Out-Null
            $path = Get-JournalPath
            $lines = @(Get-Content -LiteralPath $path -Encoding utf8)
            $lines.Count | Should -Be 3
            $lines[1] = $lines[1].Replace('D:\\B', 'D:\\X')
            Set-Content -LiteralPath $path -Value $lines -Encoding utf8
            Start-Conversation
            $answer = @((New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer) -split "`n")
            $answer.Count | Should -Be 3
            $answer[1] | Should -BeLike '*delete the files in C:\Temp*'
            $answer[2] | Should -Be '2 lines of my journal were changed outside Lambek: I left them out.'
            New-LambekPlan 'yesterday I deleted the files in C:\Logs' | Out-Null
            Start-Conversation
            $answer = @((New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer) -split "`n")
            $answer.Count | Should -Be 4
            $answer[2] | Should -BeLike '*delete the files in C:\Logs*'
        }

        It 'forgets everything when asked, in the conversation and on the disk' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            Test-Path -LiteralPath (Get-JournalPath) | Should -BeTrue
            New-LambekPlan 'forget what I told you' | ConvertTo-LambekAnswer | Should -Be 'Done: I have forgotten everything you told me.'
            Test-Path -LiteralPath (Get-JournalPath) | Should -BeFalse
            New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer | Should -Be 'You have not told me anything yet.'
        }

        It 'writes nothing in an incognito chat, and says it keeps it for the conversation only' {
            & (Get-Module Lambek) { $script:Incognito = $true }
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | ConvertTo-LambekAnswer | Should -BeLike '*I am keeping it for this conversation only.'
            Test-Path -LiteralPath (Get-JournalPath) | Should -BeFalse
            New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer | Should -BeLike '*delete the files in C:\Temp*'
            Start-Conversation
            New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer | Should -Be 'You have not told me anything yet.'
        }
    }

    It 'still answers small talk, and still asks what to do when nothing is recognised' {
        New-LambekPlan 'hello' | ConvertTo-LambekAnswer | Should -BeLike 'Hello*'
        (Resolve-Text 'what time is it').Act | Should -Be 'Order'
    }

    It 'reads every sentence as an order in a language that has no words for the rest yet' {
        (Resolve-Text 'lösche die .log dateien in C:\Temp').Act | Should -Be 'Order'
    }
}
