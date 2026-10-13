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
        @{ Text = 'I do not like it' }
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
            @{ Text = 'she likes it' }
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
            @{ Text = 'where does my sister live'; Rule = 'answer(E) :- event(E, "verb:live"), agent(E, "my sister"), says(E, "place"), not negated(E).' }
            @{ Text = 'who lives in France'; Rule = 'answer(E) :- event(E, "verb:live"), holds(E, "in", "france"), not negated(E).' }
            @{ Text = 'what did I buy yesterday'; Rule = 'answer(E) :- event(E, "verb:buy"), by(E, "speaker"), says(E, "object"), on(E, "2026-10-05"), not negated(E).' }
            @{ Text = 'what is my name'; Rule = 'answer(E) :- event(E, "verb:be"), about(E, "my name"), not negated(E).' }
            @{ Text = 'what did I delete yesterday'; Rule = 'answer(E) :- event(E, "files.delete"), by(E, "speaker"), on(E, "2026-10-05"), not negated(E).' }
            @{ Text = 'what have I told you'; Rule = 'answer(E) :- event(E, V), not deduced(E).' }
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
            # It is then said in the user's own words, quoted: never in a form ("Qui : ... Quoi : ...")
            New-LambekPlan 'tu sais, hier j''ai supprimé les fichiers dans C:\Temp' | ConvertTo-LambekAnswer | Should -BeLike 'Je comprends. Tu m''as dit : « tu sais, hier j''ai supprimé les fichiers dans C:\Temp ».*'
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
            New-LambekPlan 'my sister lives in Lyon' | ConvertTo-LambekAnswer | Should -Be 'Noted. Your sister lives in Lyon. I will remember it.'
            New-LambekPlan 'hier j''ai acheté une voiture' | ConvertTo-LambekAnswer | Should -Be 'C''est noté. Hier vous avez acheté une voiture. Je m''en souviendrai.'
        }
    }

    Context 'Questions, in French too' {
        BeforeEach {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
        }
        AfterAll {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
        }

        It 'reads the question as a rule: <Text>' -ForEach @(
            @{ Text = 'où habite ma sœur'; Rule = 'answer(E) :- event(E, "verb:habiter"), agent(E, "ma sœur"), says(E, "place"), not negated(E).' }
            @{ Text = 'où est-ce que ma sœur habite'; Rule = 'answer(E) :- event(E, "verb:habiter"), agent(E, "ma sœur"), says(E, "place"), not negated(E).' }
            @{ Text = 'qui habite à Lyon'; Rule = 'answer(E) :- event(E, "verb:habiter"), holds(E, "a", "lyon"), not negated(E).' }
            @{ Text = 'qu''est-ce que j''ai acheté hier'; Rule = 'answer(E) :- event(E, "verb:acheter"), by(E, "speaker"), says(E, "object"), on(E, "2026-10-05"), not negated(E).' }
            @{ Text = 'que fait ma sœur'; Rule = 'answer(E) :- event(E, V), not rule(E), not static(V), agent(E, "ma sœur"), not negated(E).' }
            @{ Text = 'comment je m''appelle'; Rule = 'answer(E) :- event(E, "verb:appeler"), by(E, "speaker"), says(E, "object"), not negated(E).' }
            @{ Text = 'comment s''appelle mon chat'; Rule = 'answer(E) :- event(E, "verb:appeler"), agent(E, "mon chat"), says(E, "object"), not negated(E).' }
            @{ Text = 'est-ce que ma sœur habite à Lyon'; Rule = 'answer(E) :- event(E, "verb:habiter"), agent(E, "ma sœur"), holds(E, "a", "lyon").' }
            @{ Text = 'does my sister live in Lyon'; Rule = 'answer(E) :- event(E, "verb:live"), agent(E, "my sister"), holds(E, "in", "lyon").' }
            @{ Text = 'is Lyon in France'; Rule = 'answer(E) :- event(E, "verb:be"), agent(E, "lyon"), holds(E, "in", "france").' }
        ) {
            $card = Resolve-Text $Text
            $card.Act | Should -Be 'Question'
            InModuleScope Lambek -Parameters @{ Asked = $card.Asked } { Get-LambekAskedRule -Asked $Asked } | Should -Be $Rule
        }

        It 'never takes a question that asks whether for something told: <Text>' -ForEach @(
            @{ Text = 'does my sister live in Lyon' }
            @{ Text = 'did I buy a car yesterday' }
            @{ Text = 'is Lyon in France' }
            @{ Text = 'est-ce que ma sœur habite à Lyon' }
        ) {
            New-LambekPlan $Text | Out-Null
            (Resolve-Text $Text).Statement | Should -BeNullOrEmpty
            New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer | Should -Be 'You have not told me anything yet.'
        }

        It 'answers "<Ask>" in French from what was told in French' -ForEach @(
            @{ Ask = 'où habite ma sœur'; Line = '- Votre sœur habite à Lyon.' }
            @{ Ask = 'où est-ce que ma sœur habite'; Line = '- Votre sœur habite à Lyon.' }
            @{ Ask = 'qui habite à Lyon'; Line = '- Votre sœur habite à Lyon.' }
            @{ Ask = 'est-ce que ma sœur habite à Lyon'; Line = '- Votre sœur habite à Lyon.' }
            @{ Ask = 'qu''est-ce que j''ai acheté hier'; Line = '- Hier vous avez acheté une voiture rouge.' }
            @{ Ask = 'comment je m''appelle'; Line = '- Vous vous appelez Amin.' }
            @{ Ask = 'comment s''appelle mon chat'; Line = '- Votre chat s''appelle Felix.' }
        ) {
            'ma sœur habite à Lyon', 'hier j''ai acheté une voiture rouge', 'je m''appelle Amin', 'mon chat s''appelle Felix' | ForEach-Object { New-LambekPlan $_ | Out-Null }
            New-LambekPlan $Ask | ConvertTo-LambekAnswer | Should -Be ("D'après ce qui m'a été dit dans cette conversation :", $Line -join "`n")
        }

        It 'deduces in French, whichever word of place the question uses' {
            New-LambekPlan 'ma sœur habite à Lyon' | Out-Null
            New-LambekPlan 'Lyon est en France' | Out-Null
            New-LambekPlan 'qui habite en France' | ConvertTo-LambekAnswer | Should -Be (@(
                    "D'après ce qui m'a été dit dans cette conversation :"
                    '- Votre sœur habite à Lyon.'
                    '  déduit avec : Lyon est en France.'
                ) -join "`n")
        }

        It 'says it does not know, never no: <Ask>' -ForEach @(
            @{ Ask = 'est-ce que ma sœur habite à Paris'; Said = "Je ne sais pas : on ne me l'a pas dit, et je ne sais pas encore le trouver seul." }
            @{ Ask = 'où habite mon père'; Said = "Je ne sais pas : on ne me l'a pas dit, et je ne sais pas encore le trouver seul." }
            @{ Ask = 'does my sister live in Spain'; Said = 'I do not know: nobody told me, and I cannot find it out by myself yet.' }
        ) {
            New-LambekPlan 'ma sœur habite à Lyon' | Out-Null
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            New-LambekPlan $Ask | ConvertTo-LambekAnswer | Should -Be $Said
        }

        It 'answers a question that asks whether with what it was told, and with what follows from it' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            New-LambekPlan 'Lyon is in France' | Out-Null
            New-LambekPlan 'does my sister live in France' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me in this conversation:'
                    '- Your sister lives in Lyon.'
                    '  deduced with: Lyon is in France.'
                ) -join "`n")
        }
    }

    Context 'Pronouns, negations, and several things in one sentence' {
        BeforeEach {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
        }
        AfterAll {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
        }

        It 'reads "<Text>" as the one the pronoun stands for' -ForEach @(
            @{ Before = @('my sister lives in Lyon'); Text = 'she works at a bank'; Said = 'Your sister works at a bank.' }
            @{ Before = @('my mother lives in Paris', 'my father lives in Lyon'); Text = 'he works at a bank'; Said = 'Your father works at a bank.' }
            @{ Before = @('my father lives in Lyon', 'my mother lives in Paris'); Text = 'she works at a bank'; Said = 'Your mother works at a bank.' }
            @{ Before = @('Paris is in France'); Text = 'it is in Europe'; Said = 'Paris is in Europe.' }
            @{ Before = @('ma sœur habite à Lyon'); Text = 'elle travaille à Paris'; Said = 'Votre sœur travaille à Paris.' }
            @{ Before = @('ma sœur habite à Lyon', 'Paris est en France'); Text = 'il est en France'; Said = 'Paris est en France.' }
        ) {
            $Before | ForEach-Object { New-LambekPlan $_ | Out-Null }
            New-LambekPlan $Text | ConvertTo-LambekAnswer | Should -BeLike "*$Said*"
        }

        It 'says it does not know who "<Pronoun>" is, and keeps nothing: <Text>' -ForEach @(
            @{ Before = @(); Text = 'he plays the guitar'; Pronoun = 'he' }
            @{ Before = @('my sister lives in Lyon'); Text = 'he lives in Paris'; Pronoun = 'he' }
            @{ Before = @('ma sœur habite à Lyon'); Text = 'il habite à Paris'; Pronoun = 'il' }
        ) {
            $Before | ForEach-Object { New-LambekPlan $_ | Out-Null }
            $answer = New-LambekPlan $Text | ConvertTo-LambekAnswer
            $answer | Should -Match ('["\u00AB] ?' + [regex]::Escape($Pronoun) + ' ?["\u00BB]')
            $answer | Should -Not -BeLike '*Lyon*Paris*'
            @(& (Get-Module Lambek) { (Get-LambekTold).ToArray() }).Count | Should -Be $Before.Count
        }

        It 'keeps what is denied apart, and both of two contrary things' {
            New-LambekPlan 'I like coffee' | Out-Null
            $answer = New-LambekPlan 'I do not like coffee' | ConvertTo-LambekAnswer
            $answer | Should -BeLike 'Noted. You do not like coffee.*'
            $answer | Should -BeLike '*You told me the opposite before: You like coffee. I am keeping both.'
            New-LambekPlan 'do I like coffee' | ConvertTo-LambekAnswer | Should -Be (@(
                    'You told me two things that say the opposite:'
                    '- You like coffee.'
                    '- You do not like coffee.'
                ) -join "`n")
        }

        It 'keeps what is denied apart in French too' {
            New-LambekPlan 'j''aime le café' | Out-Null
            New-LambekPlan 'je n''aime pas le café' | ConvertTo-LambekAnswer | Should -BeLike '*Vous n''aimez pas le café.*Vous m''avez dit le contraire avant : Vous aimez le café. Je garde les deux.'
            New-LambekPlan 'est-ce que j''aime le café' | ConvertTo-LambekAnswer | Should -Be (@(
                    'Vous m''avez dit deux choses contraires :'
                    '- Vous aimez le café.'
                    '- Vous n''aimez pas le café.'
                ) -join "`n")
        }

        It 'never answers with what was denied as if it had been said' {
            New-LambekPlan 'my sister does not live in Paris' | Out-Null
            New-LambekPlan 'who lives in Paris' | ConvertTo-LambekAnswer | Should -Be 'I do not know: nobody told me, and I cannot find it out by myself yet.'
            New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me in this conversation:'
                    '- Your sister does not live in Paris.'
                ) -join "`n")
        }

        It 'never takes an order in the negative for an order' {
            (Resolve-Text 'I do not delete the files in C:\A').Act | Should -Not -Be 'Order'
            @((New-LambekPlan 'I do not delete the files in C:\A').Steps | Where-Object { $_.Action }).Count | Should -Be 0
        }

        It 'reads two things told in one sentence: <Text>' -ForEach @(
            @{ Text = 'my sister lives in Lyon and my brother lives in Paris'; Said = 'Your sister lives in Lyon. Your brother lives in Paris.' }
            @{ Text = 'I live in Brussels and work in Antwerp'; Said = 'You live in Brussels. You work in Antwerp.' }
            @{ Text = 'my sister and my mother live in Lyon'; Said = 'Your sister lives in Lyon. Your mother lives in Lyon.' }
            @{ Text = 'I like tea, coffee and milk'; Said = 'You like tea. You like coffee. You like milk.' }
            @{ Text = 'my sister lived in Lyon and in Paris'; Said = 'Your sister lived in Lyon. Your sister lived in Paris.' }
            @{ Text = 'ma sœur habite à Lyon mais elle travaille à Paris'; Said = 'Votre sœur habite à Lyon. Votre sœur travaille à Paris.' }
            @{ Text = 'ma sœur et ma mère habitent à Lyon'; Said = 'Votre sœur habite à Lyon. Votre mère habite à Lyon.' }
            @{ Text = 'ma sœur a habité à Lyon et à Paris'; Said = 'Votre sœur a habité à Lyon. Votre sœur a habité à Paris.' }
        ) {
            New-LambekPlan $Text | ConvertTo-LambekAnswer | Should -BeLike "*$Said*"
        }

        It 'still makes two steps of two orders' {
            $plan = New-LambekPlan 'list the files in C:\A and delete the .tmp files in C:\B'
            @($plan.Steps).Count | Should -Be 2
        }

        It 'answers why with the reason told, or says none was' {
            New-LambekPlan 'I live in Brussels because I work in Antwerp' | Out-Null
            New-LambekPlan 'why do I live in Brussels' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me in this conversation:'
                    '- You live in Brussels.'
                    '  because: You work in Antwerp.'
                ) -join "`n")
            New-LambekPlan 'why do I work in Antwerp' | ConvertTo-LambekAnswer | Should -Be (@(
                    'From what you told me in this conversation:'
                    '- You work in Antwerp.'
                    '  you did not tell me why.'
                ) -join "`n")
            New-LambekPlan 'why is the sky blue' | ConvertTo-LambekAnswer | Should -Be 'I do not know: nobody told me, and I cannot find it out by myself yet.'
        }

        It 'answers pourquoi with the reason told' {
            New-LambekPlan 'ma sœur habite à Lyon parce qu''elle travaille à Lyon' | Out-Null
            New-LambekPlan 'pourquoi ma sœur habite à Lyon' | ConvertTo-LambekAnswer | Should -Be (@(
                    "D'après ce qui m'a été dit dans cette conversation :"
                    '- Votre sœur habite à Lyon.'
                    '  parce que : Votre sœur travaille à Lyon.'
                ) -join "`n")
        }

        It 'reads a French question by its order: <Text>' -ForEach @(
            @{ Text = 'est-ce que je travaille à Paris'; Asked = 'whether' }
            @{ Text = 'est-ce que j''aime le café'; Asked = 'whether' }
            @{ Text = 'que fait ma sœur'; Asked = 'object' }
            @{ Text = 'qu''est-ce que ma sœur a acheté'; Asked = 'object' }
        ) {
            $card = Resolve-Text $Text
            $card.Act | Should -Be 'Question'
            $card.Statement | Should -BeNullOrEmpty
            InModuleScope Lambek -Parameters @{ Text = $Text } { (Get-LambekGeneralReading -Request (ConvertTo-LambekRequest $Text)).Asked } | Should -Be $Asked
        }

        It 'tells the language by the small words of any sentence: <Text>' -ForEach @(
            @{ Text = 'je n''aime pas le café'; Language = 'fr' }
            @{ Text = 'ma sœur ne travaille pas à Paris'; Language = 'fr' }
            @{ Text = 'he plays the guitar'; Language = 'en' }
        ) {
            (ConvertTo-LambekRequest $Text).Language | Should -Be $Language
        }
    }

    Context 'Answers said as a person says them' {
        BeforeEach {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
        }
        AfterAll {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = $null }
        }

        It 'never answers in a form, who, what, when: <Text>' -ForEach @(
            @{ Text = 'my sister lives in Lyon' }
            @{ Text = 'I bought a red car yesterday' }
            @{ Text = 'yesterday I deleted the files in C:\Temp' }
            @{ Text = 'tu sais, hier j''ai supprimé les fichiers dans C:\Temp' }
            @{ Text = 'je suis né à Bruxelles' }
            @{ Text = 'I have two brothers' }
            @{ Text = 'il fait beau' }
        ) {
            $answer = New-LambekPlan $Text | ConvertTo-LambekAnswer
            $answer | Should -Not -Match '(Who|What|When|Wants): |(Qui|Quoi|Quand|Souhaite) : '
            New-LambekPlan 'what have I told you' | ConvertTo-LambekAnswer | Should -Not -Match '(Who|What|When|Wants): |(Qui|Quoi|Quand|Souhaite) : '
        }

        It 'simply notes what is not about files or code: <Text>' -ForEach @(
            @{ Text = 'my sister lives in Lyon'; Said = 'Noted. Your sister lives in Lyon. I will remember it.' }
            @{ Text = 'I have two brothers'; Said = 'Noted. You have two brothers. I will remember it.' }
            @{ Text = 'it is raining'; Said = 'Noted. It is raining. I will remember it.' }
            @{ Text = 'ma sœur habite à Lyon'; Said = 'C''est noté. Votre sœur habite à Lyon. Je m''en souviendrai.' }
            @{ Text = 'j''ai deux frères et 3 chats'; Said = 'C''est noté. Vous avez deux frères. Vous avez 3 chats. Je m''en souviendrai.' }
            @{ Text = 'il fait beau'; Said = 'C''est noté. Il fait beau. Je m''en souviendrai.' }
            @{ Text = 'il pleut'; Said = 'C''est noté. Il pleut. Je m''en souviendrai.' }
        ) {
            New-LambekPlan $Text | ConvertTo-LambekAnswer | Should -Be $Said
        }

        It 'says that it keeps it for the conversation only in an incognito chat' {
            & (Get-Module Lambek) { $script:Incognito = $true }
            New-LambekPlan 'my brother lives in Ghent' | ConvertTo-LambekAnswer | Should -Be 'Noted. Your brother lives in Ghent. I will remember it for this conversation only.'
        }

        It 'speaks to the user as the user speaks: <Text>' -ForEach @(
            @{ Text = 'je m''appelle Amin'; Said = 'C''est noté. Tu t''appelles Amin. Je m''en souviendrai.' }
            @{ Text = 'ma sœur habite à Lyon'; Said = 'C''est noté. Ta sœur habite à Lyon. Je m''en souviendrai.' }
            @{ Text = 'je n''aime pas le café'; Said = 'C''est noté. Tu n''aimes pas le café. Je m''en souviendrai.' }
        ) {
            New-LambekPlan $Text | ConvertTo-LambekAnswer -Register tu | Should -Be $Said
        }

        It 'says a contrary thing to the user as the user speaks' {
            New-LambekPlan 'j''aime le café' | Out-Null
            New-LambekPlan 'je n''aime pas le café' | ConvertTo-LambekAnswer -Register tu | Should -BeLike '*Tu m''as dit le contraire avant : Tu aimes le café. Je garde les deux.'
        }

        It 'quotes the user when its own sentence would not read back the same' {
            InModuleScope Lambek {
                $fact = [pscustomobject]@{ Action = 'verb:live'; Parameters = [ordered]@{ in = 'Lyon' }; What = 'live in Lyon'; Agent = 'other'; Name = 'my sister'; Wish = $false; Time = 'yesterday'; Day = $null; Text = 'I work in Paris'; Language = 'en'; Negated = $false }
                Format-LambekFact -Fact $fact -Language en | Should -Be 'You told me: "I work in Paris".'
                Format-LambekFact -Fact $fact -Language fr | Should -Be 'Vous m''avez dit : « I work in Paris ».'
                # Without the words it was told in: what it is about, then what
                $fact.Text = ''
                Format-LambekFact -Fact $fact -Language en | Should -Be 'About my sister: live in Lyon (yesterday).'
            }
        }

        It 'reads the weather as about nobody: <Text>' -ForEach @(
            @{ Told = 'il pleut'; Text = 'est-ce qu''il pleut'; Line = '- Il pleut.' }
            @{ Told = 'it is raining'; Text = 'is it raining'; Line = '- It is raining.' }
        ) {
            New-LambekPlan $Told | Out-Null
            New-LambekPlan $Text | ConvertTo-LambekAnswer | Should -BeLike "*`n$Line"
        }

        It 'never takes the "il" of the weather for someone' {
            New-LambekPlan 'il pleut' | Out-Null
            New-LambekPlan 'il habite à Paris' | ConvertTo-LambekAnswer | Should -BeLike '*« il »*'
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
