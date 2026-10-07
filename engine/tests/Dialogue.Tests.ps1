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
        @{ Text = 'trouve une idée de cadeau pour ma mère' }
    ) {
        $card = Resolve-Text $Text
        $card.Act | Should -Be 'Other'
        $card.Status | Should -Be 'Unknown'
        $card.Action | Should -BeNullOrEmpty
    }

    It 'says how it read the sentence, and proposes no request in its place' {
        $plan = New-LambekPlan 'she deleted her account last week'
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
        @{ Text = 'she deleted her account last week' }
        @{ Text = 'I do not like coffee' }
        @{ Text = 'ils ont déplacé la réunion à jeudi' }
        @{ Text = 'delete the files in C:\Temp' }
    ) {
        (Resolve-Text $Text).Statement | Should -BeNullOrEmpty
    }

    It 'says back who, what and when' {
        New-LambekPlan 'yesterday I deleted the files in C:\Temp' | ConvertTo-LambekAnswer | Should -Be 'I understand. Yesterday you deleted the files in C:\Temp. You are telling me, so I am not doing it. I am keeping it.'
        New-LambekPlan 'mon collègue veut supprimer les fichiers .log de C:\Temp' | ConvertTo-LambekAnswer | Should -BeLike 'Je comprends. Votre collègue veut supprimer les fichiers .log de C:\Temp.*'
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
            @{ Ask = 'what did I delete yesterday'; Line = '- Yesterday you deleted the files in C:\Temp.' }
            @{ Ask = 'what did I delete'; Line = '- Yesterday you deleted the files in C:\Temp.' }
            @{ Ask = 'did I delete the files in C:\Temp'; Line = '- Yesterday you deleted the files in C:\Temp.' }
            @{ Ask = 'what did I move last week'; Line = '- Last week you moved the .pdf files from C:\A to D:\B.' }
            @{ Ask = 'what did my colleague copy'; Line = '- Your colleague copied report.txt to D:\Backup this morning.' }
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
            $lines[1] | Should -BeLike '*deleted the files in C:\Temp*'
            $lines[2] | Should -BeLike '*moved the .pdf files*'
        }

        It 'answers in French from what was told in French' {
            New-LambekPlan 'hier j''ai supprimé les fichiers .log dans C:\Temp' | Out-Null
            New-LambekPlan 'qu''est-ce que j''ai supprimé hier' | ConvertTo-LambekAnswer | Should -Be ("D'après ce qui m'a été dit dans cette conversation :", '- Hier vous avez supprimé les fichiers .log dans C:\Temp.' -join "`n")
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
            (Resolve-LambekFollowUp -Plan $plan -Text 'what did I rename').Answer | Should -BeLike '*renamed report.txt to summary.txt*'
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
            New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer | Should -Be ('From what you told me before:', '- Told on 2026-10-06. Yesterday you deleted the files in C:\Temp. (2026-10-05)' -join "`n")
        }

        It 'does not take the yesterday of another day for the yesterday of today' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            Start-Conversation
            Start-Day '2026-10-09 09:00'
            New-LambekPlan 'what did I delete yesterday' | ConvertTo-LambekAnswer | Should -Be 'You have not told me that.'
            Start-Day '2026-10-06 18:00'
            New-LambekPlan 'what did I delete yesterday' | ConvertTo-LambekAnswer | Should -BeLike '*deleted the files in C:\Temp*'
        }

        It 'says what was told in this conversation first, then what was told before, once each' {
            New-LambekPlan 'yesterday I deleted the files in C:\Temp' | Out-Null
            Start-Conversation
            Start-Day '2026-10-09 09:00'
            New-LambekPlan 'yesterday I deleted the .log files in C:\Logs' | Out-Null
            New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me in this conversation:'
                    '- Yesterday you deleted the .log files in C:\Logs.'
                    'From what you told me before:'
                    '- Told on 2026-10-06. Yesterday you deleted the files in C:\Temp. (2026-10-05)'
                ) -join "`n")
        }

        It 'keeps the words of the day: accents, and the language it was told in' {
            New-LambekPlan 'mon collègue a copié l''été.txt vers D:\Backup ce matin' | Out-Null
            Start-Conversation
            New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer | Should -Be ('From what you told me before:', '- Told on 2026-10-06. Votre collègue a copié l''été.txt vers D:\Backup ce matin. (2026-10-06)' -join "`n")
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
            $answer[1] | Should -BeLike '*deleted the files in C:\Temp*'
            $answer[2] | Should -Be '2 lines of my journal were changed outside Lambek: I left them out.'
            New-LambekPlan 'yesterday I deleted the files in C:\Logs' | Out-Null
            Start-Conversation
            $answer = @((New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer) -split "`n")
            $answer.Count | Should -Be 4
            $answer[2] | Should -BeLike '*deleted the files in C:\Logs*'
        }

        It 'keeps the conversation of each chat of the app apart' {
            $audit = Join-Path $TestDrive 'audit.jsonl'
            function Send-Ask {
                param([string] $Text, [string] $Chat)
                $line = @{ id = 1; method = 'ask'; params = @{ text = $Text; chat = $Chat } } | ConvertTo-Json -Compress -Depth 5
                InModuleScope Lambek -Parameters @{ Line = $line; Audit = $audit } { (Invoke-LambekHostRequest -Line $Line -AuditPath $Audit | ConvertFrom-Json).result.answer }
            }
            Send-Ask 'yesterday I deleted the files in C:\Temp' 'one' | Should -BeLike 'I understand.*'
            Send-Ask 'what did I delete' 'one' | Should -BeLike 'From what you told me in this conversation:*'
            Send-Ask 'what did I delete' 'two' | Should -BeLike 'From what you told me before:*'
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
            New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer | Should -BeLike '*deleted the files in C:\Temp*'
            Start-Conversation
            New-LambekPlan 'what did I delete' | ConvertTo-LambekAnswer | Should -Be 'You have not told me anything yet.'
        }
    }

    Context 'Sentences about anything' {
        BeforeEach {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
        }
        AfterAll {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
        }

        It 'reads who, the verb, what and where, with the words of the dictionary: <Text>' -ForEach @(
            @{ Text = 'my sister lives in Lyon'; Form = 'told(live(agent("my sister"), in("Lyon")))' }
            @{ Text = 'I bought a red car yesterday'; Form = 'told(buy(agent(speaker), object("a red car")), time("yesterday"))' }
            @{ Text = 'my brother works at a bank in Brussels'; Form = 'told(work(agent("my brother"), at("a bank"), in("Brussels")))' }
            @{ Text = 'my boss moved to Paris last year'; Form = 'told(move(agent("my boss"), to("Paris")), time("last year"))' }
            @{ Text = 'my name is Amin'; Form = 'told(be(agent("my name"), object("Amin")))' }
            @{ Text = 'hier j''ai acheté une voiture'; Form = 'told(acheter(agent(speaker), object("une voiture")), time("hier"))' }
            @{ Text = 'la liste des courses est sur la table'; Form = 'told(être(agent("la liste des courses"), sur("la table")))' }
        ) {
            $card = Resolve-Text $Text
            $card.Act | Should -Be 'Report'
            $card.Statement.Form | Should -Be $Form
            $card.Status | Should -Be 'Unknown'
            $card.Action | Should -BeNullOrEmpty
        }

        It 'reads nothing it cannot read whole: <Text>' -ForEach @(
            @{ Text = 'I do not like coffee' }
            @{ Text = 'she lives in Lyon' }
            @{ Text = 'my sister lives in Lyon because she works there' }
            @{ Text = 'answers small talk in the language of the plan' }
            @{ Text = 'blorp the zork' }
            @{ Text = 'I want the pdf ones' }
            @{ Text = 'who are you' }
        ) {
            $card = Resolve-Text $Text
            $card.Statement | Should -BeNullOrEmpty
            $card.Asked | Should -BeNullOrEmpty
        }

        It 'leaves to the packs a sentence that names a place or a file: <Text>' -ForEach @(
            @{ Text = 'what is inside C:\Data'; Act = 'Order' }
            @{ Text = 'delete the files in C:\Temp'; Act = 'Order' }
            @{ Text = 'yesterday I deleted the files in C:\Temp'; Act = 'Report' }
        ) {
            $card = Resolve-Text $Text
            $card.Act | Should -Be $Act
            if ($card.Statement) { $card.Statement.Action | Should -Be 'files.delete' }
        }

        It 'answers "<Ask>" from what was told' -ForEach @(
            @{ Ask = 'where does my sister live'; Line = '- Your sister lives in Lyon.' }
            @{ Ask = 'who lives in Lyon'; Line = '- Your sister lives in Lyon.' }
            @{ Ask = 'what did I buy yesterday'; Line = '- You bought a red car yesterday.' }
            @{ Ask = 'what did I buy'; Line = '- You bought a red car yesterday.' }
            @{ Ask = 'what is my name'; Line = '- Your name is Amin.' }
        ) {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            New-LambekPlan 'I bought a red car yesterday' | Out-Null
            New-LambekPlan 'my name is Amin' | Out-Null
            New-LambekPlan $Ask | ConvertTo-LambekAnswer | Should -Be ('From what you told me in this conversation:', $Line -join "`n")
        }

        It 'says it does not know what nobody told: <Ask>' -ForEach @(
            @{ Ask = 'where does my boss live' }
            @{ Ask = 'what did I buy last week' }
            @{ Ask = 'what is the weather' }
        ) {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            New-LambekPlan 'I bought a red car yesterday' | Out-Null
            New-LambekPlan $Ask | ConvertTo-LambekAnswer | Should -Be 'I do not know: nobody told me, and I cannot find it out by myself yet.'
        }

        It 'reads the word typed, not a word of a pack that looks like it' {
            # "live" is one letter from "move"
            (Resolve-Text 'where does my sister live').Asked.Actions | Should -Be 'verb:live'
        }

        It 'keeps it across conversations like anything else told' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            & (Get-Module Lambek) { $script:Told = $null; $script:ToldJournal = $null }
            New-LambekPlan 'where does my sister live' | ConvertTo-LambekAnswer | Should -Be ('From what you told me before:', '- Told on 2026-10-06. Your sister lives in Lyon.' -join "`n")
        }

        It 'still takes a reply to its own question as a reply' {
            $plan = New-LambekPlan 'delete the files'
            $plan.Status | Should -Be 'NeedsInput'
            (Resolve-LambekFollowUp -Plan $plan -Text 'the folder is C:\Temp').Kind | Should -Not -Be 'explain'
        }
    }

    Context 'What follows from what was told' {
        BeforeEach {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
        }
        AfterAll {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
        }

        It 'reads a question as the body of a rule: <Text>' -ForEach @(
            @{ Text = 'where does my sister live'; Rule = 'answer(E) :- event(E, "verb:live"), agent(E, "my sister"), says(E, "place").' }
            @{ Text = 'who lives in France'; Rule = 'answer(E) :- event(E, "verb:live"), holds(E, "in", "france").' }
            @{ Text = 'what did I buy yesterday'; Rule = 'answer(E) :- event(E, "verb:buy"), by(E, "speaker"), says(E, "object"), on(E, "2026-10-05").' }
            @{ Text = 'what is my name'; Rule = 'answer(E) :- event(E, "verb:be"), about(E, "my name").' }
            @{ Text = 'what did I delete yesterday'; Rule = 'answer(E) :- event(E, "files.delete"), by(E, "speaker"), on(E, "2026-10-05").' }
            @{ Text = 'what have I told you'; Rule = 'answer(E) :- event(E, V).' }
        ) {
            $asked = (Resolve-Text $Text).Asked
            InModuleScope Lambek -Parameters @{ Asked = $asked } { Get-LambekAskedRule -Asked $Asked } | Should -Be $Rule
        }

        It 'deduces where someone is from where a place is, and says what it deduced it with' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            New-LambekPlan 'Lyon is in France' | Out-Null
            New-LambekPlan 'France is in Europe' | Out-Null
            New-LambekPlan 'who lives in France' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me in this conversation:'
                    '- Your sister lives in Lyon.'
                    '  deduced with: Lyon is in France.'
                ) -join "`n")
            New-LambekPlan 'who lives in Europe' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me in this conversation:'
                    '- Your sister lives in Lyon.'
                    '  deduced with: Lyon is in France.'
                    '  deduced with: France is in Europe.'
                ) -join "`n")
        }

        It 'deduces nothing that does not follow' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            New-LambekPlan 'Lyon is in France' | Out-Null
            New-LambekPlan 'who lives in Spain' | ConvertTo-LambekAnswer | Should -Be 'I do not know: nobody told me, and I cannot find it out by myself yet.'
            # France is not in Lyon: the rule goes one way only
            New-LambekPlan 'my brother lives in France' | Out-Null
            New-LambekPlan 'who lives in Lyon' | ConvertTo-LambekAnswer | Should -Be ('From what you told me in this conversation:', '- Your sister lives in Lyon.' -join "`n")
        }

        It 'says nothing of a deduction when the answer was told as it is' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            New-LambekPlan 'Lyon is in France' | Out-Null
            New-LambekPlan 'who lives in Lyon' | ConvertTo-LambekAnswer | Should -Be ('From what you told me in this conversation:', '- Your sister lives in Lyon.' -join "`n")
        }

        It 'deduces with what was told in another conversation' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            & (Get-Module Lambek) { $script:Told = $null; $script:ToldJournal = $null }
            New-LambekPlan 'Lyon is in France' | Out-Null
            New-LambekPlan 'who lives in France' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me before:'
                    '- Told on 2026-10-06. Your sister lives in Lyon.'
                    '  deduced with: Lyon is in France.'
                ) -join "`n")
        }

        It 'explains an answer with the proof of the logic' {
            $proof = InModuleScope Lambek {
                $facts = @(
                    ConvertTo-LambekRequest 'my sister lives in Lyon' | Resolve-LambekIntent | ForEach-Object { $_.Statement }
                    ConvertTo-LambekRequest 'Lyon is in France' | Resolve-LambekIntent | ForEach-Object { $_.Statement }
                )
                $logic = Get-LambekToldLogic -Facts $facts
                $logic.Run()
                $logic.Explain('holds', [string[]] @('e0', 'in', 'france'), 6)
            }
            $proof[0] | Should -Be 'holds("e0", "in", "france") :-'
            $proof | Should -Contain '  role("e0", "in", "lyon")'
            ($proof -join "`n") | Should -BeLike '*inside("lyon", "france")*'
        }
    }

    Context 'Saying it back' {
        BeforeEach {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
        }
        AfterAll {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
        }

        It 'turns the sentence to the other side: <Text>' -ForEach @(
            @{ Language = 'en'; Text = 'I bought a red car yesterday'; Said = 'You bought a red car yesterday.' }
            @{ Language = 'en'; Text = 'my sister lives in Lyon'; Said = 'Your sister lives in Lyon.' }
            @{ Language = 'en'; Text = 'I am tired today'; Said = 'You are tired today.' }
            @{ Language = 'en'; Text = 'we have a meeting with the client on Friday'; Said = 'You have a meeting with the client on Friday.' }
            @{ Language = 'en'; Text = 'yesterday I deleted the files in C:\Temp'; Said = 'Yesterday you deleted the files in C:\Temp.' }
            @{ Language = 'en'; Text = 'Lyon is in France'; Said = 'Lyon is in France.' }
            @{ Language = 'fr'; Text = 'hier j''ai acheté une voiture'; Said = 'Hier vous avez acheté une voiture.' }
            @{ Language = 'fr'; Text = 'ma sœur habite à Lyon'; Said = 'Votre sœur habite à Lyon.' }
            @{ Language = 'fr'; Text = 'je m''appelle Amin'; Said = 'Vous vous appelez Amin.' }
            @{ Language = 'fr'; Text = 'je suis fatigué'; Said = 'Vous êtes fatigué.' }
            @{ Language = 'fr'; Text = 'nous avons une réunion avec le client'; Said = 'Vous avez une réunion avec le client.' }
        ) {
            InModuleScope Lambek -Parameters @{ Text = $Text; Language = $Language } { ConvertTo-LambekOtherSide -Text $Text -Language $Language } | Should -BeExactly $Said
        }

        It 'says "tu" to who says "tu": <Text>' -ForEach @(
            @{ Text = 'hier j''ai acheté une voiture'; Said = 'Hier tu as acheté une voiture.' }
            @{ Text = 'ma sœur habite à Lyon'; Said = 'Ta sœur habite à Lyon.' }
            @{ Text = 'je m''appelle Amin'; Said = 'Tu t''appelles Amin.' }
            @{ Text = 'nous avons une réunion avec le client'; Said = 'Vous avez une réunion avec le client.' }
        ) {
            InModuleScope Lambek -Parameters @{ Text = $Text } { ConvertTo-LambekOtherSide -Text $Text -Language fr -Register tu } | Should -BeExactly $Said
        }

        It 'never rewrites a place, a file or a name between quotes' {
            InModuleScope Lambek { ConvertTo-LambekOtherSide -Text 'I renamed my.report.txt to "my summary.txt" in C:\Users\me\my files' -Language en } | Should -BeExactly 'You renamed my.report.txt to "my summary.txt" in C:\Users\me\my files.'
        }

        It 'does not turn round a sentence that already speaks to Lambek' {
            InModuleScope Lambek { ConvertTo-LambekOtherSide -Text 'tu sais, hier j''ai supprimé les fichiers dans C:\Temp' -Language fr } | Should -BeNullOrEmpty
            # It is then said plainly: who, what, when
            New-LambekPlan 'tu sais, hier j''ai supprimé les fichiers dans C:\Temp' | ConvertTo-LambekAnswer | Should -BeLike 'Je comprends. Qui : toi. Quoi : supprimer les fichiers dans C:\Temp. Quand : hier.*'
        }

        It 'reads its own sentence again, and says it only when it gives the same thing told' {
            InModuleScope Lambek {
                $fact = (ConvertTo-LambekRequest 'my sister lives in Lyon' | Resolve-LambekIntent).Statement
                Test-LambekSaidBack -Fact $fact -Sentence 'Your sister lives in Lyon.' | Should -BeTrue
                # Another verb, another place, another one: not the same thing
                Test-LambekSaidBack -Fact $fact -Sentence 'Your sister works in Lyon.' | Should -BeFalse
                Test-LambekSaidBack -Fact $fact -Sentence 'Your sister lives in Paris.' | Should -BeFalse
                Test-LambekSaidBack -Fact $fact -Sentence 'Your brother lives in Lyon.' | Should -BeFalse
                Test-LambekSaidBack -Fact $fact -Sentence 'You live in Lyon.' | Should -BeFalse
                $fact = (ConvertTo-LambekRequest 'yesterday I deleted the files in C:\Temp' | Resolve-LambekIntent).Statement
                Test-LambekSaidBack -Fact $fact -Sentence 'Yesterday you deleted the files in C:\Temp.' | Should -BeTrue
                Test-LambekSaidBack -Fact $fact -Sentence 'Yesterday you deleted the files in C:\Windows.' | Should -BeFalse
            }
        }

        It 'answers with whole sentences' {
            New-LambekPlan 'my sister lives in Lyon' | ConvertTo-LambekAnswer | Should -Be 'I understand. Your sister lives in Lyon. You are telling me, so I am not doing it. I am keeping it.'
            New-LambekPlan 'hier j''ai acheté une voiture' | ConvertTo-LambekAnswer | Should -Be 'Je comprends. Hier vous avez acheté une voiture. C''est une information, donc je ne fais rien. Je la retiens.'
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
