BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Ask {
        param([string] $Text)
        New-LambekPlan $Text | ConvertTo-LambekAnswer
    }
    function Tell {
        param([string[]] $Text)
        foreach ($line in $Text) { New-LambekPlan $line | Out-Null }
    }
}

Describe 'Solving problems told in words' {

    BeforeEach {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
    }
    AfterAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
    }

    Context 'Quantities' {

        It 'solves a problem of ages, says the equations, and checks every value in every one of them' {
            Ask 'Marie a 2 ans de plus que Paul. À eux deux, ils ont 30 ans. Quel âge a Marie ?' | Should -Be (@(
                    'Marie a 16 ans.'
                    'Et Paul a 14 ans.'
                    'Les équations :'
                    '- Marie = Paul + 2'
                    '- Marie + Paul = 30'
                    "Vérification : 16 = 14 + 2 $([char] 0x2713) ; 16 + 14 = 30 $([char] 0x2713)."
                ) -join "`n")
        }

        It 'says why, with what was told and the equations' {
            Ask 'Marie a 2 ans de plus que Paul. À eux deux, ils ont 30 ans. Quel âge a Marie ?' | Out-Null
            Ask 'pourquoi ?' | Should -Be (@(
                    "Parce que vous m'avez dit :"
                    '- Marie a 2 ans de plus que Paul.'
                    '- À eux deux, ils ont 30 ans.'
                    'Et le calcul : Marie = Paul + 2 ; Marie + Paul = 30.'
                ) -join "`n")
        }

        It 'solves with what was told in the turns before' {
            Tell "j'ai 3 chats"
            Ask 'ma soeur a 2 chats de plus que moi' | Should -Be "C'est noté. Votre soeur a 2 chats de plus que vous. Je m'en souviendrai."
            @((Ask 'combien de chats a ma soeur ?') -split "`n")[0] | Should -Be 'Votre soeur a 5 chats.'
            @((Ask 'combien de chats avons-nous en tout ?') -split "`n")[0] | Should -Be '8 chats en tout.'
        }

        It 'solves: <Problem>' -ForEach @(
            @{ Problem = 'Paul a 3 fois plus de billes que Léa. Ensemble, ils ont 48 billes. Combien de billes a Léa ?'; First = 'Léa a 12 billes.'; Check = "Vérification : 36 = 3 $([char] 0x00D7) 12 $([char] 0x2713) ; 36 + 12 = 48 $([char] 0x2713)." }
            @{ Problem = "Un père a 3 fois l'âge de son fils. À eux deux, ils ont 48 ans. Quel âge a le fils ?"; First = 'Son fils a 12 ans.'; Check = "Vérification : 36 = 3 $([char] 0x00D7) 12 $([char] 0x2713) ; 36 + 12 = 48 $([char] 0x2713)." }
            @{ Problem = 'Léa a 5 ans de moins que son frère. Son frère a 12 ans. Quel âge a Léa ?'; First = 'Léa a 7 ans.'; Check = "Vérification : 7 = 12 - 5 $([char] 0x2713)." }
            @{ Problem = "J'ai 4 pommes de plus que Tom. Tom a 7 pommes. Combien de pommes ai-je ?"; First = 'Vous avez 11 pommes.'; Check = "Vérification : 11 = 7 + 4 $([char] 0x2713)." }
            @{ Problem = 'Marie is 2 years older than Paul. Together they are 30 years old. How old is Marie?'; First = 'Marie is 16 years old.'; Check = "Check: 16 = 14 + 2 $([char] 0x2713) ; 16 + 14 = 30 $([char] 0x2713)." }
            @{ Problem = 'Tom has 3 more apples than Sam. Together they have 17 apples. How many apples does Sam have?'; First = 'Sam has 7 apples.'; Check = "Check: 10 = 7 + 3 $([char] 0x2713) ; 10 + 7 = 17 $([char] 0x2713)." }
            @{ Problem = 'Mon frère a 2 fois plus de livres que moi. Nous avons 27 livres en tout. Combien de livres ai-je ?'; First = 'Vous avez 9 livres.'; Check = "Vérification : 18 = 2 $([char] 0x00D7) 9 $([char] 0x2713) ; 18 + 9 = 27 $([char] 0x2713)." }
            @{ Problem = 'Kim has twice as many marbles as Lee. Lee has 9 marbles. How many marbles does Kim have?'; First = 'Kim has 18 marbles.'; Check = "Check: 18 = 2 $([char] 0x00D7) 9 $([char] 0x2713)." }
            @{ Problem = 'Sophie a 6 bonbons de moins que Hugo. Ensemble, ils ont 40 bonbons. Combien de bonbons a Hugo ?'; First = 'Hugo a 23 bonbons.'; Check = "Vérification : 17 = 23 - 6 $([char] 0x2713) ; 17 + 23 = 40 $([char] 0x2713)." }
        ) {
            $lines = @((Ask $Problem) -split "`n")
            $lines[0] | Should -Be $First
            $lines | Should -Contain $Check
        }

        It 'says which equations cannot all be true' {
            Ask 'Marie a 2 ans de plus que Paul. Paul a 2 ans de plus que Marie. Quel âge a Marie ?' | Should -Be (@(
                    "Ce que vous m'avez dit se contredit : ces équations ne peuvent pas être vraies ensemble :"
                    '- Marie = Paul + 2'
                    '- Paul = Marie + 2'
                ) -join "`n")
        }

        It 'says what is missing, and never guesses it' {
            @((Ask 'Marie a 2 ans de plus que Paul. Quel âge a Marie ?') -split "`n")[0] | Should -Be "Je ne peux pas le trouver : il manque une information. Avec ce que vous m'avez dit, rien ne fixe Marie."
        }

        It 'says when a count is not a whole number' {
            @((Ask 'Paul a 2 fois plus de billes que Léa. Ensemble, ils ont 31 billes. Combien de billes a Léa ?') -split "`n")[-1] | Should -Be 'Attention : 31/3 n''est pas un nombre entier, l''énoncé est peut-être faux.'
        }
    }

    Context 'Places in a row' {

        It 'gives the order when only one keeps every condition' {
            Ask 'Alice, Bob et Chloé sont assis sur un banc. Chloé est tout à gauche. Bob est juste à droite de Chloé. Dans quel ordre sont-ils assis ?' | Should -Be (@(
                    'De gauche à droite : Chloé, Bob, Alice.'
                    'C''est le seul ordre possible (sur 6 essayés).'
                ) -join "`n")
        }

        It 'answers what is the same in every order kept, and says the orders when it is not' {
            Ask 'Alice, Bob et Chloé sont assis sur un banc. Alice n''est pas à côté de Bob. Qui est au milieu ?' | Should -Be (@('C''est Chloé.', 'C''est vrai dans chacun des 2 ordres possibles.') -join "`n")
            Ask 'dans quel ordre sont-ils assis ?' | Should -Be (@(
                    'Je ne peux pas le savoir : 2 ordres sont possibles :'
                    '- Alice, Chloé, Bob'
                    '- Bob, Chloé, Alice'
                    'Il faudrait une condition de plus.'
                ) -join "`n")
        }

        It 'gives a smallest set of conditions that cannot all hold' {
            Ask 'Alice est à gauche de Bob. Bob est à gauche de Chloé. Chloé est à gauche d''Alice. Qui est au milieu ?' | Should -Be (@(
                    'Aucun ordre ne convient : ces conditions se contredisent :'
                    '- Alice est à gauche de Bob.'
                    '- Bob est à gauche de Chloé.'
                    '- Chloé est à gauche d''Alice.'
                ) -join "`n")
        }

        It 'keeps the conditions told one by one, and says how many orders are left' {
            Ask 'Alice, Bob et Chloé sont assis sur un banc.' | Should -Be 'C''est noté. Avec ces conditions, 6 ordres sont possibles (sur 6).'
            Ask 'Bob n''est pas au milieu.' | Should -Be 'C''est noté. Avec ces conditions, 4 ordres sont possibles (sur 6).'
            Ask 'Alice est à gauche de Bob.' | Should -Be 'C''est noté. Avec ces conditions, 2 ordres sont possibles (sur 6).'
            @((Ask 'où est assis Bob ?') -split "`n")[0] | Should -Be 'Bob est en position 3 sur 3, en comptant de gauche à droite.'
        }

        It 'says what keeps its place in every order: <Text>' -ForEach @(
            @{ Text = 'Zoé, Yanis, Inès et Malik sont assis en ligne. Malik est tout à droite. Inès est juste à gauche de Malik. Zoé n''est pas à côté d''Inès. Qui est en premier ?'; First = 'C''est Zoé.' }
            @{ Text = 'Tom, Ana and Raj stand in a row. Ana is not next to Raj. Who is in the middle?'; First = 'It is Tom.' }
        ) {
            @((Ask $Text) -split "`n")[0] | Should -Be $First
        }

        It 'places in English' {
            Ask 'Anna, Ben and Carl sit in a row. Carl is in the middle. Ben is on the far left. In what order do they sit?' | Should -Be (@(
                    'From left to right: Ben, Carl, Anna.'
                    'It is the only possible order (out of 6 tried).'
                ) -join "`n")
        }
    }

    Context 'Equations' {

        It 'puts every root back in the equation: <Text>' -ForEach @(
            @{ Text = 'résous 3x + 5 = 20'; Line = "Vérification : 3 $([char] 0x00D7) 5 + 5 = 20 $([char] 0x2713)." }
            @{ Text = 'résous x^2 - 5x + 6 = 0'; Line = "Vérification : 2^2 - 5 $([char] 0x00D7) 2 + 6 = 0 $([char] 0x2713) ; 3^2 - 5 $([char] 0x00D7) 3 + 6 = 0 $([char] 0x2713)." }
            @{ Text = 'résous le système 2x + y = 5 et x - y = 1'; Line = "Vérification : 2 $([char] 0x00D7) 2 + 1 = 5 $([char] 0x2713) ; 2 - 1 = 1 $([char] 0x2713)." }
            @{ Text = 'trouve x tel que 4x - 7 = 9'; Line = "Vérification : 4 $([char] 0x00D7) 4 - 7 = 9 $([char] 0x2713)." }
            @{ Text = 'solve 3x + 5 = 20'; Line = "Check: 3 $([char] 0x00D7) 5 + 5 = 20 $([char] 0x2713)." }
        ) {
            @((Ask $Text) -split "`n")[-1] | Should -Be $Line
        }

        It 'gives one unknown by the others when one equation has two' {
            Ask 'résous x + y = 10' | Should -Be 'Une infinité de solutions : x = -y + 10 (y libre).'
        }
    }

    Context 'What is no problem' {

        It 'leaves to the rest of Lambek: <Text>' -ForEach @(
            @{ Text = 'Paris est à côté de Versailles'; Like = "C'est noté. Paris est à côté de Versailles.*" }
            @{ Text = 'ma soeur habite à côté de Lyon'; Like = "C'est noté. Votre soeur habite à côté de Lyon.*" }
            @{ Text = "j'ai 3 chats"; Like = "C'est noté. Vous avez 3 chats.*" }
            @{ Text = 'mon frère a deux livres'; Like = "C'est noté. Votre frère a deux livres.*" }
        ) {
            Ask $Text | Should -BeLike $Like
        }

        It 'never takes an order for a problem' {
            (New-LambekPlan 'supprime les fichiers de plus de 5 Go dans C:\Temp').Steps[0].Action | Should -Be 'files.delete'
            (New-LambekPlan 'liste les fichiers entre 2 et 5 Mo dans C:\Data').Steps[0].Action | Should -Be 'files.list'
        }
    }
}

Describe 'The solvers' {

    It 'solves linear equations exactly, and says which are fixed' {
        $one = [LambekRational]::One
        $minus = [LambekRational]::new(-1, 1)
        $equations = [LambekProblemEquation[]] @(
            [LambekProblemEquation]::Make([string[]] @('a', 'b'), [LambekRational[]] @($one, $minus), [LambekRational]::new(2, 1))
            [LambekProblemEquation]::Make([string[]] @('a', 'b'), [LambekRational[]] @($one, $one), [LambekRational]::new(30, 1))
        )
        $solution = [LambekProblems]::Solve($equations)
        $solution.Kind | Should -Be 'solved'
        $solution.Values['a'].Exact() | Should -Be '16'
        $solution.Values['b'].Exact() | Should -Be '14'
        $partial = [LambekProblems]::Solve([LambekProblemEquation[]] @($equations[0], [LambekProblemEquation]::Make([string[]] @('c'), [LambekRational[]] @($one), [LambekRational]::new(5, 1))))
        $partial.Kind | Should -Be 'partial'
        $partial.Values['c'].Exact() | Should -Be '5'
        @($partial.Free) | Should -Be @('a', 'b')
    }

    It 'tries every order, and finds a smallest set of conditions that cannot all hold' {
        $people = [string[]] @('A', 'B', 'C')
        ([LambekProblems]::Arrange($people, [LambekPlace[]] @(), 10)).Count | Should -Be 6
        $conditions = [LambekPlace[]] @(
            [LambekPlace]::Make('middle', 'A', $null, $null, 0, $false)
            [LambekPlace]::Make('at', 'B', $null, $null, 1, $false)
            [LambekPlace]::Make('next', 'C', 'B', $null, 0, $false)
        )
        $none = [LambekProblems]::Arrange($people, $conditions, 10)
        $none.Count | Should -Be 0
        @($none.Conflict) | Should -Be @(0, 2)
    }
}
