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
    function Hear {
        param([string] $Text, [string] $Language = 'fr')
        & (Get-Module Lambek) { param($t, $l) Read-LambekSpeech -Text $t -Language $l } $Text $Language
    }
}

Describe 'Answers said in a sentence of their own' {

    BeforeEach {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:SpeechFrames = $null; $script:Now = [datetime] '2026-10-06 10:00' }
    }
    AfterAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:SpeechFrames = $null; $script:Now = $null }
    }

    It 'says the answer first, then why, in one sentence' {
        Tell 'tous les hommes sont mortels', 'Socrate est un homme'
        Ask 'Socrate est-il mortel ?' | Should -Be "Oui, Socrate est mortel : c'est un homme et tous les hommes sont mortels."
    }

    It 'says the reasons in the order of the reasoning' {
        Tell 'tous les félins sont des animaux', 'Minou est un chat', 'tous les chats sont des félins'
        Ask 'Minou est-il un animal ?' | Should -Be "Oui, Minou est un animal : c'est un chat, tous les chats sont des félins et tous les félins sont des animaux."
    }

    It 'says no the same way' {
        Tell 'aucun chien n''est un chat', 'Rex est un chien'
        Ask 'Rex est-il un chat ?' | Should -Be "Non, Rex n'est pas un chat : c'est un chien et aucun chien n'est un chat."
    }

    It 'speaks of the user as the user' {
        Tell 'tous les hommes sont mortels', 'je suis un homme'
        Ask 'suis-je mortel ?' | Should -Be "Oui, vous êtes mortel, car vous êtes un homme et tous les hommes sont mortels."
    }

    It 'says of a rule about every one in the same way' {
        Tell 'tous les chats sont des félins', 'tous les félins sont des animaux'
        Ask 'tous les chats sont-ils des animaux ?' | Should -Be 'Oui, tous les chats sont des animaux, car tous les chats sont des félins et tous les félins sont des animaux.'
    }

    It 'says what is supposed as supposed, and that it may be an exception' {
        Tell 'normalement, les oiseaux volent', 'Tweety est un oiseau'
        Ask 'Tweety vole-t-il ?' | Should -Be (@(
                "Normalement oui, Tweety vole : c'est un oiseau et normalement, les oiseaux volent."
                'Si Tweety est une exception, dites-le-moi.'
            ) -join "`n")
    }

    It 'does not say it the same way twice in a row' {
        Tell 'tous les hommes sont mortels', 'Socrate est un homme', 'Platon est un homme'
        Ask 'Socrate est-il mortel ?' | Should -Be "Oui, Socrate est mortel : c'est un homme et tous les hommes sont mortels."
        Ask 'Platon est-il mortel ?' | Should -Be "Oui, Platon est mortel, car c'est un homme et tous les hommes sont mortels."
    }

    It 'still says why with each thing told' {
        Tell 'tous les hommes sont mortels', 'Socrate est un homme'
        Ask 'Socrate est-il mortel ?' | Out-Null
        Ask 'pourquoi ?' | Should -Be (@("Parce que vous m'avez dit :", '- Tous les hommes sont mortels.', '- Socrate est un homme.') -join "`n")
    }

    It 'says it in lines, as before, when the reasons are too many for one sentence' {
        Tell 'tous les chats sont des félins', 'tous les félins sont des mammifères', 'tous les mammifères sont des animaux', 'Minou est un chat'
        @((Ask 'Minou est-il un animal ?') -split "`n")[0..1] | Should -Be @('Oui : Minou est un animal.', "Parce que vous m'avez dit :")
    }

    It 'says a question told after an open question only when it settles it' {
        Tell 'toutes les étudiantes sont curieuses'
        @((Ask 'Marie est-elle curieuse ?') -split "`n")[0] | Should -BeLike 'Je ne peux pas le conclure*'
        Ask 'normalement, les oiseaux volent' | Should -Be "C'est noté. Normalement, les oiseaux volent. Je m'en souviendrai."
        Ask 'Marie est une étudiante' | Should -Be (@(
                "C'est noté. Marie est une étudiante. Je m'en souviendrai."
                "Oui, Marie est curieuse : c'est une étudiante et toutes les étudiantes sont curieuses."
            ) -join "`n")
    }

    It 'speaks English the same way' {
        Tell 'all men are mortal', 'Socrates is a man'
        Ask 'is Socrates mortal?' | Should -Be 'Yes, Socrates is mortal, because Socrates is a man and all men are mortal.'
        Tell 'I am a man'
        Ask 'am I mortal?' | Should -Be 'Yes, you are mortal, because you are a man and all men are mortal.'
    }

    It 'asks the user in English with the right verb' {
        Tell 'all birds fly'
        @((Ask 'do I fly?') -split "`n")[1] | Should -Be 'One question would settle it: are you a bird?'
    }
}

Describe 'The second Lambek, who has only the text' {

    It 'reads back the answer, the conclusion and the reasons, and finds the conclusion follows' {
        $heard = Hear "Oui, Socrate est mortel : c'est un homme et tous les hommes sont mortels."
        $heard.Verdict | Should -Be 'yes'
        $heard.Conclusion | Should -Be 'is|name:socrate|mortel'
        $heard.Reasons | Should -Be "all|homme|mortel`nis|name:socrate|homme"
        $heard.Clauses | Should -Be @('Socrate est mortel', 'Socrate est un homme', 'tous les hommes sont mortels')
        $heard.Follows | Should -BeTrue
    }

    It 'reads the conclusion after donc, and puisqu''il' {
        (Hear "Oui : Socrate est un homme et tous les hommes sont mortels, donc il est mortel.").Clauses | Should -Be @('Socrate est un homme', 'tous les hommes sont mortels', 'Socrate est mortel')
        (Hear "Oui, Socrate est mortel, puisqu'il est un homme et que tous les hommes sont mortels.").Follows | Should -BeTrue
    }

    It 'finds a conclusion that does not follow from its reasons' {
        (Hear "Oui, Socrate est mortel : c'est un homme.").Follows | Should -BeFalse
        (Hear "Oui, Socrate est mortel : c'est un homme et tous les hommes sont grands.").Follows | Should -BeFalse
    }

    It 'does not read c''est or il when no one was named before' {
        Hear "Oui : c'est un homme et tous les hommes sont mortels, donc Socrate est mortel." | Should -BeNullOrEmpty
    }

    It 'does not read c''est or il when two were named before' {
        Hear "Oui, Socrate est mortel : Platon est un homme, c'est un homme et tous les hommes sont mortels." | Should -BeNullOrEmpty
    }

    It 'does not read il for one said to be a woman' {
        Hear "Oui, Marie est curieuse : Marie est une étudiante, il est jeune et toutes les étudiantes sont curieuses." | Should -BeNullOrEmpty
    }

    It 'reads nothing without the answer word, or with words it cannot read' {
        Hear "Socrate est mortel : c'est un homme et tous les hommes sont mortels." | Should -BeNullOrEmpty
        Hear "Oui, Socrate est mortel : c'est un homme et tous les hommes sont mortels depuis 2000." | Should -BeNullOrEmpty
    }

    It 'reads English' {
        $heard = Hear 'Yes, Socrates is mortal, because Socrates is a man and all men are mortal.' -Language en
        $heard.Conclusion | Should -Be 'is|name:socrates|mortal'
        $heard.Follows | Should -BeTrue
    }
}

Describe 'How the language sounds' {

    It 'reads a sentence as its shape: the small words as they are, the others as their kind' {
        & (Get-Module Lambek) {
            $model = Get-LambekFluency -Language 'fr'
            $model.Shape("Oui, Socrate est mortel : c'est un homme.", (Get-LambekDictionary -Language 'fr')) -join ' '
        } | Should -Be "oui , <Name> est <an> : c' est un homme ."
    }

    It 'finds a sentence of the language likelier, word by word, than its words in disorder' {
        $scores = & (Get-Module Lambek) {
            $model = Get-LambekFluency -Language 'fr'
            $dictionary = Get-LambekDictionary -Language 'fr'
            foreach ($text in "Oui, Socrate est mortel : c'est un homme.", "Mortel un oui est homme, c'est Socrate.") {
                $score = $model.Score($text, $dictionary)
                $score[0] / $score[1]
            }
        }
        $scores[0] | Should -BeGreaterThan $scores[1]
    }

    It 'was learned from free corpora, and says what from' {
        $sources = Get-Content -LiteralPath "$PSScriptRoot/../Lambek/Data/Speech/SOURCES.md" -Raw
        $sources | Should -Match 'Common Voice'
        $sources | Should -Match 'CC0'
        $sources | Should -Match 'Europarl'
    }
}

Describe 'The satellites' {

    It 'choose, for answers left out of the fit, a way a careful writer accepts' {
        $fit = Optimize-LambekSpeech -Path "$PSScriptRoot/../../bench/speech.json" -Language 'fr'
        $fit.Cases | Should -Be 16
        [int] ($fit.LeftOut -split ' / ')[0] | Should -BeGreaterOrEqual 15
    }
}

Describe 'Every syllogism, said in a sentence' {

    BeforeAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:SpeechFrames = $null }
    }
    AfterAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:SpeechFrames = $null }
    }

    # Of the 256 syllogisms (64 pairs of premises, 4 conclusions asked), those Lambek answers yes or no: the sentence it
    # says is read by the second Lambek, and what it read is checked by another judge, the models: the reasons read must
    # be sentences told, and the conclusion read must be true in every model where they are
    It 'says every answer it gives in a sentence whose reasons, read alone, prove what it says' {
        $terms = @{ S = @('étudiant', 'étudiants'); M = @('musicien', 'musiciens'); P = @('artiste', 'artistes') }
        $sentence = {
            param([string] $form, [string] $a, [string] $b)
            $x = $terms[$a]; $y = $terms[$b]
            switch ($form) {
                'A' { "tous les $($x[1]) sont des $($y[1])" }
                'E' { "aucun $($x[0]) n'est un $($y[0])" }
                'I' { "certains $($x[1]) sont des $($y[1])" }
                'O' { "certains $($x[1]) ne sont pas des $($y[1])" }
            }
        }
        # What each sentence says, from its words back
        $read = @{}
        foreach ($form in 'A', 'E', 'I', 'O') { foreach ($a in 'S', 'M', 'P') { foreach ($b in 'S', 'M', 'P') { if ($a -ne $b) { $read[(& $sentence $form $a $b)] = @($form, $a, $b) } } } }
        $index = @{ S = 1; M = 2; P = 4 }
        $holds = {
            param($said, [int] $model)
            $form, $a, $b = $said
            $found = @{ AB = $false; AnotB = $false }
            foreach ($kind in 0..7) {
                if (-not ($model -band (1 -shl $kind))) { continue }
                $inA = [bool] ($kind -band $index[$a]); $inB = [bool] ($kind -band $index[$b])
                if ($inA -and $inB) { $found.AB = $true }
                if ($inA -and -not $inB) { $found.AnotB = $true }
            }
            switch ($form) { 'A' { -not $found.AnotB } 'E' { -not $found.AB } 'I' { $found.AB } 'O' { $found.AnotB } }
        }
        $figures = @(, @(@('M', 'P'), @('S', 'M'))) + @(, @(@('P', 'M'), @('S', 'M'))) + @(, @(@('M', 'P'), @('M', 'S'))) + @(, @(@('P', 'M'), @('M', 'S')))
        $wrong = [System.Collections.Generic.List[string]]::new()
        $said = 0
        $lines = 0
        foreach ($figure in $figures) {
            foreach ($major in 'A', 'E', 'I', 'O') {
                foreach ($minor in 'A', 'E', 'I', 'O') {
                    $told = @((& $sentence $major $figure[0][0] $figure[0][1]), (& $sentence $minor $figure[1][0] $figure[1][1]))
                    foreach ($conclusion in 'A', 'E', 'I', 'O') {
                        $question = & $sentence $conclusion 'S' 'P'
                        $question = $(if ($conclusion -eq 'E') { "est-ce qu'$question ?" } else { "est-ce que $question ?" })
                        $reply = & (Get-Module Lambek) {
                            param($m)
                            Clear-LambekTold
                            $script:Told = $null
                            (Resolve-LambekCategory -Text $m).Reply
                        } "$($told[0]). $($told[1]). $question"
                        $first = @("$reply" -split "`n")[0]
                        if ($first -notlike 'Oui*' -and $first -notlike 'Non*') { continue }
                        # (in lines, as before: the answer, then "Parce que vous m'avez dit :")
                        if ("$reply".Contains("`n")) { $lines++; continue }
                        $said++
                        $heard = Hear $first
                        if (-not $heard -or -not $heard.Follows) { $wrong.Add("${first}: not read back"); continue }
                        $reasons = @($heard.Because)
                        $claimed = $heard.Said
                        if (@($reasons | Where-Object { $_ -notin $told }).Count -gt 0 -or -not $read.ContainsKey($claimed)) { $wrong.Add("${first}: not what was told"); continue }
                        for ($model = 1; $model -lt 256; $model++) {
                            if (@($reasons | Where-Object { -not (& $holds $read[$_] $model) }).Count -gt 0) { continue }
                            if (-not (& $holds $read[$claimed] $model)) { $wrong.Add("${first}: false in model $model"); break }
                        }
                    }
                }
            }
        }
        $wrong | Should -BeNullOrEmpty
        # Every answer said in a sentence but the 8 whose answer has no sentence of its own ("Non.", "Non, il n'y en a pas."),
        # said in lines as before
        $said | Should -Be 22
        $lines | Should -Be 8
    }
}
