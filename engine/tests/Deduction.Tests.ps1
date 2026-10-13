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
    # Another conversation: nothing is kept in memory, the journal is read again from the disk
    function Start-Conversation { & (Get-Module Lambek) { $script:Told = $null; $script:ToldJournal = $null } }
}

Describe 'Reasoning on what was told' {

    BeforeEach {
        # Every test starts a conversation of its own, with an empty journal, on the same day
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
    }
    AfterAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
    }

    Context 'A thing told on a condition' {

        It 'keeps "<Text>" as a rule, said back with its condition' -ForEach @(
            @{ Text = "s'il pleut je prends le bus"; Said = "C'est noté. S'il pleut, vous prenez le bus. Je m'en souviendrai." }
            @{ Text = "s'il pleut, alors je prends le bus"; Said = "C'est noté. S'il pleut, vous prenez le bus. Je m'en souviendrai." }
            @{ Text = "je prends le bus s'il pleut"; Said = "C'est noté. S'il pleut, vous prenez le bus. Je m'en souviendrai." }
            @{ Text = 'quand il pleut, je prends le bus'; Said = "C'est noté. S'il pleut, vous prenez le bus. Je m'en souviendrai." }
            @{ Text = 'if it rains, I take the bus'; Said = 'Noted. If it rains, you take the bus. I will remember it.' }
            @{ Text = 'I take the bus when it rains'; Said = 'Noted. If it rains, you take the bus. I will remember it.' }
        ) {
            Ask $Text | Should -Be $Said
        }

        It 'never tells what holds on a condition as if it always held' {
            Tell "s'il pleut je prends le bus"
            $plan = New-LambekPlan 'qu''est-ce que je fais ?'
            $answer = $plan | ConvertTo-LambekAnswer
            $answer | Should -Not -BeLike "J'en déduis*"
            $answer | Should -Be "Je ne sais pas. Vous m'avez dit : S'il pleut, vous prenez le bus. Mais je ne sais pas s'il pleut."
        }

        It 'deduces what holds when the condition is told, and says what it deduced it with' {
            Tell "s'il pleut je prends le bus", 'il pleut'
            Ask 'qu''est-ce que je fais ?' | Should -Be (@(
                    "J'en déduis :"
                    '- Vous prenez le bus.'
                    "  déduit avec : S'il pleut, vous prenez le bus."
                    '  déduit avec : Il pleut.'
                ) -join "`n")
        }

        It 'deduces it whichever comes first, the rule or the thing told' {
            Tell 'il pleut', "s'il pleut je prends le bus"
            Ask 'est-ce que je prends le bus ?' | Should -BeLike "J'en déduis :*Vous prenez le bus.*"
        }

        It 'deduces in English' {
            Tell 'if it rains, I take the bus', 'it rains'
            Ask 'what do I do?' | Should -Be (@(
                    'From that, I deduce:'
                    '- You take the bus.'
                    '  deduced with: If it rains, you take the bus.'
                    '  deduced with: It rains.'
                ) -join "`n")
        }

        It 'follows a chain of rules to the end' {
            Tell "s'il pleut, je fais un gâteau", 'si je fais un gâteau, ma soeur mange le gâteau', 'il pleut'
            Ask 'qu''est-ce que ma soeur mange ?' | Should -Be (@(
                    "J'en déduis :"
                    '- Votre soeur mange le gâteau.'
                    "  déduit avec : S'il pleut, vous faites un gâteau."
                    '  déduit avec : Si vous faites un gâteau, votre soeur mange le gâteau.'
                    '  déduit avec : Il pleut.'
                ) -join "`n")
        }

        It 'asks about every word of a question that asks whether' {
            Tell "s'il pleut, je fais un gâteau", 'si je fais un gâteau, mon frère est content', 'il pleut'
            Ask 'est-ce que mon frère est content ?' | Should -BeLike "J'en déduis :*- Votre frère est content.*"
            Tell 'ma soeur est malade'
            Ask 'est-ce que ma soeur est heureuse ?' | Should -BeLike 'Je ne sais pas*'
        }

        It 'reads a condition in the negative, and deduces only from the same sign' {
            Tell "s'il ne pleut pas, je prends le vélo", 'il pleut'
            Ask 'qu''est-ce que je fais ?' | Should -Not -BeLike '*vélo.*déduit*'
            Tell 'il ne pleut pas'
            Ask 'qu''est-ce que je fais ?' | Should -BeLike "J'en déduis :*- Vous prenez le vélo.*S'il ne pleut pas, vous prenez le vélo.*Il ne pleut pas.*"
        }

        It 'deduces from a rule told in another conversation' {
            Tell "s'il pleut je prends le bus"
            Start-Conversation
            Tell 'il pleut'
            Ask 'qu''est-ce que je fais ?' | Should -BeLike "J'en déduis :*- Vous prenez le bus.*"
        }

        It 'lists the rules among what was told, never what it deduced' {
            Tell "s'il pleut je prends le bus", 'il pleut'
            Ask 'qu''est-ce que je t''ai dit ?' | Should -Be (@(
                    "D'après ce qui m'a été dit dans cette conversation :"
                    "- S'il pleut, tu prends le bus."
                    '- Il pleut.'
                ) -join "`n")
        }

        It 'puts what it deduced on the blackboard, with what it rests on' {
            Tell "s'il pleut je prends le bus", 'il pleut'
            Ask 'qu''est-ce que je fais ?' | Out-Null
            $deduced = @(& (Get-Module Lambek) { (Get-LambekBoard).Entries() } | Where-Object { $_.Status -eq 'deduced' })
            $deduced.Count | Should -Be 1
            $deduced[0].Source | Should -Be 'logic'
            @($deduced[0].Basis).Count | Should -Be 2
        }

        It 'takes "do" for what is done, never for what one is or has' {
            Tell "j'ai 3 chats", "s'il pleut je prends le bus", 'il pleut'
            Ask 'qu''est-ce que je fais ?' | Should -Not -BeLike '*chats*'
        }

        It 'reads a verb alone, and a condition in the negative with it' {
            Tell 'si je ne travaille pas, je lis un livre', 'je ne travaille pas'
            Ask 'qu''est-ce que je lis ?' | Should -Be (@(
                    "J'en déduis :"
                    '- Vous lisez un livre.'
                    '  déduit avec : Si vous ne travaillez pas, vous lisez un livre.'
                    '  déduit avec : Vous ne travaillez pas.'
                ) -join "`n")
        }

        It 'says back the one who speaks when a verb is about them: <Told>' -ForEach @(
            @{ Told = 'if my boss calls me, I answer the phone'; Said = 'Noted. If your boss calls you, you answer the phone. I will remember it.' }
            @{ Told = "si mon patron m'appelle, je réponds au téléphone"; Said = "C'est noté. Si votre patron vous appelle, vous répondez au téléphone. Je m'en souviendrai." }
        ) {
            Ask $Told | Should -Be $Said
        }

        It 'reads the word that asks at the end: <Text>' -ForEach @(
            @{ Told = @("s'il pleut je prends le bus", 'il pleut'); Text = 'je fais quoi ?'; Like = "J'en déduis :*- Vous prenez le bus.*" }
            @{ Told = @('ma soeur habite à Lyon'); Text = 'ma soeur habite où ?'; Like = '*- Votre soeur habite à Lyon.' }
        ) {
            Tell $Told
            Ask $Text | Should -BeLike $Like
        }

        It 'asks whether even with the verb of an order: does the school close?' {
            Tell 'if it snows, the school closes', 'it snows'
            Ask 'does the school close?' | Should -BeLike 'From that, I deduce:*- The school closes.*'
        }

        It 'says a rule told in another language in that language' {
            Tell 'if I finish the report, I watch a movie', 'I finish the report'
            Ask 'qu''est-ce que je fais ?' | Should -Not -BeLike '*Si you*'
        }

        It 'never plans an order given on a condition' {
            (New-LambekPlan 'si il pleut, supprime les fichiers .log dans C:\Temp').Status | Should -Not -Be 'Ready'
        }
    }

    Context 'Numbers told, worked out' {

        It 'adds up what everyone has: "<Ask>"' -ForEach @(
            @{ Ask = 'combien de chats avons-nous en tout ?' }
            @{ Ask = 'combien de chats avons-nous ?' }
        ) {
            Tell "j'ai 3 chats", 'ma soeur a deux chats'
            Ask $Ask | Should -Be (@(
                    '5 chats en tout.'
                    '- Vous avez 3 chats.'
                    '- Votre soeur a deux chats.'
                    '3 + 2 = 5'
                ) -join "`n")
        }

        It 'says the number of one, the last one told' {
            Tell "j'ai 3 chats", 'ma soeur a 2 chats', "j'ai 4 chats"
            Ask 'combien de chats j''ai ?' | Should -Be (@('4 chats.', '- Vous avez 4 chats.') -join "`n")
            Ask 'combien de chats a ma soeur ?' | Should -Be (@('2 chats.', '- Votre soeur a 2 chats.') -join "`n")
        }

        It 'compares: <Ask>' -ForEach @(
            @{ Ask = 'combien de chats mon frère a de plus que ma soeur ?'; First = '2 chats de plus.'; Calculation = '4 - 2 = 2' }
            @{ Ask = 'combien de chats ma soeur a de moins que mon frère ?'; First = '2 chats de moins.'; Calculation = '4 - 2 = 2' }
        ) {
            Tell 'ma soeur a 2 chats', 'mon frère a 4 chats'
            $lines = @((Ask $Ask) -split "`n")
            $lines[0] | Should -Be $First
            $lines[-1] | Should -Be $Calculation
        }

        It 'counts in English, one and many' {
            Tell 'I have 3 cats', 'my sister has 5 cats'
            @((Ask 'how many cats do we have?') -split "`n")[0] | Should -Be '8 cats in total.'
            @((Ask 'how many more cats does my sister have than me?') -split "`n")[0] | Should -Be '2 more cats.'
            Tell 'my brother has 4 cats'
            @((Ask 'how many more cats does my brother have than my sister?') -split "`n")[0] | Should -Be '1 fewer cat.'
        }

        It 'reads "en" as the thing counted just before, and says it back so' {
            Tell "j'ai 3 chats"
            Ask 'ma soeur en a 2' | Should -Be "C'est noté. Votre soeur a 2 chats. Je m'en souviendrai."
            Ask "mon frère en a deux" | Should -Be "C'est noté. Votre frère a deux chats. Je m'en souviendrai."
            Ask "j'en ai 4" | Should -Be "C'est noté. Vous avez 4 chats. Je m'en souviendrai."
            @((Ask 'combien de chats avons-nous ?') -split "`n")[-1] | Should -Be '4 + 2 + 2 = 8'
        }

        It 'leaves "en" alone when nothing was counted before, or when it is no "en" of a number: <Text>' -ForEach @(
            @{ Text = 'je vais en France'; Said = "C'est noté. Vous allez en France. Je m'en souviendrai." }
        ) {
            Ask $Text | Should -Be $Said
            InModuleScope Lambek { ConvertTo-LambekPlainSentence -Text 'ma soeur en a 2' } | Should -Be 'ma soeur en a 2'
        }

        It 'reads the verb before the one who has: combien de chiens a ma voisine ?' {
            Tell 'ma voisine a trois chiens'
            Ask 'combien de chiens a ma voisine ?' | Should -Be (@('3 chiens.', '- Votre voisine a trois chiens.') -join "`n")
        }

        It 'counts "une voiture" as one' {
            Tell 'mon père a 2 voitures', 'ma mère a une voiture'
            @((Ask 'combien de voitures avons-nous ?') -split "`n")[-1] | Should -Be '2 + 1 = 3'
        }

        It 'keeps a word in small letters as it was written: <Text>' -ForEach @(
            @{ Text = "j'ai 10 euros"; Said = "C'est noté. Vous avez 10 euros. Je m'en souviendrai." }
        ) {
            Ask $Text | Should -Be $Said
        }

        It 'says it does not know a number nobody told' {
            Tell "j'ai 3 chats"
            Ask 'combien de chiens j''ai ?' | Should -BeLike 'Je ne sais pas*'
        }

        It 'never takes a calculation for a question about what was told' {
            Ask 'combien font 3/7 + 2/5 ?' | Should -BeLike '*29/35*'
        }
    }

    Context 'Why' {

        It 'says what a number it worked out rests on' {
            Tell "j'ai 3 chats", 'ma soeur a 2 chats'
            Ask 'combien de chats avons-nous ?' | Out-Null
            Ask 'pourquoi ?' | Should -Be (@(
                    "Parce que vous m'avez dit :"
                    '- Vous avez 3 chats.'
                    '- Votre soeur a 2 chats.'
                    'Et le calcul : 3 + 2 = 5.'
                ) -join "`n")
        }

        It 'says what a thing it deduced rests on' {
            Tell "s'il pleut je prends le bus", 'il pleut'
            Ask 'qu''est-ce que je fais ?' | Out-Null
            Ask 'pourquoi ?' | Should -Be (@(
                    "Parce que vous m'avez dit :"
                    "- S'il pleut, vous prenez le bus."
                    '- Il pleut.'
                ) -join "`n")
        }

        It 'quotes once what it cannot say back, in a list that already says it was told' {
            Tell 'si mon frère vient avec Zorglub, je fais un gâteau', 'mon frère vient avec Zorglub'
            Ask 'est-ce que je fais un gâteau ?' | Out-Null
            Ask 'pourquoi ?' | Should -Not -BeLike "*- Vous m'avez dit*"
        }

        It 'answers "why do I..." with what it was deduced with' {
            Tell 'I take the bus when it rains', 'it rains'
            Ask 'why do I take the bus?' | Should -BeLike '*You take the bus.*deduced with: If it rains, you take the bus.*deduced with: It rains.*'
        }

        It 'leaves "pourquoi ?" to what it is about when no answer from what was told came just before' {
            Tell 'il pleut'
            Ask 'pourquoi ?' | Should -Not -BeLike 'Parce que*'
            Tell "j'ai 3 chats"
            Ask 'combien de chats j''ai ?' | Out-Null
            New-LambekPlan 'supprime les fichiers .log dans C:\Temp' | Out-Null
            Ask 'pourquoi ?' | Should -Not -BeLike 'Parce que*'
        }

        It 'keeps the proof of each chat apart' {
            Tell "j'ai 3 chats"
            Ask 'combien de chats j''ai ?' | Out-Null
            & (Get-Module Lambek) { $script:Told = [System.Collections.Generic.List[object]]::new() }
            Ask 'pourquoi ?' | Should -Not -BeLike 'Parce que*'
        }
    }
}

Describe 'Reasoning on things never seen in the tests above' {

    BeforeEach {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
    }
    AfterAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
    }

    # Other things, other words, other numbers: what works only on the sentences of the tests is not reasoning
    It 'deduces: <Question>' -ForEach @(
        @{ Told = @("s'il fait beau, je vais à la plage", 'il fait beau'); Question = 'où est-ce que je vais ?'; Line = '- Vous allez à la plage.' }
        @{ Told = @('si je suis fatigué, je dors', 'je suis fatigué'); Question = 'est-ce que je dors ?'; Line = '- Vous dormez.' }
        @{ Told = @('si je travaille à Lyon, je prends le train', 'je travaille à Lyon'); Question = 'est-ce que je prends le train ?'; Line = '- Vous prenez le train.' }
        @{ Told = @('si je gagne au loto, j''achète une maison', 'si j''achète une maison, je déménage', 'je gagne au loto'); Question = 'est-ce que je déménage ?'; Line = '- Vous déménagez.' }
        @{ Told = @('if I finish the report, I watch a movie', 'I finish the report'); Question = 'what do I watch?'; Line = '- You watch a movie.' }
    ) {
        Tell $Told
        @((Ask $Question) -split "`n") | Should -Contain $Line
    }

    It 'works out: <Question>' -ForEach @(
        @{ Told = @("j'ai 10 euros", 'mon frère a 7 euros'); Question = 'combien d''euros j''ai de plus que mon frère ?'; First = '3 euros de plus.'; Last = '10 - 7 = 3' }
        @{ Told = @('mon oncle a 6 poules', 'ma tante a 9 poules'); Question = 'combien de poules mon oncle a de moins que ma tante ?'; First = '3 poules de moins.'; Last = '9 - 6 = 3' }
        @{ Told = @('I have 12 apples', 'my friend has 5 apples'); Question = 'how many apples do we have in total?'; First = '17 apples in total.'; Last = '12 + 5 = 17' }
    ) {
        Tell $Told
        $lines = @((Ask $Question) -split "`n")
        $lines[0] | Should -Be $First
        $lines[-1] | Should -Be $Last
    }
}

Describe 'The language of a chat' {

    It 'keeps the language of the chat when the words fit it as well as another one' {
        & (Get-Module Lambek) {
            $script:LanguageHint = 'fr'
            try { Get-LambekLanguage -Tokens @('ma', 'tante', 'a', 'poules') | Should -Be 'fr' }
            finally { $script:LanguageHint = $null }
        }
    }
}

Describe 'Speaking of numbers' {

    It 'leaves the word that compares as it is: <Text>' -ForEach @(
        @{ Text = '2 more cats.'; Said = '2 more cats.' }
        @{ Text = '3 fewer files.'; Said = '3 fewer files.' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) ConvertTo-LambekSpoken -Text $Text -Language 'en' -Register 'vous' } | Should -Be $Said
    }
}
