BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'The blackboard' {

    Context 'What a thing is, where it comes from, and what it rests on' {

        It 'keeps a thing once, with its status, source and day' {
            $board = [LambekBoard]::new()
            $fact = [pscustomobject]@{ Name = 'one' }
            $entry = $board.Put($fact, 'told', 'user', '2026-10-06', 'live(agent("my sister"), in("Lyon"))', $false, $null, 'f1', [int[]] @())
            $again = $board.Put($fact, 'read', 'other', '2026-10-07', 'x()', $true, $null, 'f2', [int[]] @())
            $board.Count | Should -Be 1
            $again.Id | Should -Be $entry.Id
            $entry.Status | Should -Be 'told'
            $entry.Source | Should -Be 'user'
            $entry.Day | Should -Be '2026-10-06'
        }

        It 'knows only the statuses told, read, deduced, assumed and imagined' {
            $board = [LambekBoard]::new()
            { $board.Put([pscustomobject]@{}, 'rumour', 'user', '', 'a()', $false, $null, '', [int[]] @()) } | Should -Throw '*Unknown status*'
            [LambekBoard]::Statuses -join ' ' | Should -Be 'told read deduced assumed imagined'
        }

        It 'lets a deduced thing rest only on things already on the board' {
            $board = [LambekBoard]::new()
            $first = $board.Put([pscustomobject]@{}, 'told', 'user', '', 'in("lyon", "france")', $false, $null, 'a', [int[]] @())
            $deduced = $board.Put([pscustomobject]@{}, 'deduced', 'logic', '', 'in("x", "france")', $false, $null, 'b', [int[]] @($first.Id))
            $deduced.Basis | Should -Be @($first.Id)
            { $board.Put([pscustomobject]@{}, 'deduced', 'logic', '', 'c()', $false, $null, 'c', [int[]] @(99)) } | Should -Throw '*already on the board*'
        }
    }

    Context 'The same meaning whatever the order it was said in' {

        It 'reads <A> and <B> as the same thing' -ForEach @(
            @{ A = 'habiter(agent("ma soeur"), a("Lyon"), avec("Marie"))|'; B = 'habiter(agent("ma soeur"), avec("Marie"), a("Lyon"))|' }
            @{ A = 'live(agent(speaker), in("Lyon"), with("Marie"))|2026-10-05'; B = 'live(with("Marie"), agent(speaker), in("Lyon"))|2026-10-05' }
        ) {
            [LambekBoard]::Canonical($A) | Should -Be ([LambekBoard]::Canonical($B))
        }

        It 'keeps the day apart: the same thing another day is another thing' {
            [LambekBoard]::Canonical('go(agent(speaker))|2026-10-05') | Should -Not -Be ([LambekBoard]::Canonical('go(agent(speaker))|2026-10-06'))
        }

        It 'keeps as it is what does not read as terms' {
            [LambekBoard]::Canonical('say(agent("a "b"))|') | Should -Be 'say(agent("a "b"))|'
            [LambekBoard]::Canonical('say(agent("a, b"), to("c"))|') | Should -Be 'say(agent("a, b"), to("c"))|'
        }
    }

    Context 'A thing and its contrary both stay' {

        BeforeAll {
            function New-Told {
                param([string] $Core, [bool] $Negated, [string] $Day = '2026-10-06', [string] $Status = 'told', $Board)
                $fact = [pscustomobject]@{ Core = $Core; Negated = $Negated; Form = "$Core|$Negated|$Day|$Status" }
                [void] $Board.Put($fact, $Status, 'user', $Day, $Core, $Negated, $null, $fact.Form, [int[]] @())
                return $fact
            }
        }

        It 'gives the four values of Belnap' {
            $board = [LambekBoard]::new()
            $yes = New-Told 'live(agent("my sister"), in("Lyon"))|' $false -Board $board
            $no = New-Told 'live(in("Lyon"), agent("my sister"))|' $true -Board $board
            $key = 'live(agent("my sister"), in("Lyon"))|'
            $board.Value($key, [object[]] @($yes)) | Should -Be 'true'
            $board.Value($key, [object[]] @($no)) | Should -Be 'false'
            $board.Value($key, [object[]] @($yes, $no)) | Should -Be 'both'
            $board.Value('work(agent("my sister"))|', [object[]] @($yes, $no)) | Should -Be 'none'
            $board.Count | Should -Be 2
        }

        It 'finds the contrary whatever the order of its parts' {
            $board = [LambekBoard]::new()
            $yes = New-Told 'habiter(agent("ma soeur"), a("Lyon"), avec("Marie"))|' $false -Board $board
            $no = New-Told 'habiter(agent("ma soeur"), avec("Marie"), a("Lyon"))|' $true -Board $board
            @($board.Contraries($no, $no.Core, $true, [object[]] @($yes, $no))) | Should -Be @($yes)
        }

        It 'never counts an idea as a fact' {
            $board = [LambekBoard]::new()
            $idea = New-Told 'name(agent("the cat"), object("Fourviere"))|' $false -Status 'imagined' -Board $board
            $board.Value('name(agent("the cat"), object("Fourviere"))|', [object[]] @($idea)) | Should -Be 'none'
        }

        It 'acts on the strongest, then the latest, and keeps the others' {
            $board = [LambekBoard]::new()
            $old = New-Told 'live(agent("my sister"), in("Lyon"))|' $false -Day '2026-10-01' -Board $board
            $new = New-Told 'live(agent("my sister"), in("Lyon"))|' $true -Day '2026-10-05' -Board $board
            $guess = New-Told 'live(agent("my sister"), in("Lyon"))|' $false -Day '2026-10-09' -Status 'assumed' -Board $board
            $board.Preferred('live(in("Lyon"), agent("my sister"))|', [object[]] @($old, $new, $guess)) | Should -Be $new
            $board.Count | Should -Be 3
        }
    }

    Context 'Everything told goes on the board' {

        BeforeEach {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:ToldJournal = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
        }
        AfterAll {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
        }

        It 'puts a thing told on the board, here and in the journal' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            $entries = @(& (Get-Module Lambek) { (Get-LambekBoard).Entries() })
            @($entries | Where-Object Source -EQ 'user').Count | Should -Be 1
            @($entries | Where-Object Source -EQ 'journal').Count | Should -Be 1
            $entries[0].Status | Should -Be 'told'
            $entries[0].Day | Should -Be '2026-10-06'
        }

        It 'writes the status and the source on the line of the journal' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            $path = & (Get-Module Lambek) { $script:ToldPath }
            $line = Get-Content -LiteralPath $path -Encoding utf8 | Select-Object -First 1 | ConvertFrom-Json
            $line.Status | Should -Be 'told'
            $line.Source | Should -Be 'user'
        }

        It 'reads the journal of another conversation back onto the board' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            & (Get-Module Lambek) { $script:Told = $null; $script:ToldJournal = $null; [void] (Get-LambekToldJournal) }
            $entries = @(& (Get-Module Lambek) { (Get-LambekBoard).Entries() })
            @($entries | Where-Object Source -EQ 'journal').Count | Should -Be 1
        }

        It 'sees the contrary of a thing told in another order' {
            New-LambekPlan 'ma soeur habite à Lyon avec Marie' | Out-Null
            $answer = New-LambekPlan "ma soeur n'habite pas avec Marie à Lyon" | ConvertTo-LambekAnswer
            $answer | Should -BeLike "*Vous m'avez dit le contraire avant*habite à Lyon avec Marie*Je garde les deux*"
        }

        It 'empties the board when asked to forget' {
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            New-LambekPlan 'forget what I told you' | ConvertTo-LambekAnswer | Out-Null
            & (Get-Module Lambek) { (Get-LambekBoard).Count } | Should -Be 0
        }

        It 'keeps a thing told in an incognito chat on the board for the conversation only' {
            & (Get-Module Lambek) { $script:Incognito = $true }
            New-LambekPlan 'my sister lives in Lyon' | Out-Null
            $entries = @(& (Get-Module Lambek) { (Get-LambekBoard).Entries() })
            @($entries | Where-Object Source -EQ 'user').Count | Should -Be 1
            @($entries | Where-Object Source -EQ 'journal').Count | Should -Be 0
        }
    }
}
