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

Describe 'General rules told in words' {

    BeforeEach {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
    }
    AfterAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
    }

    Context 'Tous, aucun, certains' {

        It 'keeps a rule about every one as told, and says it back from the other side' {
            Ask 'tous les chats de ma soeur sont noirs' | Should -Be "C'est noté. Tous les chats de votre soeur sont noirs. Je m'en souviendrai."
        }

        It 'concludes from a rule about every one, and says what it rests on' {
            Tell 'tous les chats de ma soeur sont noirs', 'Minou est un chat de ma soeur'
            $expected = @(
                'Oui : Minou est noir.'
                "Parce que vous m'avez dit :"
                '- Tous les chats de votre soeur sont noirs.'
                '- Minou est un chat de votre soeur.'
            ) -join "`n"
            Ask 'est-ce que Minou est noir ?' | Should -Be $expected
            Ask 'Minou est-il noir ?' | Should -Be $expected
        }

        It 'answers pourquoi with the same' {
            Tell 'tous les chats de ma soeur sont noirs', 'Minou est un chat de ma soeur', 'Minou est-elle noire ?'
            Ask 'pourquoi ?' | Should -Be (@(
                    "Parce que vous m'avez dit :"
                    '- Tous les chats de votre soeur sont noirs.'
                    '- Minou est un chat de votre soeur.'
                ) -join "`n")
        }

        It 'concludes no from aucun' {
            Tell "aucun chien n'est un chat", 'Rex est un chien'
            Ask 'Rex est-il un chat ?' | Should -Be (@(
                    "Non : Rex n'est pas un chat."
                    "Parce que vous m'avez dit :"
                    "- Aucun chien n'est un chat."
                    '- Rex est un chien.'
                ) -join "`n")
        }

        It 'says that certains does not say which ones, and never guesses' {
            Tell 'certains chats sont gris', 'Tom est un chat'
            Ask 'Tom est-il gris ?' | Should -Be (@(
                    "Je ne peux pas le conclure avec ce que vous m'avez dit : « Tom est gris » peut être vrai ou faux."
                    '« Certains chats sont gris » ne dit pas lesquels.'
                ) -join "`n")
        }

        It 'solves a whole syllogism told in one message' {
            Ask 'Tous les hommes sont mortels. Socrate est un homme. Donc Socrate est-il mortel ?' | Should -Be (@(
                    'Oui : Socrate est mortel.'
                    "Parce que vous m'avez dit :"
                    '- Tous les hommes sont mortels.'
                    '- Socrate est un homme.'
                ) -join "`n")
        }

        It 'follows rules about every one, one after the other' {
            Tell 'tous les chats sont des mammifères', 'tous les mammifères sont des animaux'
            @((Ask 'est-ce que tous les chats sont des animaux ?') -split "`n")[0] | Should -Be 'Oui : tous les chats sont des animaux.'
            @((Ask 'est-ce que certains chats ne sont pas des animaux ?') -split "`n")[0] | Should -Be 'Non : tous les chats sont des animaux.'
            @((Ask 'tous les animaux sont-ils des chats ?') -split "`n")[0] | Should -BeLike 'Je ne peux pas le conclure*'
        }

        It 'never takes for granted that there are any' {
            Tell 'tous les chats sont des mammifères'
            Ask 'certains chats sont-ils des mammifères ?' | Should -Be (@(
                    "Je ne peux pas le conclure avec ce que vous m'avez dit : « certains chats sont des mammifères » peut être vrai ou faux."
                    "Et rien ne dit qu'il existe des chats."
                ) -join "`n")
        }

        It 'answers about the user, and who' {
            Tell 'tous les hommes sont mortels', 'Socrate est un homme', 'je suis un homme'
            @((Ask 'suis-je mortel ?') -split "`n")[0] | Should -Be 'Oui : vous êtes mortel.'
            @((Ask 'qui est mortel ?') -split "`n")[0] | Should -Be 'Socrate et vous.'
        }

        It 'reasons with verbs, and with what they are done to: <Question>' -ForEach @(
            @{ Told = 'tous les oiseaux volent', 'Tweety est un oiseau'; Question = 'est-ce que Tweety vole ?'; First = 'Oui : Tweety vole.' }
            @{ Told = 'tous les oiseaux volent', 'Tweety est un oiseau'; Question = 'Tweety vole-t-il ?'; First = 'Oui : Tweety vole.' }
            @{ Told = 'aucun poisson ne vole', 'Nemo est un poisson'; Question = 'est-ce que Nemo vole ?'; First = 'Non : Nemo ne vole pas.' }
            @{ Told = 'tous les chats aiment le lait', 'Minou est un chat'; Question = 'Minou aime-t-il le lait ?'; First = 'Oui : Minou aime le lait.' }
            @{ Told = "aucun chien n'aime le chocolat", 'Rex est un chien'; Question = 'est-ce que Rex aime le chocolat ?'; First = "Non : Rex n'aime pas le chocolat." }
            @{ Told = 'tous les chats aiment le lait', 'Minou est un chat'; Question = 'qui aime le lait ?'; First = 'Minou aime le lait.' }
            @{ Told = 'tous les chats sont noirs', 'je ne suis pas noir'; Question = 'suis-je un chat ?'; First = "Non : vous n'êtes pas un chat." }
            @{ Told = 'All cats like milk.', 'Tom is a cat.'; Question = 'Does Tom like milk?'; First = 'Yes: Tom does like milk.' }
            @{ Told = 'No dog likes chocolate.', 'Rex is a dog.'; Question = 'Does Rex like chocolate?'; First = 'No: Rex does not like chocolate.' }
            @{ Told = 'All cats like milk.', 'Tom is a cat.'; Question = 'Who likes milk?'; First = 'Tom likes milk.' }
            @{ Told = 'All cats of my sister are black.', 'Tom is a cat of my sister.'; Question = 'Is Tom black?'; First = 'Yes: Tom is black.' }
        ) {
            Tell $Told
            @((Ask $Question) -split "`n")[0] | Should -Be $First
        }

        It 'lists what was told among the rest of what was told' {
            Tell "aucun chien n'est un chat", 'Rex est un chien'
            Ask "qu'est-ce que je t'ai dit ?" | Should -Be (@(
                    "D'après ce qui m'a été dit dans cette conversation :"
                    "- Aucun chien n'est un chat."
                    '- Rex est un chien.'
                ) -join "`n")
        }
    }

    Context 'Contradictions' {

        It 'says at once when what is told cannot be true with what was told, and keeps both' {
            Tell "aucun chat n'est noir", 'Minou est un chat'
            Ask 'Minou est noir' | Should -Be (@(
                    "C'est noté. Minou est noir. Je m'en souviendrai."
                    "Attention : avec ce que vous m'avez dit, ces phrases ne peuvent pas être vraies ensemble :"
                    "- Aucun chat n'est noir."
                    '- Minou est un chat.'
                    '- Minou est noir.'
                ) -join "`n")
            @((Ask 'est-ce que Minou est noir ?') -split "`n")[0] | Should -Be "Ce que vous m'avez dit se contredit : ces phrases ne peuvent pas être vraies ensemble :"
        }

        It 'gives a smallest set of sentences that cannot all be true' {
            Tell 'tous les chats sont noirs', 'Rex est un chien', "aucun chat n'est noir"
            Ask 'Tom est un chat' | Should -Be (@(
                    "C'est noté. Tom est un chat. Je m'en souviendrai."
                    "Attention : avec ce que vous m'avez dit, ces phrases ne peuvent pas être vraies ensemble :"
                    '- Tous les chats sont noirs.'
                    "- Aucun chat n'est noir."
                    '- Tom est un chat.'
                ) -join "`n")
        }
    }

    Context 'What is left to the rest of Lambek' {

        It 'leaves a question about something told to the memory when nothing general was told' {
            Tell 'Minou est noir'
            Ask 'est-ce que Minou est noir ?' | Should -BeLike "D'après ce qui m'a été dit*"
        }

        It 'reads nothing as a rule that is not one: <Text>' -ForEach @(
            @{ Text = 'supprime les fichiers .log dans C:\Temp' }
            @{ Text = 'les fichiers sont dans C:\Temp' }
            @{ Text = 'tous les fichiers de C:\Temp' }
        ) {
            & (Get-Module Lambek) { param($t) Resolve-LambekCategory -Text $t } $Text | Should -BeNullOrEmpty
        }

        It 'keeps the register of the user when a question has the t of liaison' {
            Tell 'tous les oiseaux volent', 'Tweety est un oiseau'
            Ask 'Tweety vole-t-il ?' | Should -BeLike "*Parce que vous m'avez dit :*"
        }
    }

    Context 'The question that settles it' {

        It 'asks the question that would settle what cannot be concluded, and answers again on oui' {
            Tell 'tous les chats sont noirs'
            Ask 'Tom est-il noir ?' | Should -Be (@(
                    "Je ne peux pas le conclure avec ce que vous m'avez dit : « Tom est noir » peut être vrai ou faux."
                    'Une question trancherait : est-ce que Tom est un chat ?'
                    '- Si oui : Tom est noir.'
                ) -join "`n")
            Ask 'oui' | Should -Be (@(
                    "C'est noté. Tom est un chat. Je m'en souviendrai."
                    'Oui : Tom est noir.'
                    "Parce que vous m'avez dit :"
                    '- Tous les chats sont noirs.'
                    '- Tom est un chat.'
                ) -join "`n")
        }

        It 'keeps a non as told, and says plainly that it still cannot conclude' {
            Tell 'tous les chats sont noirs', 'Tom est-il noir ?'
            Ask 'non' | Should -Be (@(
                    "C'est noté. Tom n'est pas un chat. Je m'en souviendrai."
                    "Je ne peux pas le conclure avec ce que vous m'avez dit : « Tom est noir » peut être vrai ou faux."
                ) -join "`n")
        }

        It 'takes an answer said in full as the answer' {
            Tell 'tous les chats sont noirs', 'Tom est-il noir ?'
            @((Ask 'Tom est un chat') -split "`n")[0..1] | Should -Be @("C'est noté. Tom est un chat. Je m'en souviendrai.", 'Oui : Tom est noir.')
        }

        It 'says what a no would give, by the rule read backwards' {
            Tell 'tous les chats sont noirs'
            Ask 'Tom est-il un chat ?' | Should -Be (@(
                    "Je ne peux pas le conclure avec ce que vous m'avez dit : « Tom est un chat » peut être vrai ou faux."
                    'Une question trancherait : est-ce que Tom est noir ?'
                    "- Si non : Tom n'est pas un chat."
                ) -join "`n")
        }

        It 'asks about every one of a kind when the question is about every one' {
            Tell 'tous les chats sont des mammifères'
            @((Ask 'tous les chats sont-ils des animaux ?') -split "`n")[1] | Should -Be 'Une question trancherait : est-ce que tous les mammifères sont des animaux ?'
            @((Ask 'oui') -split "`n")[0..1] | Should -Be @("C'est noté. Tous les mammifères sont des animaux. Je m'en souviendrai.", 'Oui : tous les chats sont des animaux.')
        }

        It 'says one of a kind the way the language does: <Question>' -ForEach @(
            @{ Told = 'toutes les souris sont grises'; Question = 'est-ce que Jerry est grise ?'; Asked = 'Une question trancherait : est-ce que Jerry est une souris ?' }
            @{ Told = 'tous les chats de ma soeur sont noirs'; Question = 'Minou est-il noir ?'; Asked = 'Une question trancherait : est-ce que Minou est un chat de votre soeur ?' }
            @{ Told = 'tous les oiseaux volent'; Question = 'est-ce que Tweety vole ?'; Asked = 'Une question trancherait : est-ce que Tweety est un oiseau ?' }
            @{ Told = 'tous les hommes sont mortels'; Question = 'suis-je mortel ?'; Asked = 'Une question trancherait : est-ce que vous êtes un homme ?' }
            @{ Told = 'All cats are black.'; Question = 'Is Tom black?'; Asked = 'One question would settle it: is Tom a cat?' }
            @{ Told = 'All cats are mammals.'; Question = 'Are all cats animals?'; Asked = 'One question would settle it: are all mammals animals?' }
        ) {
            Tell $Told
            @((Ask $Question) -split "`n")[1] | Should -Be $Asked
        }

        It 'asks nothing when no question would help' {
            Tell 'certains chats sont gris', 'Tom est un chat'
            @((Ask 'Tom est-il gris ?') -split "`n").Count | Should -Be 2
        }

        It 'drops the question when something else is said' {
            Tell 'tous les chats sont noirs', 'Tom est-il noir ?', 'bonjour'
            Ask 'oui' | Should -Not -BeLike "C'est noté*"
        }

        It 'gives, for every syllogism it cannot conclude, a question whose answers do what it says they do' {
            $terms = @{
                S = @{ One = 'étudiant'; Many = 'étudiants' }
                M = @{ One = 'musicien'; Many = 'musiciens' }
                P = @{ One = 'artiste'; Many = 'artistes' }
            }
            $sentence = {
                param([string] $form, [string] $a, [string] $b, [switch] $ask)
                $x = $terms[$a]; $y = $terms[$b]
                $said = switch ($form) {
                    'A' { "tous les $($x.Many) sont des $($y.Many)" }
                    'E' { "aucun $($x.One) n'est un $($y.One)" }
                    'I' { "certains $($x.Many) sont des $($y.Many)" }
                    'O' { "certains $($x.Many) ne sont pas des $($y.Many)" }
                }
                if ($ask) { $(if ($form -eq 'E') { "est-ce qu'$said ?" } else { "est-ce que $said ?" }) } else { "$said." }
            }
            $figures = @(
                , @(@('M', 'P'), @('S', 'M'))
                , @(@('P', 'M'), @('S', 'M'))
                , @(@('M', 'P'), @('M', 'S'))
                , @(@('P', 'M'), @('M', 'S'))
            )
            $forms = 'A', 'E', 'I', 'O'
            $wrong = [System.Collections.Generic.List[string]]::new()
            $asked = 0
            foreach ($figure in $figures) {
                foreach ($major in $forms) {
                    foreach ($minor in $forms) {
                        foreach ($conclusion in $forms) {
                            $message = "$(& $sentence $major $figure[0][0] $figure[0][1]) $(& $sentence $minor $figure[1][0] $figure[1][1]) $(& $sentence $conclusion 'S' 'P' -ask)"
                            foreach ($answer in 'oui', 'non') {
                                & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null }
                                $first = Ask $message
                                if ($first -notlike '*Une question trancherait*') { continue }
                                $replies = @($first, (Ask $answer))
                                $asked++
                                $said = @($replies[0] -split "`n" | Where-Object { $_ -like "- Si $answer : *" })
                                $got = @($replies[1] -split "`n")[1]
                                if ($said.Count -eq 1) {
                                    $expected = $said[0] -replace "^- Si $answer : ", ''
                                    $ok = $got -eq "Oui : $expected" -or $got -eq "Non : $expected" -or ($got -like 'Non*' -and $expected -like '*pas*') -or ($got -like 'Oui*' -and $expected -notlike '*pas*')
                                    if (-not $ok -or $got -like 'Je ne peux pas*') { $wrong.Add("$message / $answer -> $got (said: $expected)") }
                                }
                                elseif ($got -notlike 'Je ne peux pas*') { $wrong.Add("$message / $answer -> $got (said nothing would follow)") }
                            }
                        }
                    }
                }
            }
            $asked | Should -BeGreaterThan 0
            $wrong | Should -BeNullOrEmpty
        }
    }

    Context 'What holds normalement' {

        It 'supposes what holds normalement, says it is supposed, and on what' {
            Tell 'normalement, les oiseaux volent', 'Tweety est un oiseau'
            Ask 'Tweety vole-t-il ?' | Should -Be (@(
                    'Normalement oui : Tweety vole.'
                    "Je le suppose, parce que vous m'avez dit :"
                    '- Normalement, les oiseaux volent.'
                    '- Tweety est un oiseau.'
                    'Si Tweety est une exception, dites-le-moi.'
                ) -join "`n")
        }

        It 'drops what it supposed when an exception is told' {
            Tell 'normalement, les oiseaux volent', 'Tweety est un oiseau', 'les pingouins ne volent pas', 'tous les pingouins sont des oiseaux', 'Tweety est un pingouin'
            Ask 'Tweety vole-t-il ?' | Should -Be (@(
                    'Non : Tweety ne vole pas.'
                    "Parce que vous m'avez dit :"
                    '- Les pingouins ne volent pas.'
                    '- Tweety est un pingouin.'
                ) -join "`n")
        }

        It 'never supposes against what was told, and never calls an exception a contradiction' {
            Tell 'les oiseaux volent normalement', 'Tweety est un oiseau'
            Ask 'Tweety ne vole pas' | Should -Be "C'est noté. Tweety ne vole pas. Je m'en souviendrai."
            @((Ask 'Tweety vole-t-il ?') -split "`n")[0] | Should -Be 'Non : Tweety ne vole pas.'
        }

        It 'lets the rule about the narrower kind go first' {
            $reply = Ask 'normalement les oiseaux volent. normalement les pingouins ne volent pas. tous les pingouins sont des oiseaux. Pingu est un pingouin. Pingu vole-t-il ?'
            $lines = @($reply -split "`n")
            $lines[0] | Should -Be 'Normalement non : Pingu ne vole pas.'
            $lines | Should -Contain '- Normalement les pingouins ne volent pas.'
            $lines | Should -Contain '- Pingu est un pingouin.'
            $lines | Should -Not -Contain '- Normalement les oiseaux volent.'
        }

        It 'says when rules that hold normalement contradict each other, and supposes nothing' {
            Ask 'normalement les quakers sont pacifistes. normalement les républicains ne sont pas pacifistes. Nixon est un quaker. Nixon est un républicain. Nixon est-il pacifiste ?' | Should -Be (@(
                    "Je ne peux pas le conclure : pour Nixon, des règles qui valent « normalement » se contredisent, et aucune n'est plus précise que l'autre :"
                    '- Normalement les quakers sont pacifistes.'
                    '- Normalement les républicains ne sont pas pacifistes.'
                    '- Nixon est un quaker.'
                    '- Nixon est un républicain.'
                ) -join "`n")
        }

        It 'reads what most of a kind do, and speaks of the user: <Question>' -ForEach @(
            @{ Told = 'la plupart des oiseaux volent', 'je suis un oiseau'; Question = 'est-ce que je vole ?'; First = 'Normalement oui : vous volez.'; Last = 'Si vous êtes une exception, dites-le-moi.' }
            @{ Told = 'Birds normally fly.', 'Tweety is a bird.'; Question = 'Does Tweety fly?'; First = 'Normally yes: Tweety does fly.'; Last = 'If Tweety is an exception, tell me.' }
            @{ Told = 'Most birds fly.', 'Penguins do not fly.', 'All penguins are birds.', 'Pingu is a penguin.'; Question = 'Does Pingu fly?'; First = 'No: Pingu does not fly.'; Last = '- Pingu is a penguin.' }
        ) {
            Tell $Told
            $lines = @((Ask $Question) -split "`n")
            $lines[0] | Should -Be $First
            $lines[-1] | Should -Be $Last
        }
    }

    Context 'Every syllogism' {

        # The 64 pairs of premises of the four figures, each with the four conclusions asked: what Lambek answers must be
        # what every model says (a model: which of the 8 kinds of individuals exist, at least one)
        It 'agrees with every model on every syllogism' {
            $terms = @{
                S = @{ One = 'étudiant'; Many = 'étudiants' }
                M = @{ One = 'musicien'; Many = 'musiciens' }
                P = @{ One = 'artiste'; Many = 'artistes' }
            }
            $sentence = {
                param([string] $form, [string] $a, [string] $b, [switch] $ask)
                $x = $terms[$a]; $y = $terms[$b]
                $said = switch ($form) {
                    'A' { "tous les $($x.Many) sont des $($y.Many)" }
                    'E' { "aucun $($x.One) n'est un $($y.One)" }
                    'I' { "certains $($x.Many) sont des $($y.Many)" }
                    'O' { "certains $($x.Many) ne sont pas des $($y.Many)" }
                }
                if ($ask) { $(if ($form -eq 'E') { "est-ce qu'$said ?" } else { "est-ce que $said ?" }) } else { "$said." }
            }
            $index = @{ S = 1; M = 2; P = 4 }
            $holds = {
                param([string] $form, [string] $a, [string] $b, [int] $model)
                $any = { param([scriptblock] $test) foreach ($kind in 0..7) { if (($model -band (1 -shl $kind)) -and (& $test $kind)) { return $true } }; $false }
                $isA = { param($kind) [bool] ($kind -band $index[$a]) }
                $isB = { param($kind) [bool] ($kind -band $index[$b]) }
                switch ($form) {
                    'A' { -not (& $any { param($k) (& $isA $k) -and -not (& $isB $k) }) }
                    'E' { -not (& $any { param($k) (& $isA $k) -and (& $isB $k) }) }
                    'I' { & $any { param($k) (& $isA $k) -and (& $isB $k) } }
                    'O' { & $any { param($k) (& $isA $k) -and -not (& $isB $k) } }
                }
            }
            $figures = @(
                , @(@('M', 'P'), @('S', 'M'))
                , @(@('P', 'M'), @('S', 'M'))
                , @(@('M', 'P'), @('M', 'S'))
                , @(@('P', 'M'), @('M', 'S'))
            )
            $forms = 'A', 'E', 'I', 'O'
            $wrong = [System.Collections.Generic.List[string]]::new()
            $count = 0
            foreach ($figure in $figures) {
                foreach ($major in $forms) {
                    foreach ($minor in $forms) {
                        foreach ($conclusion in $forms) {
                            $true1 = 0; $false1 = 0
                            for ($model = 1; $model -lt 256; $model++) {
                                if (-not (& $holds $major $figure[0][0] $figure[0][1] $model)) { continue }
                                if (-not (& $holds $minor $figure[1][0] $figure[1][1] $model)) { continue }
                                if (& $holds $conclusion 'S' 'P' $model) { $true1++ } else { $false1++ }
                            }
                            $expected = $(if ($false1 -eq 0) { 'yes' } elseif ($true1 -eq 0) { 'no' } else { 'unknown' })
                            $message = "$(& $sentence $major $figure[0][0] $figure[0][1]) $(& $sentence $minor $figure[1][0] $figure[1][1]) $(& $sentence $conclusion 'S' 'P' -ask)"
                            $reply = & (Get-Module Lambek) {
                                param($m)
                                Clear-LambekTold
                                $script:Told = $null
                                (Resolve-LambekCategory -Text $m).Reply
                            } $message
                            $first = @("$reply" -split "`n")[0]
                            $got = $(if ($first -like 'Oui*') { 'yes' } elseif ($first -like 'Non*') { 'no' } elseif ($first -like 'Je ne peux pas*') { 'unknown' } else { "?$first" })
                            $count++
                            if ($got -ne $expected) { $wrong.Add("$message -> $got, expected $expected") }
                        }
                    }
                }
            }
            $count | Should -Be 256
            $wrong | Should -BeNullOrEmpty
        }
    }
}
