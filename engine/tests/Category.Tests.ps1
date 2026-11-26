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
            # (in a sentence of its own, read back by a second Lambek; not twice in the same words)
            Ask 'est-ce que Minou est noir ?' | Should -Be "Oui, Minou est noir, car c'est un chat de votre soeur et tous les chats de votre soeur sont noirs."
            Ask 'Minou est-il noir ?' | Should -Be "Oui, Minou est noir : c'est un chat de votre soeur et tous les chats de votre soeur sont noirs."
        }

        It 'keeps what the answer says and what it rests on in the shape a checker reads' {
            Tell 'tous les hommes sont mortels', 'Socrate est un homme'
            Ask 'Socrate est-il mortel ?' | Out-Null
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('category(is|name:socrate|mortel)')
            $proof.Forms | Should -Be @('category(all|homme|mortel)', 'category(is|name:socrate|homme)')
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
            Ask 'Rex est-il un chat ?' | Should -Be "Non, Rex n'est pas un chat : c'est un chien et aucun chien n'est un chat."
        }

        It 'says that certains does not say which ones, and never guesses' {
            Tell 'certains chats sont gris', 'Tom est un chat'
            Ask 'Tom est-il gris ?' | Should -Be (@(
                    "Je ne peux pas le conclure avec ce que vous m'avez dit : « Tom est gris » peut être vrai ou faux."
                    '« Certains chats sont gris » ne dit pas lesquels.'
                ) -join "`n")
        }

        It 'solves a whole syllogism told in one message' {
            Ask 'Tous les hommes sont mortels. Socrate est un homme. Donc Socrate est-il mortel ?' | Should -Be "Oui, Socrate est mortel : c'est un homme et tous les hommes sont mortels."
        }

        It 'follows rules about every one, one after the other' {
            Tell 'tous les chats sont des mammifères', 'tous les mammifères sont des animaux'
            Ask 'est-ce que tous les chats sont des animaux ?' | Should -Be 'Oui, tous les chats sont des animaux, car tous les chats sont des mammifères et tous les mammifères sont des animaux.'
            Ask 'est-ce que certains chats ne sont pas des animaux ?' | Should -Be 'Non, tous les chats sont des animaux : tous les chats sont des mammifères et tous les mammifères sont des animaux.'
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
            Ask 'suis-je mortel ?' | Should -Be 'Oui, vous êtes mortel, car vous êtes un homme et tous les hommes sont mortels.'
            @((Ask 'qui est mortel ?') -split "`n")[0] | Should -Be 'Socrate et vous.'
        }

        It 'reasons with verbs, and with what they are done to: <Question>' -ForEach @(
            @{ Told = 'tous les oiseaux volent', 'Tweety est un oiseau'; Question = 'est-ce que Tweety vole ?'; First = "Oui, Tweety vole : c'est un oiseau et tous les oiseaux volent." }
            @{ Told = 'tous les oiseaux volent', 'Tweety est un oiseau'; Question = 'Tweety vole-t-il ?'; First = "Oui, Tweety vole : c'est un oiseau et tous les oiseaux volent." }
            @{ Told = 'aucun poisson ne vole', 'Nemo est un poisson'; Question = 'est-ce que Nemo vole ?'; First = "Non, Nemo ne vole pas : c'est un poisson, et aucun poisson ne vole." }
            @{ Told = 'tous les chats aiment le lait', 'Minou est un chat'; Question = 'Minou aime-t-il le lait ?'; First = "Oui, Minou aime le lait : c'est un chat et tous les chats aiment le lait." }
            @{ Told = "aucun chien n'aime le chocolat", 'Rex est un chien'; Question = 'est-ce que Rex aime le chocolat ?'; First = "Non, Rex n'aime pas le chocolat : c'est un chien et aucun chien n'aime le chocolat." }
            @{ Told = 'tous les chats aiment le lait', 'Minou est un chat'; Question = 'qui aime le lait ?'; First = 'Minou aime le lait.' }
            @{ Told = 'tous les chats sont noirs', 'je ne suis pas noir'; Question = 'suis-je un chat ?'; First = "Non, vous n'êtes pas un chat : vous n'êtes pas noir et tous les chats sont noirs." }
            @{ Told = 'All cats like milk.', 'Tom is a cat.'; Question = 'Does Tom like milk?'; First = 'Yes, Tom does like milk: Tom is a cat and all cats like milk.' }
            @{ Told = 'No dog likes chocolate.', 'Rex is a dog.'; Question = 'Does Rex like chocolate?'; First = 'No, Rex does not like chocolate: Rex is a dog and no dog likes chocolate.' }
            @{ Told = 'All cats like milk.', 'Tom is a cat.'; Question = 'Who likes milk?'; First = 'Tom likes milk.' }
            @{ Told = 'All cats of my sister are black.', 'Tom is a cat of my sister.'; Question = 'Is Tom black?'; First = 'Yes, Tom is black, because Tom is a cat of your sister and all cats of your sister are black.' }
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

    Context 'Someone said with le, ce or this' {

        It 'is of the kind its words name: <Question>' -ForEach @(
            @{ Told = 'tous les cerisiers sont des arbres'; Question = 'le cerisier est-il un arbre ?'; First = 'Oui : le cerisier est un arbre.' }
            @{ Told = 'all squares are rectangles', 'this shape is a square'; Question = 'is this shape a rectangle?'; First = 'Yes, this shape is a rectangle: this shape is a square and all squares are rectangles.' }
        ) {
            Tell $Told
            @((Ask $Question) -split "`n")[0] | Should -Be $First
        }

        It 'keeps what the words say by themselves apart from what was told' {
            Tell 'tous les cerisiers sont des arbres'
            Ask 'le cerisier est-il un arbre ?' | Out-Null
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Forms | Should -Be @('category(all|cerisier|arbre)')
            $proof.Assumed | Should -Be @('category(is|the:cerisier|cerisier)')
        }

        It 'assumes nothing when everything was told' {
            Tell 'les oiseaux volent normalement', 'Tweety est un oiseau'
            Ask 'Tweety vole-t-il ?' | Out-Null
            @((& (Get-Module Lambek) { Get-LambekLastProof }).Assumed).Count | Should -Be 0
        }
    }

    Context 'Contradictions' {

        It 'says at once what it replaces, when what is told cannot be true with what was told about the same one' {
            Tell "aucun chat n'est noir", 'Minou est un chat'
            Ask 'Minou est noir' | Should -Be (@(
                    "C'est noté. Minou est noir. Je m'en souviendrai."
                    "Je remplace ce que vous m'aviez dit :"
                    '- Minou est un chat.'
                ) -join "`n")
            @((Ask 'est-ce que Minou est noir ?') -split "`n")[0] | Should -Be 'Oui : Minou est noir.'
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

        It 'leaves to the memory what no rule told is about: <Told> / <Asked>' -ForEach @(
            @{ Rule = 'all dogs are animals'; Told = 'my cat is called Luna'; Asked = 'what is my cat called?'; Answer = '*Luna*' }
            @{ Rule = 'normalement, les oiseaux volent'; Told = 'ma soeur habite à Lyon'; Asked = 'où habite ma soeur ?'; Answer = '*Lyon*' }
            @{ Rule = 'birds usually fly'; Told = 'if it rains, I take the bus', 'it rains'; Asked = 'do I take the bus?'; Answer = '*take the bus*' }
        ) {
            Tell $Rule
            Tell $Told
            Ask $Asked | Should -BeLike $Answer
        }

        It 'still takes what a rule told is about, with something else told between' {
            Tell 'all dogs are animals', 'my cat is called Luna', 'Rex is a dog'
            Ask 'is Rex an animal?' | Should -BeLike 'Yes, Rex is an animal*'
        }

        It 'reads nothing as a rule that is not one: <Text>' -ForEach @(
            @{ Text = 'supprime les fichiers .log dans C:\Temp' }
            @{ Text = 'les fichiers sont dans C:\Temp' }
            @{ Text = 'tous les fichiers de C:\Temp' }
        ) {
            & (Get-Module Lambek) { param($t) Resolve-LambekCategory -Text $t } $Text | Should -BeNullOrEmpty
        }

        It 'keeps the register of the user when a question has the t of liaison' {
            # (said in lines: four reasons are too many for one sentence)
            Tell 'tous les animaux volent', 'tous les oiseaux sont des animaux', 'tous les pingouins sont des oiseaux', 'Tweety est un pingouin'
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
                    "Oui, Tom est noir, car c'est un chat et tous les chats sont noirs."
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
            @((Ask 'Tom est un chat') -split "`n")[0..1] | Should -Be @("C'est noté. Tom est un chat. Je m'en souviendrai.", "Oui, Tom est noir, car c'est un chat et tous les chats sont noirs.")
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
            @((Ask 'oui') -split "`n")[0..1] | Should -Be @("C'est noté. Tous les mammifères sont des animaux. Je m'en souviendrai.", 'Oui, tous les chats sont des animaux, car tous les chats sont des mammifères et tous les mammifères sont des animaux.')
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
                                    # (the answer said in a sentence of its own starts with what it says: "Non, tous les etudiants sont des artistes, car ...")
                                    $ok = $got -eq "Oui : $expected" -or $got -eq "Non : $expected" -or $got.StartsWith("Oui, $($expected.TrimEnd('.'))", [System.StringComparison]::Ordinal) -or $got.StartsWith("Non, $($expected.TrimEnd('.'))", [System.StringComparison]::Ordinal) -or ($got -like 'Non*' -and $expected -like '*pas*') -or ($got -like 'Oui*' -and $expected -notlike '*pas*')
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
            # (what is supposed is said as supposed, "normalement", with what it rests on)
            Ask 'Tweety vole-t-il ?' | Should -Be (@(
                    "Normalement oui, Tweety vole : c'est un oiseau et normalement, les oiseaux volent."
                    'Si Tweety est une exception, dites-le-moi.'
                ) -join "`n")
        }

        It 'drops what it supposed when an exception is told' {
            Tell 'normalement, les oiseaux volent', 'Tweety est un oiseau', 'les pingouins ne volent pas', 'tous les pingouins sont des oiseaux', 'Tweety est un pingouin'
            # (said of penguins with no word of how many, it holds normalement: the narrower rule still wins)
            (Ask 'Tweety vole-t-il ?') -join "`n" | Should -Be "Normalement non, Tweety ne vole pas : c'est un pingouin et les pingouins ne volent pas.`nSi Tweety est une exception, dites-le-moi."
        }

        It 'never supposes against what was told, and never calls an exception a contradiction' {
            Tell 'les oiseaux volent normalement', 'Tweety est un oiseau'
            Ask 'Tweety ne vole pas' | Should -Be "C'est noté. Tweety ne vole pas. Je m'en souviendrai."
            @((Ask 'Tweety vole-t-il ?') -split "`n")[0] | Should -Be 'Non : Tweety ne vole pas.'
        }

        It 'lets the rule about the narrower kind go first' {
            $reply = Ask 'normalement les oiseaux volent. normalement les pingouins ne volent pas. tous les pingouins sont des oiseaux. Pingu est un pingouin. Pingu vole-t-il ?'
            # (it rests on the rule about penguins, never on the one about birds)
            @($reply -split "`n")[0] | Should -Be "Normalement non, Pingu ne vole pas : c'est un pingouin et normalement les pingouins ne volent pas."
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
            @{ Told = 'la plupart des oiseaux volent', 'je suis un oiseau'; Question = 'est-ce que je vole ?'; First = 'Normalement oui, vous volez : vous êtes un oiseau et la plupart des oiseaux volent.'; Last = 'Si vous êtes une exception, dites-le-moi.' }
            @{ Told = 'Birds normally fly.', 'Tweety is a bird.'; Question = 'Does Tweety fly?'; First = 'Normally yes, Tweety does fly: Tweety is a bird and birds normally fly.'; Last = 'If Tweety is an exception, tell me.' }
            @{ Told = 'Most birds fly.', 'Penguins do not fly.', 'All penguins are birds.', 'Pingu is a penguin.'; Question = 'Does Pingu fly?'; First = 'Normally no, Pingu does not fly: Pingu is a penguin and penguins do not fly.'; Last = 'If Pingu is an exception, tell me.' }
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

    Context 'Read by the tags of the words' {

        It 'reasons with what is had, in French and in English: <Question>' -ForEach @(
            @{ Told = 'tous les appareils ont un capteur', 'mon téléphone est un appareil'; Question = 'mon téléphone a-t-il un capteur ?'; Said = 'Oui : votre téléphone a un capteur.*' }
            @{ Told = 'tous les oiseaux ont des plumes', 'le moineau est un oiseau'; Question = 'est-ce que le moineau a des plumes ?'; Said = 'Oui : *moineau a des plumes.*' }
            @{ Told = 'all devices have a sensor', 'my phone is a device'; Question = 'does my phone have a sensor?'; Said = 'Yes: your phone does have a sensor.*' }
        ) {
            Tell $Told
            Ask $Question | Should -BeLike $Said
        }

        It 'says what is not done to with the article a negation takes, learned: <Question>' -ForEach @(
            @{ Told = "les poissons n'ont pas de poils", 'Nemo est un poisson'; Question = 'Nemo a-t-il des poils ?'; Said = "Normalement non : Nemo n'a pas de poils.*" }
            @{ Told = "aucun poisson n'a d'ailes", 'Nemo est un poisson'; Question = 'Nemo a-t-il des ailes ?'; Said = "Non : Nemo n'a pas d'ailes.*" }
            @{ Told = 'aucun chien ne mange une salade', 'Rex est un chien'; Question = 'Rex mange-t-il une salade ?'; Said = 'Non, Rex ne mange pas de salade*' }
            @{ Told = "les chats n'aiment pas les légumes", 'Tom est un chat'; Question = 'Tom aime-t-il les légumes ?'; Said = "Normalement non, Tom n'aime pas les légumes*" }
            @{ Told = 'fish do not have fur', 'Nemo is a fish'; Question = 'does Nemo have fur?'; Said = 'Normally no: Nemo does not have fur.*' }
        ) {
            Tell $Told
            Ask $Question | Should -BeLike $Said
        }

        It 'learns the article of a negation from the treebanks, and none where a negation keeps its article' {
            $tiny = Join-Path $TestDrive 'negated.conllu'
            $denied = "1`tTom`tTom`tPROPN`t_`t_`t3`tnsubj`t_`t_`n2`tne`tne`tADV`t_`tPolarity=Neg`t3`tadvmod`t_`t_`n3`tmange`tmanger`tVERB`t_`t_`t0`troot`t_`t_`n4`tpas`tpas`tADV`t_`tPolarity=Neg`t3`tadvmod`t_`t_`n5`tde`tun`tDET`t_`tDefinite=Ind|PronType=Art`t6`tdet`t_`t_`n6`tpomme`tpomme`tNOUN`t_`t_`t3`tobj`t_`t_`n"
            $plain = "1`tTom`tTom`tPROPN`t_`t_`t2`tnsubj`t_`t_`n2`tmange`tmanger`tVERB`t_`t_`t0`troot`t_`t_`n3`tune`tun`tDET`t_`tDefinite=Ind|PronType=Art`t4`tdet`t_`t_`n4`tpomme`tpomme`tNOUN`t_`t_`t2`tobj`t_`t_`n"
            [IO.File]::WriteAllText($tiny, ((@(1..5 | ForEach-Object { $denied }) + @(1..5 | ForEach-Object { $plain })) -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
            $found = @([LambekLogicWords]::Negated([string[]] @($tiny), 3))
            @($found | Where-Object Kind -EQ 'negated').Word | Should -Be 'de'
            $kept = Join-Path $TestDrive 'kept.conllu'
            [IO.File]::WriteAllText($kept, (@(1..10 | ForEach-Object { $plain }) -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
            @([LambekLogicWords]::Negated([string[]] @($kept), 3)) | Should -BeNullOrEmpty
        }

        It 'reads a sentence as its tags and its words of logic say: <Sentence>' -ForEach @(
            @{ Language = 'fr'; Sentence = 'tous les chats boivent du lait'; Question = $false; Kind = 'all'; Predicate = 'v:boire>lait' }
            @{ Language = 'fr'; Sentence = 'chaque chat est un animal'; Question = $false; Kind = 'all'; Predicate = 'animal' }
            @{ Language = 'fr'; Sentence = "aucun chien n'aime les chats"; Question = $false; Kind = 'no'; Predicate = 'v:aimer>chat' }
            @{ Language = 'fr'; Sentence = 'les oiseaux ne volent pas'; Question = $false; Kind = 'no'; Predicate = 'v:voler' }
            @{ Language = 'fr'; Sentence = 'Tom a un chat'; Question = $false; Kind = 'does'; Predicate = 'v:avoir>chat' }
            @{ Language = 'fr'; Sentence = 'suis-je mortel'; Question = $true; Kind = 'askis'; Predicate = 'mortel' }
            @{ Language = 'fr'; Sentence = 'est-ce que Minou est noir'; Question = $true; Kind = 'askis'; Predicate = 'noir' }
            @{ Language = 'en'; Sentence = 'Socrates is a man'; Question = $false; Kind = 'is'; Predicate = 'man' }
            @{ Language = 'en'; Sentence = 'no fish is a mammal'; Question = $false; Kind = 'no'; Predicate = 'mammal' }
        ) {
            $read = InModuleScope Lambek -Parameters $_ { param($Language, $Sentence, $Question) Read-LambekCategoryTagged -Sentence $Sentence -Language $Language -Question:$Question }
            $read.Kind | Should -Be $Kind
            @($read.Predicate.Atoms) -join '+' | Should -Be $Predicate
        }

        It 'leaves to the rest what is no sentence, or asks which or how many: <Sentence>' -ForEach @(
            @{ Language = 'fr'; Sentence = 'raconte-moi une blague'; Question = $false }
            @{ Language = 'fr'; Sentence = "combien de pays sont membres de l'Union européenne"; Question = $true }
            @{ Language = 'en'; Sentence = 'Plan hash'; Question = $false }
            @{ Language = 'en'; Sentence = 'what is the capital of France'; Question = $true }
        ) {
            InModuleScope Lambek -Parameters $_ { param($Language, $Sentence, $Question) Read-LambekCategoryTagged -Sentence $Sentence -Language $Language -Question:$Question } | Should -BeNullOrEmpty
        }

        It 'has its words of logic and its copula learned, not written' {
            $logic = InModuleScope Lambek { Get-LambekLogicWord -Language fr }
            $logic.Kinds['tous'] | Should -Be 'all'
            $logic.Kinds['chaque'] | Should -Be 'all'
            $logic.Kinds['aucun'] | Should -Be 'no'
            $logic.Kinds['certains'] | Should -Be 'some'
            $logic.Copulas | Should -Contain 'être'
            (InModuleScope Lambek { Get-LambekLogicWord -Language en }).Copulas | Should -Contain 'be'
        }

        It 'learns a word of logic from sentences translated from English' {
            $words = InModuleScope Lambek {
                $english = @(1..4 | ForEach-Object { 'all cats are black', 'some dogs are white', 'the birds sing', 'the cats sleep' })
                $french = @(1..4 | ForEach-Object { 'tous les chats sont noirs', 'certains chiens sont blancs', 'les oiseaux chantent', 'les chats dorment' })
                [LambekLogicWords]::Learn((Get-LambekFormModel -Language en), (Get-LambekFormModel -Language fr), [string[]] $english, [string[]] $french, 3, 12)
            }
            @($words | Where-Object Word -EQ 'tous').Kind | Should -Be 'all'
            @($words | Where-Object Word -EQ 'certains').Kind | Should -Be 'some'
            @($words | Where-Object Word -EQ 'les') | Should -BeNullOrEmpty
        }

        It 'learns that some under a negation is none' {
            $words = InModuleScope Lambek {
                $english = @(1..4 | ForEach-Object { 'I do not see anyone', 'the birds sing' })
                $french = @(1..4 | ForEach-Object { 'je ne vois personne', 'les oiseaux chantent' })
                [LambekLogicWords]::Learn((Get-LambekFormModel -Language en), (Get-LambekFormModel -Language fr), [string[]] $english, [string[]] $french, 3, 12)
            }
            @($words | Where-Object Word -EQ 'personne').Kind | Should -Be 'no'
        }

        It 'has the words of logic and the copula of <Language> learned: <All>, <None>, <Some>, <Copula>' -ForEach @(
            @{ Language = 'de'; All = 'jeder'; None = 'kein'; Some = 'etwas'; Copula = 'sein' }
            @{ Language = 'es'; All = 'cada'; None = 'nada'; Some = 'algo'; Copula = 'ser' }
            @{ Language = 'nl'; All = 'elke'; None = 'geen'; Some = 'iemand'; Copula = 'zijn' }
            @{ Language = 'pt'; All = 'cada'; None = 'nada'; Some = 'alguém'; Copula = 'ser' }
            @{ Language = 'it'; All = 'ogni'; None = 'niente'; Some = 'qualcosa'; Copula = 'essere' }
        ) {
            $logic = InModuleScope Lambek -Parameters $_ { param($Language) Get-LambekLogicWord -Language $Language }
            $logic.Kinds[$All] | Should -Be 'all'
            $logic.Kinds[$None] | Should -Be 'no'
            $logic.Kinds[$Some] | Should -Be 'some'
            $logic.Copulas | Should -Contain $Copula
        }
    }

    Context 'What is told now replaces what cannot be true with it' {

        It 'keeps the newest and sets aside the sentence told before about the same one' {
            Tell 'no dog is a cat', 'Rex is a dog'
            (Ask 'Rex is a cat') -join ' ' | Should -BeLike '*I replace what you told me before:*- Rex is a dog.*'
            (Ask 'is Rex a cat?') -join ' ' | Should -BeLike 'Yes: Rex is a cat.*'
            (Ask 'is Rex a dog?') -join ' ' | Should -BeLike 'No, Rex is not a dog*'
        }

        It 'leaves the general rule standing, and what is told about someone else' {
            Tell 'no dog is a cat', 'Max is a dog', 'Rex is a dog', 'Rex is a cat'
            (Ask 'is Max a cat?') -join ' ' | Should -BeLike 'No, Max is not a cat*'
        }

        It 'replaces nothing, and says what cannot be true together, when the sentence told is a general rule' {
            Tell 'Rex is a dog', 'Rex is a cat'
            (Ask 'no dog is a cat') -join ' ' | Should -BeLike '*cannot all be true together:*'
        }

        It 'writes the line that replaces in the journal, and leaves the line replaced where it was' {
            Tell 'no bird is a fish', 'Pip is a bird', 'Pip is a fish'
            $lines = & (Get-Module Lambek) { @(Get-LambekToldJournal) }
            $replacing = @($lines | Where-Object { $_.PSObject.Properties['Replaces'] -and $_.Replaces })
            $replacing.Count | Should -BeGreaterThan 0
            $replaced = @($lines | Where-Object { "$($_.Hash)" -eq "$($replacing[-1].Replaces)" })
            $replaced.Count | Should -Be 1
            $replaced[0].Text | Should -Be 'Pip is a bird'
        }
    }

    Context 'Adjectives and plurals are read for what they say, no more' {

        It 'keeps an adjective with its noun: a big ant is no big insect' {
            Tell 'all ants are insects', 'Bob is a big ant'
            (Ask 'is Bob big?') -join ' ' | Should -BeLike 'Yes*'
            (Ask 'is Bob a big insect?') -join ' ' | Should -Not -BeLike 'Yes*'
            Tell 'toutes les fourmis sont des insectes', 'Bob est une grosse fourmi'
            (Ask 'Bob est-il un gros insecte ?') -join ' ' | Should -Not -BeLike 'Oui*'
            (Ask 'Bob est-il un insecte ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'reads an adjective that takes away what its noun says: <Told>' -ForEach @(
            @{ Told = 'Jean est un ancien étudiant'; Asked = 'Jean est-il un étudiant ?'; Again = 'Jean est-il un ancien étudiant ?'; Yes = 'Oui*' }
            @{ Told = 'Bob is a former soldier'; Asked = 'is Bob a soldier?'; Again = 'is Bob a former soldier?'; Yes = 'Yes*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -BeLike $Yes
            (Ask $Again) -join ' ' | Should -BeLike $Yes
        }

        It 'keeps the noun of an adjective said after it: "les Grecs anciens" are Grecs' {
            Tell 'Platon est un Grec ancien', 'tous les Grecs sont des humains'
            (Ask 'Platon est-il un Grec ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'lets the rule about the narrower kind go first when that kind is one only normalement' {
            Tell 'normalement, les oiseaux volent', 'les pingouins ne volent pas', 'les pingouins sont des oiseaux', 'Pingu est un pingouin'
            (Ask 'Pingu vole-t-il ?') -join ' ' | Should -BeLike 'Normalement non*'
        }

        It 'reads a plural with no word of how many as what holds normalement: <Told>' -ForEach @(
            @{ Told = 'les chats aiment le lait', 'Minou est un chat'; Asked = 'Minou aime-t-il le lait ?'; Said = 'Normalement oui*'; All = 'tous les chats aiment-ils le lait ?'; Yes = 'Oui*' }
            @{ Told = 'cats like milk', 'Felix is a cat'; Asked = 'does Felix like milk?'; Said = 'Normally yes*'; All = 'do all cats like milk?'; Yes = 'Yes*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
            (Ask $All) -join ' ' | Should -Not -BeLike $Yes
        }
    }

    Context 'What is said after a verb is kept whole when its words are not read one by one' {

        It 'keeps a wish for what it is, and no more: <Told>' -ForEach @(
            @{ Told = 'tous les Italiens veulent être de grands ténors', 'Luigi est un Italien'; Asked = 'Luigi veut-il être un grand ténor ?'; Wider = 'Luigi veut-il être un ténor ?'; Is = 'Luigi est-il un grand ténor ?'; Yes = 'Oui*' }
            @{ Told = 'all Italians want to be great tenors', 'Luigi is an Italian'; Asked = 'does Luigi want to be a great tenor?'; Wider = 'does Luigi want to be a tenor?'; Is = 'is Luigi a great tenor?'; Yes = 'Yes*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Yes
            (Ask $Wider) -join ' ' | Should -Not -BeLike $Yes
            (Ask $Is) -join ' ' | Should -Not -BeLike $Yes
        }

        It 'keeps what one can do apart from what one does' {
            Tell 'every European can travel freely within Europe', 'Klaus is a European'
            (Ask 'can Klaus travel freely within Europe?') -join ' ' | Should -BeLike 'Yes*'
            (Ask 'does Klaus travel freely within Europe?') -join ' ' | Should -Not -BeLike 'Yes*'
        }

        It 'reads a number, an article that says not which, or a word that says not how many as some: <Told>' -ForEach @(
            @{ Told = 'trois chats sont noirs'; Asked = 'certains chats sont-ils noirs ?'; Yes = 'Oui*' }
            @{ Told = 'plusieurs chiens aboient'; Asked = 'des chiens aboient-ils ?'; Yes = 'Oui : certains chiens aboient*' }
            @{ Told = 'des souris sont grises'; Asked = 'des souris sont-elles grises ?'; Yes = 'Oui : certaines souris sont grises*' }
            @{ Told = 'un Irlandais a reçu le prix Nobel'; Asked = 'un Irlandais a-t-il reçu le prix Nobel ?'; Yes = 'Oui*' }
            @{ Told = 'three dogs bark'; Asked = 'do some dogs bark?'; Yes = 'Yes*' }
            @{ Told = 'an Irishman won the Nobel prize'; Asked = 'did an Irishman win the Nobel prize?'; Yes = 'Yes*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Yes
        }

        It 'says no more of one than that some are' {
            Tell 'trois chats sont noirs', 'Minou est un chat'
            (Ask 'Minou est-il noir ?') -join ' ' | Should -Not -BeLike 'Oui*'
            (Ask 'tous les chats sont-ils noirs ?') -join ' ' | Should -Not -BeLike 'Oui*'
            Tell 'Sean is an Irishman', 'an Irishman won the Nobel prize'
            (Ask 'did Sean win the Nobel prize?') -join ' ' | Should -Not -BeLike 'Yes*'
        }

        It 'reads no some where how many may be none' {
            Tell 'moins de trois chats sont noirs'
            (Ask 'certains chats sont-ils noirs ?') -join ' ' | Should -Not -BeLike 'Oui*'
            Tell 'few cats are black'
            (Ask 'are some cats black?') -join ' ' | Should -Not -BeLike 'Yes*'
        }

        It 'answers no question for more than one from one: <Asked>' -ForEach @(
            @{ Asked = 'plusieurs comptables ont-ils assisté à la réunion ?' }
            @{ Asked = 'trois comptables ont-ils assisté à la réunion ?' }
        ) {
            Tell 'un seul comptable a assisté à la réunion'
            (Ask $Asked) -join ' ' | Should -Not -BeLike 'Oui*'
            (Ask 'des comptables ont-ils assisté à la réunion ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'finds that some said with a number cannot be with none' {
            Tell 'aucun chat n''est noir'
            (Ask 'trois chats sont noirs') -join ' ' | Should -BeLike '*ne peuvent pas être vraies ensemble*'
        }

        It 'says a verb told in a past with the verb that helps it: <Asked>' -ForEach @(
            @{ Told = 'tous les chats ont mangé du poisson', 'Tom est un chat'; Asked = 'Tom a-t-il mangé du poisson ?'; Said = 'Oui : Tom a mangé du poisson.' }
            @{ Told = 'aucun chat n''a mangé', 'Tom est un chat'; Asked = 'Tom a-t-il mangé ?'; Said = 'Non : Tom n''a pas mangé.' }
            @{ Told = 'all cats have eaten', 'Tom is a cat'; Asked = 'has Tom eaten?'; Said = 'Yes: Tom has eaten.' }
            @{ Told = 'no cat has eaten', 'Tom is a cat'; Asked = 'has Tom eaten?'; Said = 'No: Tom has not eaten.' }
            @{ Told = 'alle Katzen haben gegessen', 'Tom ist eine Katze'; Asked = 'hat Tom gegessen?'; Said = 'Ja. Tom hat gegessen.' }
        ) {
            Tell $Told
            @((Ask $Asked) -split "`n")[0] | Should -Be $Said
        }

        It 'reads the article said before an adjective in the plural: <Told>' -ForEach @(
            @{ Told = 'tous les Italiens sont de grands ténors', 'Luigi est un Italien'; Asked = 'Luigi est-il un grand ténor ?', 'Luigi est-il un ténor ?' }
            @{ Told = 'tous les chats sont de petits animaux', 'Tom est un chat'; Asked = 'Tom est-il un animal ?' }
        ) {
            Tell $Told
            foreach ($question in $Asked) { (Ask $question) -join ' ' | Should -BeLike 'Oui*' }
        }

        It 'keeps the "de" of where one comes from' {
            Tell 'tous les Italiens sont de Rome', 'Luigi est un Italien'
            (Ask 'Luigi est-il Rome ?') -join ' ' | Should -Not -BeLike 'Oui*'
        }

        It 'asks of a pronoun for the one told of last that agrees with it: <Asked>' -ForEach @(
            @{ Told = 'toutes les étudiantes sont curieuses', 'Marie est une étudiante', 'Tom est un chat'; Asked = 'est-elle curieuse ?'; Said = 'Oui, Marie est curieuse*' }
            @{ Told = 'tous les chats aiment le lait', 'Tom est un chat'; Asked = 'aime-t-il le lait ?'; Said = 'Oui, Tom aime le lait*' }
            @{ Told = 'all cats like milk', 'Tom is a cat'; Asked = 'does he like milk?'; Said = 'Yes, Tom does like milk*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'stands a pronoun for nobody when it agrees with none, or for one of several' {
            # ("ils" stands for them both now: 'Several told of together, then "ils" for them')
            Tell 'tous les chiens aboient', 'Rex et Max sont des chiens'
            (Ask 'aboie-t-il ?') -join ' ' | Should -Not -BeLike 'Oui*'
            Tell 'toutes les étudiantes sont curieuses', 'Tom est un chat'
            (Ask 'est-elle curieuse ?') -join ' ' | Should -Not -BeLike 'Oui*'
        }

        It 'reads several things told in one message, a pronoun standing for one told before it' {
            Tell 'Tom est un chat. Il est noir.'
            (Ask 'Tom est-il noir ?') -join ' ' | Should -BeLike 'Oui*'
            Tell 'Rex is a dog. Max is a cat.'
            (Ask 'is Max a cat?') -join ' ' | Should -BeLike 'Yes*'
            (Ask 'is Rex a cat?') -join ' ' | Should -Not -BeLike 'Yes*'
        }

        It 'reads a kind said with what those of it do, after a relative pronoun: <Told>' -ForEach @(
            @{ Told = 'les chats qui sont noirs aiment le lait', 'Tom est un chat', 'Tom est noir'; Asked = 'Tom aime-t-il le lait ?'; Yes = 'Normalement oui*' }
            @{ Told = 'tout Européen a le droit de vivre en Europe', 'tout Européen est une personne', 'toute personne qui a le droit de vivre en Europe peut circuler librement en Europe', 'Klaus est un Européen'; Asked = 'Klaus peut-il circuler librement en Europe ?'; Yes = 'Oui*' }
            @{ Told = 'all dogs that bark are noisy', 'Rex is a dog', 'Rex barks'; Asked = 'is Rex noisy?'; Yes = 'Yes*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Yes
        }

        It 'says nothing of one not said to do what the clause says' {
            Tell 'all dogs that bark are noisy', 'Rex is a dog'
            (Ask 'is Rex noisy?') -join ' ' | Should -Not -BeLike 'Yes*'
            Tell 'les chats qui sont noirs aiment le lait', 'Minou est un chat'
            (Ask 'Minou aime-t-il le lait ?') -join ' ' | Should -Not -BeLike '*oui*'
        }

        It 'does not read a clause about someone else as one about the kind' {
            Tell 'Paul est un homme'
            (Ask 'le chien que Paul aime est noir') -join ' ' | Should -Not -BeLike 'C''est noté. Le chien*'
        }

        It 'reads two kinds, or two things said, joined by the word that says both: <Told>' -ForEach @(
            @{ Told = 'tous les chats et les chiens sont des animaux', 'Rex est un chien'; Asked = 'Rex est-il un animal ?'; Yes = 'Oui*' }
            @{ Told = 'tous les chats sont noirs et gentils', 'Tom est un chat'; Asked = 'Tom est-il gentil ?'; Yes = 'Oui*' }
            @{ Told = 'tous les chiens aboient et mordent', 'Rex est un chien'; Asked = 'Rex mord-il ?'; Yes = 'Oui*' }
            @{ Told = 'all cats and dogs are animals', 'Rex is a dog'; Asked = 'is Rex an animal?'; Yes = 'Yes*' }
            @{ Told = 'alle Katzen und Hunde sind Tiere', 'Rex ist ein Hund'; Asked = 'ist Rex ein Tier?'; Yes = 'Ja*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Yes
        }

        It 'never splits what says one of them, or what says not of both: <Told>' -ForEach @(
            @{ Told = 'Rex o Max es un perro'; Asked = '¿es Rex un perro?'; Yes = 'Sí*' }
            @{ Told = 'Rex oder Max ist ein Hund'; Asked = 'ist Rex ein Hund?'; Yes = 'Ja*' }
            @{ Told = 'tous les chats sont noirs ou blancs', 'Tom est un chat'; Asked = 'Tom est-il noir ?'; Yes = 'Oui*' }
            @{ Told = 'Rex est un chien ou un chat'; Asked = 'Rex est-il un chat ?'; Yes = 'Oui*' }
            @{ Told = "Rex n'est pas un chien ou un chat", 'Rex est un animal'; Asked = 'Rex est-il un chien ?'; Yes = 'Non*' }
            @{ Told = 'tous les chiens aboient ou mordent', 'Rex est un chien'; Asked = 'Rex mord-il ?'; Yes = 'Oui*' }
            @{ Told = 'aucun chat n''est noir et gentil', 'Tom est un chat'; Asked = 'Tom est-il noir ?'; Yes = 'Non*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -BeLike $Yes
        }

        It 'reads one of two kinds joined by the word that says one of them: <Asked>' -ForEach @(
            @{ Told = 'Rex est un chien ou un chat', "Rex n'est pas un chat"; Asked = 'Rex est-il un chien ?'; Said = 'Oui, Rex est un chien : c''est un chien ou un chat et ce n''est pas un chat.' }
            @{ Told = 'tous les chiens sont des animaux', 'tous les chats sont des animaux', 'Rex est un chien ou un chat'; Asked = 'Rex est-il un animal ?'; Said = 'Oui, Rex est un animal*' }
            @{ Told = 'tous les chats sont noirs ou blancs', 'Tom est un chat', "Tom n'est pas noir"; Asked = 'Tom est-il blanc ?'; Said = 'Oui, Tom est blanc*' }
            @{ Told = 'Tom est un chat noir ou un chien', "Tom n'est pas un chien"; Asked = 'Tom est-il noir ?'; Said = 'Oui, Tom est noir*' }
            @{ Told = 'Rex est un cheval', "aucun cheval n'est un chien", "aucun cheval n'est un chat"; Asked = 'Rex est-il un chien ou un chat ?'; Said = 'Non*' }
            @{ Told = 'every dog is black or white', 'Rex is a dog', 'Rex is not white'; Asked = 'is Rex black?'; Said = 'Yes, Rex is black*' }
            @{ Told = 'Rex is een hond of een kat', 'Rex is geen kat'; Asked = 'is Rex een hond?'; Said = 'Ja. Rex is een hond.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'keeps one of two kinds in the shape the checker reads, and never says no for one of them alone' {
            Tell 'Rex est un chien ou un chat', "Rex n'est pas un chat"
            $null = Ask 'Rex est-il un chien ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Forms | Should -Be @('category(is|name:rex|or:chat;chien)', 'category(isnot|name:rex|chat)')
            Tell 'Max est un cheval', "aucun cheval n'est un chat"
            (Ask 'Max est-il un chien ou un chat ?') -join ' ' | Should -Not -BeLike 'Non*'
        }

        It 'reads an object said with two small words the same as with one' {
            Tell "aucun chien ne mange d'herbe", 'Rex est un chien'
            (Ask "Rex mange-t-il de l'herbe ?") -join ' ' | Should -BeLike 'Non*'
            Tell 'tous les chiens mangent de la viande', 'Max est un chien'
            (Ask 'Max mange-t-il de la viande ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'says two names told together back as they were told, and keeps each' {
            Ask 'Tom et Rex sont des animaux' | Should -Be "C'est noté. Tom et Rex sont des animaux. Je m'en souviendrai."
            (Ask 'Rex est-il un animal ?') -join ' ' | Should -BeLike 'Oui*- Tom et Rex sont des animaux.'
        }

        It 'answers each part of a question joined by the word that says both: <Asked>' -ForEach @(
            @{ Told = 'tous les chats sont noirs'; Asked = 'tous les chats sont-ils noirs et gentils ?'; Said = 'Oui : tous les chats sont noirs.*peut être vrai ou faux*' }
            @{ Told = 'all dogs bark', 'all dogs bite'; Asked = 'do all dogs bark and bite?'; Said = 'Yes: all dogs bark.*Yes: all dogs bite.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }
    }

    Context 'What holds for a time is said with the day it was told' {

        It 'says the day of a state told another day, in <Language>' -ForEach @(
            @{ Language = 'fr'; Told = 'Minou est noir', 'Rex est un chien', 'tous les chats aiment le lait'; Dated = 'Minou est noir (dit le 6 octobre 2026).'; Kept = 'Rex est un chien.', 'Tous les chats aiment le lait.'; Asked = "qu'est-ce que je t'ai dit ?" }
            @{ Language = 'en'; Told = 'Felix is black', 'Rex is a dog', 'all cats like milk'; Dated = 'Felix is black (told on October 6, 2026).'; Kept = 'Rex is a dog.', 'All cats like milk.'; Asked = 'what did I tell you?' }
        ) {
            Tell $Told
            & (Get-Module Lambek) { $script:Now = [datetime] '2026-10-09 10:00' }
            $lines = @((Ask $Asked) -split "`n" | ForEach-Object { $_ -replace '^- ', '' })
            $lines | Should -Contain $Dated
            foreach ($kept in $Kept) { $lines | Should -Contain $kept }
        }

        It 'says no day for what was told the same day' {
            Tell 'Minou est noir'
            & (Get-Module Lambek) { $script:Now = [datetime] '2026-10-06 18:00' }
            (Ask "qu'est-ce que je t'ai dit ?") -join ' ' | Should -Not -BeLike '*(dit le*'
        }

        It 'answers from a state told before, with its day in the proof' {
            Tell 'Minou est noir', 'Minou est un chat', 'tous les chats aiment le lait'
            & (Get-Module Lambek) { $script:Now = [datetime] '2026-10-09 10:00' }
            (Ask 'Minou est-il noir ?') -join "`n" | Should -BeLike "Oui : Minou est noir.*- Minou est noir (dit le 6 octobre 2026).*"
        }
    }

    Context 'A correction takes back what it corrects, and what followed from it' {

        It 'lets go of what is taken back with <Taken>' -ForEach @(
            @{ Taken = 'non, en fait Tom est un chien' }
            @{ Taken = "je me suis trompé, Tom n'est pas un chat" }
            @{ Taken = 'correction : Tom est un chien, pas un chat' }
            @{ Taken = "pardon, Tom n'est pas un chat mais un chien" }
        ) {
            Tell 'Tom est un chat', 'Minou est un chat', 'tous les chats aiment le lait', $Taken
            (Ask 'Tom est-il un chat ?') -join ' ' | Should -Not -BeLike 'Oui*'
            (Ask 'Tom aime-t-il le lait ?') -join ' ' | Should -Not -BeLike 'Oui*'
            (Ask 'Minou aime-t-il le lait ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'lets go of what is taken back in English: <Taken>' -ForEach @(
            @{ Taken = 'no, actually Tom is a dog' }
            @{ Taken = 'I was wrong, Tom is not a cat' }
            @{ Taken = 'correction: Tom is a dog, not a cat' }
            @{ Taken = 'sorry, Tom is not a cat but a dog' }
        ) {
            Tell 'Tom is a cat', 'Felix is a cat', 'all cats like milk', $Taken
            (Ask 'is Tom a cat?') -join ' ' | Should -Not -BeLike 'Yes*'
            (Ask 'does Tom like milk?') -join ' ' | Should -Not -BeLike 'Yes*'
            (Ask 'does Felix like milk?') -join ' ' | Should -BeLike 'Yes*'
        }

        It 'says what it replaces, apart from what is noted' {
            Tell 'Tom est un chat'
            $lines = @((Ask 'non, en fait Tom est un chien') -split "`n")
            $lines[0] | Should -BeLike "C'est noté. Tom est un chien.*"
            $lines | Should -Contain "Je remplace ce que vous m'aviez dit :"
            $lines | Should -Contain '- Tom est un chat.'
        }

        It 'writes in the journal which line the correction replaces' {
            Tell 'Pip est un oiseau', 'non, en fait Pip est un poisson'
            $lines = & (Get-Module Lambek) { @(Get-LambekToldJournal) }
            $replacing = @($lines | Where-Object { $_.PSObject.Properties['Replaces'] -and $_.Replaces })
            $replacing.Count | Should -Be 1
            @($lines | Where-Object { "$($_.Hash)" -eq "$($replacing[0].Replaces)" })[0].Text | Should -Be 'Pip est un oiseau'
        }

        It 'keeps a kind the dictionary says the new one is a kind of, or is a kind of' {
            Tell 'Tom est un animal', 'non, en fait Tom est un chien'
            (Ask 'Tom est-il un animal ?') -join ' ' | Should -BeLike 'Oui*'
            Tell 'Minou est un chat', 'non, en fait Minou est un siamois'
            (Ask 'Minou est-il un chat ?') -join ' ' | Should -BeLike 'Oui : Minou est un chat.*'
        }

        It 'takes nothing back without the words marked off: <Told>' -ForEach @(
            @{ Told = 'no dog is a cat' }
            @{ Told = 'actually Rex is a cat' }
        ) {
            Tell 'Rex is a dog', $Told
            (Ask 'is Rex a dog?') -join ' ' | Should -Not -BeLike 'No*'
        }

        It 'takes back nothing of someone else' {
            Tell 'Rex est un chien', 'non, en fait Tom est un chat'
            (Ask 'Rex est-il un chien ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'never takes back a general rule' {
            Tell 'tous les chats aiment le lait', 'Tom est un chat', "non, en fait Tom n'aime pas le lait", 'Minou est un chat'
            (Ask 'Minou aime-t-il le lait ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'leaves out a kind from the dictionary that makes what was told contradict itself' {
            Tell 'Nemo est un dauphin', "Nemo n'est pas un poisson"
            (Ask 'Nemo est-il un dauphin ?') -join ' ' | Should -BeLike 'Oui*'
        }
    }

    Context 'A rule reaches what the dictionary says is a kind of what the rule is about' {

        It 'follows a rule about cats for a siamese, and says the dictionary said so' {
            Tell 'tous les chats sont noirs', 'Minou est un siamois'
            $said = (Ask 'est-ce que Minou est noir ?') -join "`n"
            $said | Should -BeLike 'Oui : Minou est noir.*'
            $said | Should -BeLike "*D'apr*dictionnaire*siamois*sorte de*chat*"
        }

        It 'says what the dictionary says apart from what was told' {
            Tell 'tous les chats sont noirs', 'Minou est un siamois'
            $lines = @((Ask 'est-ce que Minou est noir ?') -split "`n")
            # (every sentence told is listed with a dash under "you told me"; the dictionary speaks for itself)
            @($lines | Where-Object { $_ -like "*dictionnaire*" -and $_ -like '-*' }).Count | Should -Be 0
        }

        It 'says the dictionary again for a pourquoi, apart from what was told' {
            Tell 'tous les chats sont noirs', 'Minou est un siamois'
            $null = Ask 'est-ce que Minou est noir ?'
            $lines = @((Ask 'pourquoi ?') -split "`n")
            $lines | Should -Contain '- Tous les chats sont noirs.'
            $lines | Should -Contain '- Minou est un siamois.'
            @($lines | Where-Object { $_ -like "D'apr*dictionnaire*siamois*chat*" }).Count | Should -Be 1
            @($lines | Where-Object { $_ -like '-*dictionnaire*' }).Count | Should -Be 0
        }

        It 'works with a rule that says no one of a kind is something' {
            Tell "aucun chat n'aime l'eau", 'Minou est un siamois'
            (Ask "est-ce que Minou aime l'eau ?") -join ' ' | Should -BeLike "Non : Minou n'aime pas l'eau.*siamois*chat*"
        }

        It 'never goes down: a rule about siamese says nothing of a cat' {
            Tell 'tous les siamois sont bleus', 'Minou est un chat'
            (Ask 'est-ce que Minou est bleu ?') -join ' ' | Should -Not -BeLike 'Oui*'
        }

        It 'follows the way up in <Language>: <Question>' -ForEach @(
            @{ Language = 'en'; Told = 'all cats are black', 'Minou is a siamese'; Question = 'is Minou black?'; Said = 'Yes: Minou is black.*dictionary*siamese*kind of*cat*' }
            @{ Language = 'nl'; Told = 'elke hond is een dier', 'Rex is een teckel'; Question = 'is Rex een dier?'; Said = 'Ja. Rex is een dier.*teckel*hond*' }
        ) {
            Tell $Told
            (Ask $Question) -join ' ' | Should -BeLike $Said
        }

        It 'names the dictionary it found the kind in' {
            Tell 'tous les chats sont noirs', 'Minou est un siamois'
            (Ask 'est-ce que Minou est noir ?') -join ' ' | Should -BeLike "*D'après le dictionnaire (WOLF*, Open English WordNet*), « siamois » est une sorte de « chat »*"
        }

        It 'keeps where each premise comes from: what was told here, and the dictionary by its name' {
            Tell 'tous les chats sont noirs', 'Minou est un siamois'
            $null = Ask 'est-ce que Minou est noir ?'
            $sources = @(& (Get-Module Lambek) { (Get-LambekLastProof).Sources })
            @($sources | Where-Object { $_.Kind -eq 'told' -and $_.Name -eq 'here' }).Count | Should -Be 2
            $book = @($sources | Where-Object Kind -EQ 'dictionary')
            $book.Count | Should -Be 1
            $book[0].Id | Should -Be 'siamois<chat'
            $book[0].Name | Should -BeLike 'WOLF*Open English WordNet*'
        }

        It 'says a sentence told in a conversation before comes from the journal, by its line' {
            Tell 'tous les chats sont noirs', 'Minou est un chat'
            & (Get-Module Lambek) { $script:Told = $null; $script:ToldJournal = $null }
            $null = Ask 'est-ce que Minou est noir ?'
            $sources = @(& (Get-Module Lambek) { (Get-LambekLastProof).Sources })
            $before = @($sources | Where-Object { $_.Kind -eq 'told' -and $_.Name -eq 'before' })
            $before.Count | Should -Be 2
            $lines = & (Get-Module Lambek) { @(Get-LambekToldJournal) }
            foreach ($source in $before) { @($lines | Where-Object { "$($_.Hash)" -eq $source.Id }).Count | Should -Be 1 }
        }

        It 'gives the dictionary to the checker as a premise of its own, never as a thing told' {
            Tell 'tous les chats sont noirs', 'Minou est un siamois'
            $null = Ask 'est-ce que Minou est noir ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            @($proof.Facts).Count | Should -Be 2
            @($proof.Assumed) | Should -Contain 'category(all|siamois|chat)'
        }
    }

    Context 'How many of a kind are so' {

        It 'answers how many from what was told: <Asked>' -ForEach @(
            @{ Told = @('au moins trois chats sont noirs'); Asked = 'au moins deux chats sont-ils noirs ?'; Said = 'Oui.*au moins trois chats sont noirs*' }
            @{ Told = @('au moins trois chats sont noirs'); Asked = 'au plus deux chats sont-ils noirs ?'; Said = 'Non.*' }
            @{ Told = @('au plus deux chats sont noirs'); Asked = 'au moins trois chats sont-ils noirs ?'; Said = 'Non.*Au plus deux chats sont noirs.' }
            @{ Told = @('au plus deux chats sont noirs'); Asked = 'au plus cinq chats sont-ils noirs ?'; Said = 'Oui.*' }
            @{ Told = @('tous les siamois sont des chats', 'au moins trois siamois sont noirs'); Asked = 'au moins trois chats sont-ils noirs ?'; Said = 'Oui.*Tous les siamois sont des chats.' }
            @{ Told = @('tous les siamois sont des chats', 'au plus deux chats sont noirs'); Asked = 'au moins trois siamois sont-ils noirs ?'; Said = 'Non.*' }
            @{ Told = @('exactement deux chats sont noirs'); Asked = 'trois chats sont-ils noirs ?'; Said = 'Non.*' }
            @{ Told = @('at least three dogs bark'); Asked = 'do at least two dogs bark?'; Said = 'Yes.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'never says yes or no when what was told does not say it: <Asked>' -ForEach @(
            @{ Told = @('au moins trois chats sont noirs'); Asked = 'au moins quatre chats sont-ils noirs ?' }
            @{ Told = @('au moins trois siamois sont noirs'); Asked = 'au moins trois chats sont-ils noirs ?' }
            @{ Told = @('tous les siamois sont des chats', 'au moins trois chats sont noirs'); Asked = 'au moins trois siamois sont-ils noirs ?' }
            @{ Told = @('au plus deux siamois sont noirs'); Asked = 'au moins trois chats sont-ils noirs ?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike '*peut être vrai ou faux*'
        }

        It 'keeps how many in the shape the checker reads' {
            Tell 'tous les siamois sont des chats', 'au plus deux chats sont noirs'
            $null = Ask 'au moins trois siamois sont-ils noirs ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('count(notleast|3|siamois|noir)')
            $proof.Forms | Should -Be @('count(most|2|chat|noir)', 'category(all|siamois|chat)')
        }
    }

    Context 'A sentence inside another' {

        It 'reasons with a rule told with if about named ones: <Asked>' -ForEach @(
            @{ Told = @('si Rex est un chien, Rex aboie', 'Rex est un chien'); Asked = 'Rex aboie-t-il ?'; Said = 'Oui*si Rex est un chien, Rex aboie*' }
            @{ Told = @('si Rex est un chien, Rex aboie', "Rex n'aboie pas"); Asked = 'Rex est-il un chien ?'; Said = 'Non*' }
            @{ Told = @('Rex aboie si Rex est un chien', 'Rex est un chien'); Asked = 'Rex aboie-t-il ?'; Said = 'Oui*' }
            @{ Told = @('si Rex est un chien, Max est un chat', 'Rex est un chien'); Asked = 'Max est-il un chat ?'; Said = 'Oui*' }
            @{ Told = @('si Rex est un chien, Max est un chat', "Max n'est pas un chat"); Asked = 'Rex est-il un chien ?'; Said = 'Non*' }
            @{ Told = @('wenn Rex ein Hund ist, bellt Rex', 'Rex ist ein Hund'); Asked = 'bellt Rex?'; Said = 'Ja.*' }
            @{ Told = @('if Rex is a dog, Max is a cat', 'Rex is a dog'); Asked = 'is Max a cat?'; Said = 'Yes*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'concludes nothing from a rule told with if whose condition was not told' {
            Tell 'si Rex est un chien, Rex aboie'
            (Ask 'Rex aboie-t-il ?') -join ' ' | Should -Not -BeLike 'Oui*'
            Tell 'Rex aboie'
            (Ask 'Rex est-il un chien ?') -join ' ' | Should -Not -BeLike 'Oui*'
        }

        It 'keeps what someone believes apart from what is so' {
            Tell 'Alice croit que Rex est un chat'
            $said = (Ask 'Rex est-il un chat ?') -join ' '
            $said | Should -Not -BeLike 'Oui*'
            $said | Should -Not -BeLike 'Non*'
        }

        It 'answers what someone believes from what that one believes alone: <Asked>' -ForEach @(
            @{ Told = @('Alice croit que tous les chats sont noirs', 'Alice croit que Tom est un chat'); Asked = 'Alice croit-elle que Tom est noir ?'; Said = 'Oui : Alice croit que Tom est noir.*' }
            @{ Told = @('Alice croit que aucun chat n''est noir', 'Alice croit que Tom est un chat'); Asked = 'Alice croit-elle que Tom est noir ?'; Said = 'Non.*' }
            @{ Told = @('Alice believes that all cats are black', 'Alice believes that Tom is a cat'); Asked = 'does Alice believe that Tom is black?'; Said = 'Yes: Alice believes that Tom is black.*' }
            @{ Told = @('Alice glaubt, dass alle Katzen schwarz sind', 'Alice glaubt, dass Tom eine Katze ist'); Asked = 'glaubt Alice, dass Tom schwarz ist?'; Said = 'Ja.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'never takes what is so, nor what another believes, for what one believes: <Asked>' -ForEach @(
            @{ Told = @('tous les chats sont noirs', 'Alice croit que Tom est un chat'); Asked = 'Alice croit-elle que Tom est noir ?' }
            @{ Told = @('Paul croit que tous les chats sont noirs', 'Alice croit que Tom est un chat'); Asked = 'Alice croit-elle que Tom est noir ?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike '*peut être vrai ou faux*'
        }

        It 'takes what someone knows as so' {
            Tell 'Alice sait que Rex est un chien'
            (Ask 'Rex est-il un chien ?') -join ' ' | Should -BeLike 'Oui*Alice sait que Rex est un chien*'
            (Ask 'Alice croit-elle que Rex est un chien ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'keeps a rule told with if and what one believes in the shapes the checker reads' {
            Tell 'si Rex est un chien, Rex aboie', "Rex n'aboie pas"
            $null = Ask 'Rex est-il un chien ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('category(isnot|name:rex|chien)')
            $proof.Forms | Should -Be @('category(if|is~name:rex~chien|does~name:rex~v:aboyer)', 'category(doesnot|name:rex|v:aboyer)')
            Tell 'Alice croit que tous les chats sont noirs', 'Alice croit que Tom est un chat'
            $null = Ask 'Alice croit-elle que Tom est noir ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('category(believe|name:alice|is~name:tom~noir)')
            $proof.Forms | Should -Be @('category(believe|name:alice|all~chat~noir)', 'category(believe|name:alice|is~name:tom~chat)')
        }
    }

    Context 'Which of two kinds one is' {

        It 'says which one when one follows and the other does not: <Asked>' -ForEach @(
            @{ Told = @('Rex est un chien'); Asked = 'Rex est-il un chien ou un chat ?'; Said = 'Rex est un chien.*Rex est un chien*' }
            @{ Told = @('Rex est un chien ou un chat', "Rex n'est pas un chat"); Asked = 'Rex est-il un chien ou un chat ?'; Said = 'Rex est un chien.*' }
            @{ Told = @('tous les chats sont noirs', 'Tom est un chat'); Asked = 'Tom est-il noir ou blanc ?'; Said = 'Tom est noir.*' }
            @{ Told = @('Rex is a dog'); Asked = 'is Rex a dog or a cat?'; Said = 'Rex is a dog.*' }
            @{ Told = @('Rex es un perro'); Asked = '¿es Rex un perro o un gato?'; Said = 'Rex es un perro.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'does not say which when it may be either' {
            Tell 'Rex est un chien ou un chat'
            (Ask 'Rex est-il un chien ou un chat ?') -join ' ' | Should -BeLike 'Oui : Rex est un chien ou un chat.*'
        }

        It 'keeps the one that follows as what the checker reads' {
            Tell 'Rex est un chien ou un chat', "Rex n'est pas un chat"
            $null = Ask 'Rex est-il un chien ou un chat ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('category(is|name:rex|chien)')
            $proof.Forms | Should -Be @('category(is|name:rex|or:chat;chien)', 'category(isnot|name:rex|chat)')
        }
    }

    Context 'Neither one thing nor the other' {

        It 'reads what is said not of two things at once: <Asked>' -ForEach @(
            @{ Told = @("Rex n'est ni un chat ni un oiseau"); Asked = 'Rex est-il un oiseau ?'; Said = "Non : Rex n'est pas un oiseau.*Rex n'est ni un chat ni un oiseau.*" }
            @{ Told = @("Rex n'est ni un chat ni un oiseau"); Asked = 'Rex est-il un chat ?'; Said = "Non : Rex n'est pas un chat.*" }
            @{ Told = @('Ni les chats ni les chiens ne volent', 'Tom est un chien'); Asked = 'Tom vole-t-il ?'; Said = 'Normalement non*' }
            @{ Told = @('Rex is neither a cat nor a bird'); Asked = 'is Rex a cat?'; Said = 'No: Rex is not a cat.*' }
            @{ Told = @('Neither cats nor dogs fly', 'Tom is a dog'); Asked = 'does Tom fly?'; Said = 'Normally no*' }
            @{ Told = @('Rex ist weder eine Katze noch ein Vogel'); Asked = 'ist Rex ein Vogel?'; Said = 'Nein.*' }
            @{ Told = @('Rex no es ni un gato ni un pájaro'); Asked = '¿es Rex un pájaro?'; Said = 'No.*' }
            @{ Told = @('Rex não é nem um gato nem um pássaro'); Asked = 'Rex é um gato?'; Said = 'Não.*' }
            @{ Told = @('Rex non è né un gatto né un uccello'); Asked = 'Rex è un uccello?'; Said = 'No.*' }
            @{ Told = @('Rex is noch een kat noch een vogel'); Asked = 'is Rex een kat?'; Said = 'Nee.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'does not suppose what it has no words to say is only supposed' {
            Tell 'Weder Katzen noch Hunde fliegen', 'Tom ist ein Hund'
            (Ask 'fliegt Tom?') -join ' ' | Should -BeLike 'Ich wei*nicht*'
        }

        It 'says it back once, as it was said' {
            (Ask "Rex n'est ni un chat ni un oiseau.") -join ' ' | Should -BeLike "C'est noté. Rex n'est ni un chat ni un oiseau.*"
        }

        It 'makes two sentences that say not, with the words learned of the language: <Text>' -ForEach @(
            @{ Language = 'fr'; Text = "Rex n'est ni un chat ni un oiseau"; Parts = @("Rex n'est un chat", "Rex n'est un oiseau") }
            @{ Language = 'en'; Text = 'Rex is neither a cat nor a bird'; Parts = @('Rex is not a cat', 'Rex is not a bird') }
            @{ Language = 'de'; Text = 'Weder Katzen noch Hunde fliegen'; Parts = @('Katzen fliegen nicht', 'Hunde fliegen nicht') }
            @{ Language = 'es'; Text = 'Ni los gatos ni los perros vuelan'; Parts = @('los gatos no vuelan', 'los perros no vuelan') }
            @{ Language = 'nl'; Text = 'Rex is noch een kat noch een vogel'; Parts = @('Rex is niet een kat', 'Rex is niet een vogel') }
        ) {
            $parts = & (Get-Module Lambek) { param($t, $l) @(Split-LambekCategoryNeither -Text $t -Language $l) } $Text $Language
            $parts | Should -Be $Parts
        }

        It 'makes nothing of a sentence where the words do not say not of both: <Text>' -ForEach @(
            @{ Language = 'de'; Text = 'Rex ist noch ein Welpe' }
            @{ Language = 'fr'; Text = 'Rex est un chat ni' }
            @{ Language = 'fr'; Text = "ni Rex n'est un chat" }
            @{ Language = 'en'; Text = 'Rex is a cat and a dog' }
        ) {
            $parts = & (Get-Module Lambek) { param($t, $l) @(Split-LambekCategoryNeither -Text $t -Language $l) } $Text $Language
            $parts.Count | Should -Be 0
        }
    }

    Context 'One of two things told of ones named' {

        It 'reasons from one of two sentences joined by or: <Asked>' -ForEach @(
            @{ Told = @('Rex est un chien ou Max est un chat', "Rex n'est pas un chien"); Asked = 'Max est-il un chat ?'; Said = 'Oui : Max est un chat.*Rex est un chien ou Max est un chat*' }
            @{ Told = @("Rex n'est pas un chien ou Max est un chat", 'Rex est un chien'); Asked = 'Max est-il un chat ?'; Said = 'Oui : Max est un chat.*' }
            @{ Told = @('tous les chiens aboient', 'Rex est un chien ou Max est un chat', "Max n'est pas un chat"); Asked = 'Rex aboie-t-il ?'; Said = 'Oui : Rex aboie.*' }
            @{ Told = @('Rex est un chien ou Rex est un chat', 'tous les chiens sont des animaux', 'tous les chats sont des animaux'); Asked = 'Rex est-il un animal ?'; Said = 'Oui : Rex est un animal.*' }
            @{ Told = @('Rex is a dog or Max is a cat', 'Rex is not a dog'); Asked = 'is Max a cat?'; Said = 'Yes: Max is a cat.*' }
            @{ Told = @('Rex barks or Max sleeps', 'Max does not sleep'); Asked = 'does Rex bark?'; Said = 'Yes: Rex does bark.*' }
            @{ Told = @('Rex ist ein Hund oder Max ist eine Katze', 'Max ist keine Katze'); Asked = 'ist Rex ein Hund?'; Said = 'Ja. Rex ist ein Hund.*' }
            @{ Told = @('Rex es un perro o Max es un gato', 'Rex no es un perro'); Asked = '¿Max es un gato?'; Said = 'Sí. Max es un gato.*' }
            @{ Told = @('Rex is een hond of Max is een kat', 'Rex is geen hond'); Asked = 'is Max een kat?'; Said = 'Ja. Max is een kat.*' }
            @{ Told = @('Rex é um cão ou Max é um gato', 'Rex não é um cão'); Asked = 'Max é um gato?'; Said = 'Sim. Max é um gato.*' }
            @{ Told = @('Rex è un cane o Max è un gatto', 'Rex non è un cane'); Asked = 'Max è un gatto?'; Said = 'Sì. Max è un gatto.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'reasons from two things done, in a chat in the language they are told in' {
            # (alone, "Rex aboie ou Max dort" reads as German by its letters, "dort"; the chat says it is French)
            & (Get-Module Lambek) { $script:LanguageHint = 'fr' }
            try {
                Tell 'Rex aboie ou Max dort', 'Max ne dort pas'
                (Ask 'Rex aboie-t-il ?') -join ' ' | Should -BeLike 'Oui : Rex aboie.*'
            }
            finally { & (Get-Module Lambek) { $script:LanguageHint = $null } }
        }

        It 'does not conclude what only one of the two would give: <Asked>' -ForEach @(
            @{ Told = @('Rex est un chien ou Max est un chat'); Asked = 'Max est-il un chat ?' }
            @{ Told = @('Rex est un chien ou Max est un chat', "Rex n'est pas un chien"); Asked = 'Rex est-il un chien ?' }
            @{ Told = @('Rex est un chien ou Max est un chien', 'tous les chiens aboient'); Asked = 'Rex aboie-t-il ?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -BeLike 'Oui*'
        }

        It 'keeps it in the shape the checker reads' {
            Tell 'Rex est un chien ou Max est un chat', "Rex n'est pas un chien"
            $null = Ask 'Max est-il un chat ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Forms | Should -Be @('category(or|is~name:rex~chien|is~name:max~chat)', 'category(isnot|name:rex|chien)')
        }

        It 'reads one sentence with or between two kinds as before, not as two sentences' {
            $read = & (Get-Module Lambek) { Read-LambekCategoryEmbedded -Sentence 'Rex est un chien ou un chat' -Language 'fr' }
            $read | Should -BeNullOrEmpty
        }
    }

    Context 'One thing done before another, and on a day' {

        It 'answers before and after from what was told: <Asked>' -ForEach @(
            @{ Told = @('Rex est arrivé avant Max', 'Max est arrivé avant Tom'); Asked = 'Rex est-il arrivé avant Tom ?'; Said = 'Oui : Rex est arrivé avant Tom.*' }
            @{ Told = @('Rex est arrivé après Max', 'Max est arrivé après Tom'); Asked = 'Rex est-il arrivé après Tom ?'; Said = 'Oui*' }
            @{ Told = @('Rex est arrivé hier', "Max est arrivé aujourd'hui"); Asked = 'Rex est-il arrivé avant Max ?'; Said = 'Oui*Rex est arrivé hier*' }
            @{ Told = @('Rex est arrivé hier'); Asked = 'Rex est-il arrivé hier ?'; Said = 'Oui*' }
            @{ Told = @('Rex arrived yesterday', 'Max arrived today'); Asked = 'did Max arrive after Rex?'; Said = 'Yes*' }
            @{ Told = @('Rex ist vor Max angekommen', 'Max ist vor Tom angekommen'); Asked = 'ist Rex vor Tom angekommen?'; Said = 'Ja.*' }
            @{ Told = @('gestern hat Rex gegessen'); Asked = 'hat Rex gestern gegessen?'; Said = 'Ja.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'never says yes or no when what was told does not say it, nor after from before: <Asked>' -ForEach @(
            @{ Told = @('Rex est arrivé hier'); Asked = "Rex est-il arrivé aujourd'hui ?" }
            @{ Told = @('Rex est arrivé hier'); Asked = 'Max est-il arrivé hier ?' }
            @{ Told = @('Rex est arrivé avant Max', 'Rex est arrivé avant Tom'); Asked = 'Max est-il arrivé avant Tom ?' }
            @{ Told = @('Rex a nagé avant Max'); Asked = 'Max a-t-il nagé après Rex ?' }
            @{ Told = @('Rex a nagé avant Max'); Asked = 'Max a-t-il nagé avant Rex ?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike '*peut être vrai ou faux*'
        }

        It 'keeps what is done on a day with the day it was told on' {
            Tell 'Rex est arrivé hier'
            & (Get-Module Lambek) { $script:Now = [datetime] '2026-10-07 10:00' }
            (Ask 'Rex est-il arrivé hier ?') -join ' ' | Should -BeLike '*peut être vrai ou faux*'
            (Ask 'Rex est-il arrivé avant Max ?') -join ' ' | Should -BeLike '*peut être vrai ou faux*'
        }

        It 'keeps before and on a day in the shapes the checker reads' {
            Tell 'Rex est arrivé hier', "Max est arrivé aujourd'hui"
            $null = Ask 'Rex est-il arrivé avant Max ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('compare(more|time:before:arriver|name:rex|name:max)')
            $proof.Forms | Should -Be @('date(time:arriver|name:rex|2026-10-05)', 'date(time:arriver|name:max|2026-10-06)')
        }
    }

    Context 'A short sentence read in its language' {

        It 'tells the language of a short sentence by how each language writes its words: <Text>' -ForEach @(
            @{ Text = 'Rex è alto?'; Language = 'it' }
            @{ Text = 'Max è alto'; Language = 'it' }
            @{ Text = 'Rex no es alto'; Language = 'es' }
            @{ Text = 'Rex es más alto que Max'; Language = 'es' }
            @{ Text = 'alle Hunde bellen'; Language = 'de' }
            @{ Text = 'Rex ist ein Hund'; Language = 'de' }
        ) {
            & (Get-Module Lambek) {
                param($Text)
                $script:LanguageHint = $null
                Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) -Text $Text -Forms -Letters
            } $Text | Should -Be $Language
        }

        It 'says nothing of a word no language writes, alone' {
            & (Get-Module Lambek) { Get-LambekLanguageLikelihood -Text 'slt' } | Should -BeNullOrEmpty
        }

        It 'reasons in the language of short sentences told with nothing before them' {
            Tell 'Max è alto', 'Rex è più alto di Max'
            (Ask 'Rex è alto?') -join ' ' | Should -BeLike 'Sì*'
        }
    }

    Context 'The fewest sentences an answer rests on' {

        It 'rests on a thing told rather than on a way through several: <Name>' -ForEach @(
            @{ Name = 'told last'; Told = 'Rex est un chien', 'tous les chiens sont des animaux', 'Rex est un animal' }
            @{ Name = 'told first'; Told = 'Rex est un animal', 'Rex est un chien', 'tous les chiens sont des animaux' }
        ) {
            Tell $Told
            Ask 'Rex est-il un animal ?' | Should -Be (@('Oui : Rex est un animal.', "Parce que vous m'avez dit :", '- Rex est un animal.') -join "`n")
        }

        It 'gives the same, shortest way whatever order the rules were told in: <Name>' -ForEach @(
            @{ Name = 'long way first'; Told = 'tous les chiens sont des mammifères', 'tous les mammifères sont des animaux', 'tous les chiens sont des animaux', 'Rex est un chien' }
            @{ Name = 'short way first'; Told = 'tous les chiens sont des animaux', 'Rex est un chien', 'tous les chiens sont des mammifères', 'tous les mammifères sont des animaux' }
        ) {
            Tell $Told
            Ask 'Rex est-il un animal ?' | Should -Be "Oui, Rex est un animal : c'est un chien et tous les chiens sont des animaux."
            $least = (& (Get-Module Lambek) { Get-LambekLastProof }).Least
            $least.Least | Should -BeTrue
            $least.Checked | Should -Be 2
        }

        It 'says how far it looked when it could not try every smaller set' {
            & (Get-Module Lambek) {
                # (told first that Rex is of the second kind, then that it is of the first, and that the first is the
                # second: taking each out in turn keeps the way of two; only trying the sets of one finds the first)
                $statements = [System.Collections.Generic.List[LambekCategoryStatement]]::new()
                $s = [LambekCategoryStatement]::new(); $s.AddNamed('rex', [int[]] @(2)); $statements.Add($s)
                $s = [LambekCategoryStatement]::new(); $s.AddNamed('rex', [int[]] @(1)); $statements.Add($s)
                $s = [LambekCategoryStatement]::new(); $s.AddEvery([int[]] @(-1, 2)); $statements.Add($s)
                $question = [LambekCategoryStatement]::new(); $question.AddNamed('rex', [int[]] @(-2))
                $all = [LambekCategories]::Shortest($statements.ToArray(), $question, $null, 100)
                $all.Indices | Should -Be @(0)
                $all.Least | Should -BeTrue
                $cut = [LambekCategories]::Shortest($statements.ToArray(), $question, $null, 0)
                $cut.Indices | Should -Be @(1, 2)
                $cut.Least | Should -BeFalse
                $cut.Checked | Should -Be 1
            }
        }
    }

    Context 'One compared with the contrary word' {

        It 'reads more of the contrary the other way round: <Asked>' -ForEach @(
            @{ Told = @('Rex est plus petit que Max'); Asked = 'Max est-il plus grand que Rex ?'; Said = "Oui : Max est plus grand que Rex.*Rex est plus petit que Max*le contraire de*" }
            @{ Told = @('Rex est plus petit que Max', 'Max est plus petit que Tom'); Asked = 'Tom est-il plus grand que Rex ?'; Said = 'Oui : Tom est plus grand que Rex.*' }
            @{ Told = @('Rex est plus grand que Max'); Asked = 'Rex est-il plus petit que Max ?'; Said = 'Non : Max est plus petit que Rex.*' }
            @{ Told = @('Max est grand', 'Max est plus petit que Rex'); Asked = 'Rex est-il grand ?'; Said = 'Oui : Rex est grand.*' }
            @{ Told = @('Rex ist kleiner als Max'); Asked = 'ist Max größer als Rex?'; Said = 'Ja. Max ist größer als Rex.*' }
            @{ Told = @('Rex es más bajo que Max'); Asked = '¿es Max más alto que Rex?'; Said = 'Sí. Max es más alto que Rex.*' }
            @{ Told = @('Rex é mais baixo que Max'); Asked = 'Max é mais alto que Rex?'; Said = 'Sim. Max é mais alto que Rex.*' }
            @{ Told = @('Rex è più basso di Max'); Asked = 'Max è più alto di Rex?'; Said = 'Sì. Max è più alto di Rex.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'keeps the contrary apart, as the checker reads it' {
            Tell 'Rex est plus petit que Max'
            $null = Ask 'Max est-il plus grand que Rex ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Forms | Should -Be @('compare(more|petit|name:rex|name:max)')
            $proof.Assumed | Should -Be @('antonym(grand|petit)')
        }

        It 'says when the contrary goes back on what was told' {
            Tell 'Rex est plus petit que Max'
            (Ask 'Rex est plus grand que Max') -join ' ' | Should -BeLike '*Attention*'
        }

        It 'says no to the contrary of what one was told to be: <Asked>' -ForEach @(
            @{ Told = @('Rex est petit'); Asked = 'Rex est-il grand ?'; Said = "Non : Rex n'est pas grand.*Rex est petit*le contraire de*" }
            @{ Told = @('Rex est grand'); Asked = 'Rex est-il petit ?'; Said = "Non : Rex n'est pas petit.*" }
            @{ Told = @('tous les chats sont petits', 'Tom est un chat'); Asked = 'Tom est-il grand ?'; Said = "Non : Tom n'est pas grand.*Tous les chats sont petits*" }
            @{ Told = @('Rex ist klein'); Asked = 'ist Rex groß?'; Said = 'Nein.*Rex ist klein*' }
            @{ Told = @('Rex é baixo'); Asked = 'Rex é alto?'; Said = 'Não.*Rex é baixo*' }
            @{ Told = @('Rex è basso'); Asked = 'Rex è alto?'; Said = 'No.*Rex è basso*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'does not take not so for the contrary: <Asked>' -ForEach @(
            @{ Told = @("Rex n'est pas petit"); Asked = 'Rex est-il grand ?' }
            @{ Told = @('Rex est petit'); Asked = 'Max est-il grand ?' }
        ) {
            Tell $Told
            $said = (Ask $Asked) -join ' '
            $said | Should -Not -BeLike 'Oui*'
            $said | Should -Not -BeLike 'Non*'
        }

        It 'keeps the contrary of a kind apart, as the checker reads it' {
            Tell 'Rex est petit'
            $null = Ask 'Rex est-il grand ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Forms | Should -Be @('category(is|name:rex|petit)')
            $proof.Assumed | Should -Be @('category(no|grand|petit)')
        }

        It 'learns a contrary only where it is the only one: <Word>' -ForEach @(
            @{ Language = 'fr'; Word = 'grand'; Contrary = 'petit' }
            @{ Language = 'fr'; Word = 'petit'; Contrary = 'grand' }
            @{ Language = 'fr'; Word = 'vieux'; Contrary = $null }
            @{ Language = 'en'; Word = 'short'; Contrary = $null }
        ) {
            $pairs = & (Get-Module Lambek) { param($l) (Get-LambekAntonym -Language $l).Pairs } $Language
            $found = $null
            if ($pairs.TryGetValue($Word, [ref] $found)) { $found | Should -Be $Contrary } else { $Contrary | Should -BeNullOrEmpty }
        }
    }

    Context 'One said to be as much as another' {

        It 'reasons from as much as, which is at least as much: <Asked>' -ForEach @(
            @{ Told = @('Rex est aussi grand que Max', 'Max est plus grand que Tom'); Asked = 'Rex est-il plus grand que Tom ?'; Said = 'Oui : Rex est plus grand que Tom.*Rex est aussi grand que Max*' }
            @{ Told = @('Rex est aussi grand que Max', 'Max est aussi grand que Tom'); Asked = 'Rex est-il aussi grand que Tom ?'; Said = 'Oui : Rex est aussi grand que Tom.*' }
            @{ Told = @('Rex est plus grand que Max'); Asked = 'Rex est-il aussi grand que Max ?'; Said = 'Oui : Rex est aussi grand que Max.*' }
            @{ Told = @('Rex est aussi grand que Max'); Asked = 'Max est-il plus grand que Rex ?'; Said = 'Non.*Rex est aussi grand que Max*' }
            @{ Told = @('Max est plus grand que Rex'); Asked = 'Rex est-il aussi grand que Max ?'; Said = 'Non.*Max est plus grand que Rex*' }
            @{ Told = @('Max est grand', 'Rex est aussi grand que Max'); Asked = 'Rex est-il grand ?'; Said = 'Oui : Rex est grand.*' }
            @{ Told = @('Rex is as tall as Max', 'Max is taller than Tom'); Asked = 'is Rex taller than Tom?'; Said = 'Yes: Rex is taller than Tom.*' }
            @{ Told = @('Rex ist so groß wie Max', 'Max ist größer als Tom'); Asked = 'ist Rex größer als Tom?'; Said = 'Ja. Rex ist größer als Tom.*' }
            @{ Told = @('Rex es tan alto como Max', 'Max es más alto que Tom'); Asked = '¿es Rex más alto que Tom?'; Said = 'Sí. Rex es más alto que Tom.*' }
            @{ Told = @('Rex is zo groot als Max', 'Max is groter dan Tom'); Asked = 'is Rex groter dan Tom?'; Said = 'Ja. Rex is groter dan Tom.*' }
            @{ Told = @('Rex é tão alto quanto Max', 'Max é mais alto que Tom'); Asked = 'Rex é mais alto que Tom?'; Said = 'Sim. Rex é mais alto que Tom.*' }
            @{ Told = @('Rex è tanto alto quanto Max', 'Max è più alto di Tom'); Asked = 'Rex è più alto di Tom?'; Said = 'Sì. Rex è più alto di Tom.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'does not take as much for more' {
            Tell 'Rex est aussi grand que Max'
            (Ask 'Rex est-il plus grand que Max ?') -join ' ' | Should -BeLike 'Je ne peux pas le conclure*'
        }

        It 'says when as much goes back on more' {
            Tell 'Max est plus grand que Rex'
            (Ask 'Rex est aussi grand que Max') -join ' ' | Should -BeLike '*Attention*Max est plus grand que Rex*Rex est aussi grand que Max*'
        }

        It 'keeps it in the shape the checker reads' {
            Tell 'Rex est aussi grand que Max', 'Max est plus grand que Tom'
            $null = Ask 'Rex est-il plus grand que Tom ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Forms | Should -Be @('compare(atleast|grand|name:rex|name:max)', 'compare(more|grand|name:max|name:tom)')
        }

        It 'reads "aussi" alone as before, not as much as' {
            $read = & (Get-Module Lambek) { Read-LambekComparison -Sentence 'Rex est aussi un chien' -Language 'fr' }
            $read | Should -BeNullOrEmpty
        }
    }

    Context 'One said to be more than another' {

        It 'follows more from one to the next, and says what it rests on' {
            Tell 'Rex est plus grand que Max', 'Max est plus grand que Tom'
            Ask 'Rex est-il plus grand que Tom ?' | Should -Be (@(
                    'Oui : Rex est plus grand que Tom.'
                    "Parce que vous m'avez dit :"
                    '- Rex est plus grand que Max.'
                    '- Max est plus grand que Tom.'
                ) -join "`n")
        }

        It 'says no when the other is the one said to be more' {
            Tell 'Rex est plus grand que Max', 'Max est plus grand que Tom'
            (Ask 'Tom est-il plus grand que Rex ?') -join ' ' | Should -BeLike 'Non : Rex est plus grand que Tom.*'
        }

        It 'never guesses about one nothing was said of, or about another way of being more' {
            Tell 'Rex est plus grand que Max'
            (Ask 'Tom est-il plus grand que Max ?') -join ' ' | Should -BeLike '*peut être vrai ou faux*'
            (Ask 'Rex est-il plus fort que Max ?') -join ' ' | Should -BeLike '*« Rex est plus fort que Max » peut être vrai ou faux*'
        }

        It 'reads several joined by the word that says both, on either side' {
            Ask 'Rex et Max sont plus grands que Tom' | Should -Be "C'est noté. Rex et Max sont plus grands que Tom. Je m'en souviendrai."
            Tell 'Tom est plus grand que Paul'
            (Ask 'Max est-il plus grand que Paul ?') -join ' ' | Should -BeLike 'Oui : Max est plus grand que Paul.*- Rex et Max sont plus grands que Tom.*- Tom est plus grand que Paul.'
            (Ask 'Rex et Max sont-ils plus grands que Paul ?') -join ' ' | Should -BeLike 'Oui : Rex et Max sont plus grands que Paul.*'
            (Ask 'Paul et Rex sont-ils plus grands que Tom ?') -join ' ' | Should -BeLike 'Non.*- Tom est plus grand que Paul.'
            Tell 'Luc est plus petit que Rex, Max et Paul'
            (Ask 'Luc est-il plus petit que Paul ?') -join ' ' | Should -BeLike 'Oui*'
        }

        It 'reads one named with figures in its name' {
            Tell 'the XR-200 is faster than the ZX-10'
            (Ask 'is the XR-200 faster than the ZX-10?') -join ' ' | Should -BeLike 'Yes*'
            (Ask 'is the ZX-10 faster than the XR-200?') -join ' ' | Should -BeLike 'No*'
        }

        It 'says one is so when it is more so than one that is, and not when it is less so than one that is not' {
            Tell 'Max est grand', 'Rex est plus grand que Max'
            Ask 'Rex est-il grand ?' | Should -Be (@(
                    'Oui : Rex est grand.'
                    "Parce que vous m'avez dit :"
                    '- Rex est plus grand que Max.'
                    '- Max est grand.'
                ) -join "`n")
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('category(is|name:rex|grand)')
            $proof.Forms | Should -Be @('compare(more|grand|name:rex|name:max)', 'category(is|name:max|grand)')
            Tell "Paul n'est pas grand", 'Paul est plus grand que Luc'
            (Ask 'Luc est-il grand ?') -join ' ' | Should -BeLike "Non : Luc n'est pas grand.*"
        }

        It 'never says one is so from one less so, or from another way of being more: <Asked>' -ForEach @(
            @{ Told = 'Max est grand', 'Max est plus grand que Rex'; Asked = 'Rex est-il grand ?' }
            @{ Told = 'Max est grand', 'Rex est plus fort que Max'; Asked = 'Rex est-il grand ?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -BeLike 'Oui*'
            (Ask $Asked) -join ' ' | Should -Not -BeLike 'Non*'
        }

        It 'says one is so from one less so of the contrary, only from the contrary learned, and says where it comes from' {
            # (no contrary guessed: "petit" and "grand" are each other's only contrary in Wiktionary and the wordnet)
            Tell 'Max est petit', 'Rex est moins grand que Max'
            (Ask 'Rex est-il petit ?') -join ' ' | Should -BeLike "Oui : Rex est petit.*Rex est moins grand que Max*Max est petit*d'après les dictionnaires*contraire*"
        }

        It 'reads less the other way' {
            Tell 'le chat est moins grand que le chien', 'le chien est moins grand que le cheval'
            (Ask 'le chat est-il moins grand que le cheval ?') -join ' ' | Should -BeLike 'Oui : le chat est moins grand que le cheval.*'
        }

        It 'says when what is told cannot be true with what was told' {
            Tell 'Rex est plus grand que Max', 'Max est plus grand que Tom'
            (Ask 'Tom est plus grand que Rex') -join ' ' | Should -BeLike '*ne peuvent pas être vraies ensemble*- Tom est plus grand que Rex.*'
        }

        It 'reads it in <Language>: <Question>' -ForEach @(
            @{ Language = 'en'; Told = 'Rex is taller than Max', 'Max is taller than Tom'; Question = 'is Rex taller than Tom?'; Said = 'Yes*' }
            @{ Language = 'de'; Told = 'Rex ist größer als Max', 'Max ist größer als Tom'; Question = 'ist Rex größer als Tom?'; Said = 'Ja*' }
            @{ Language = 'it'; Told = 'Rex è più alto di Max', 'Max è più alto di Tom'; Question = 'Tom è più alto di Rex?'; Said = 'No*' }
        ) {
            Tell $Told
            (Ask $Question) -join ' ' | Should -BeLike $Said
        }

        It 'keeps the answer in the shape a checker reads' {
            Tell 'Rex est plus grand que Max', 'Max est plus grand que Tom'
            $null = Ask 'Rex est-il plus grand que Tom ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('compare(more|grand|name:rex|name:tom)')
            $proof.Forms | Should -Be @('compare(more|grand|name:rex|name:max)', 'compare(more|grand|name:max|name:tom)')
        }
    }

    Context 'Several told of together, then "ils" for them' {

        It 'asks of each one of the group, and says it once: <Asked>' -ForEach @(
            @{ Told = @('Rex et Max sont des chiens', 'tous les chiens aboient'); Asked = 'Aboient-ils ?'; Said = 'Oui : Rex et Max aboient.*Rex et Max sont des chiens*' }
            @{ Told = @('Rex et Max sont des chiens', 'tous les chiens aboient'); Asked = 'Rex et Max aboient-ils ?'; Said = 'Oui : Rex et Max aboient.*' }
            @{ Told = @('Rex et Max sont des chiens', 'tous les chiens aboient'); Asked = 'Est-ce que Rex et Max aboient ?'; Said = 'Oui : Rex et Max aboient.*' }
            @{ Told = @('Marie et Paul sont des étudiants', 'tous les étudiants travaillent'); Asked = 'Travaillent-ils ?'; Said = 'Oui : Marie et Paul travaillent.*' }
            @{ Told = @('Rex und Max sind Hunde', 'alle Hunde bellen'); Asked = 'Bellen sie?'; Said = 'Ja. Rex und Max bellen.*' }
            @{ Told = @('Rex und Max sind Hunde', 'alle Hunde bellen'); Asked = 'Bellen Rex und Max?'; Said = 'Ja. Rex und Max bellen.*' }
            @{ Told = @('Rex y Max son perros', 'todos los perros ladran'); Asked = '¿Ellos ladran?'; Said = 'Sí. Rex y Max ladran.*' }
            @{ Told = @('Rex en Max zijn honden', 'alle honden blaffen'); Asked = 'Blaffen Rex en Max?'; Said = 'Ja. Rex en Max blaffen.*' }
            @{ Told = @('Rex e Max são cães', 'todos os cães latem'); Asked = 'Eles latem?'; Said = 'Sim. Rex e Max latem.*' }
            @{ Told = @('Rex e Max sono cani', 'tutti i cani abbaiano'); Asked = 'Essi abbaiano?'; Said = 'Sì. Rex e Max abbaiano.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'says it of each when the answer puts a word of its own: <Asked>' -ForEach @(
            @{ Told = @('Rex and Max are dogs', 'all dogs bark'); Asked = 'do they bark?' }
            @{ Told = @('Rex and Max are dogs', 'all dogs bark'); Asked = 'do Rex and Max bark?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike 'Yes: Rex does bark.*Yes: Max does bark.*'
        }

        It 'says of each what holds of each' {
            Tell 'Rex est un chien', 'Max est un chat', "aucun chat n'est un chien"
            (Ask 'Rex et Max sont-ils des chiens ?') -join ' ' | Should -BeLike 'Oui : Rex*Non, Max*'
        }

        It 'tells of each what is told of them' {
            Tell 'Rex et Max sont des chiens. Ils aboient.'
            (Ask 'Aboient-ils ?') -join ' ' | Should -BeLike 'Oui : Rex et Max aboient.*- Rex aboie.*- Max aboie.*'
        }

        It 'takes the group told last' {
            Tell 'Rex et Max sont des chiens', 'Tom et Felix sont des chats', 'tous les chats miaulent'
            (Ask 'Miaulent-ils ?') -join ' ' | Should -BeLike 'Oui : Tom et Felix miaulent.*'
        }

        It 'stands for no one with no group told, or with a gender none of them has: <Asked>' -ForEach @(
            @{ Told = @('Rex est un chien', 'tous les chiens aboient'); Asked = 'Aboient-ils ?' }
            @{ Told = @('Rex et Max sont des chiens', 'tous les chiens aboient'); Asked = 'Aboient-elles ?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -BeLike 'Oui*'
        }

        It 'does not take one of the group for "il"' {
            Tell 'Rex et Max sont des chiens', 'tous les chiens aboient'
            (Ask 'Aboie-t-il ?') -join ' ' | Should -Not -BeLike 'Oui*'
        }

        It 'does not split what is asked of one with two others: <Asked>' -ForEach @(
            @{ Told = @('Rex likes Tom', 'all dogs bark'); Asked = 'does Rex like Tom and Max?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -BeLike 'Yes*'
        }

        It 'keeps the answer in the shape the checker reads' {
            Tell 'Rex et Max sont des chiens', 'tous les chiens aboient'
            $null = Ask 'Aboient-ils ?'
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -Be @('category(is|name:max|v:aboyer)')
        }
    }

    Context 'The one a sentence is about left unsaid, in the languages that leave it out' {

        It 'asks of the one told of last: <Asked>' -ForEach @(
            @{ Told = @('Rex es un perro', 'todos los perros ladran'); Asked = '¿Ladra?'; Said = 'Sí. Rex ladra.*' }
            @{ Told = @('Rex è un cane', 'tutti i cani abbaiano'); Asked = 'Abbaia?'; Said = 'Sì. Rex abbaia.*' }
            @{ Told = @('Rex é um cão', 'todos os cães latem'); Asked = 'Late?'; Said = 'Sim. Rex late.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'asks of each of the group told last when the verb says several: <Asked>' -ForEach @(
            @{ Told = @('Rex y Max son perros', 'todos los perros ladran'); Asked = '¿Ladran?'; Said = 'Sí. Rex y Max ladran.*' }
            @{ Told = @('Rex e Max sono cani', 'tutti i cani abbaiano'); Asked = 'Abbaiano?'; Said = 'Sì. Rex e Max abbaiano.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'reads it told after one told of in the same message, and asked in it' {
            Tell 'Rex es un perro. Ladra.'
            (Ask '¿Ladra Rex?') -join ' ' | Should -BeLike 'Sí. Rex ladra.*'
            (Ask 'Rex es un perro. Todos los perros ladran. ¿Ladra?') -join ' ' | Should -BeLike 'Sí. Rex ladra.*'
        }

        It 'keeps nothing told so alone, as it may be said to the listener' {
            Tell 'Rex es un perro'
            $null = Ask 'Borra el archivo.'
            $known = & (Get-Module Lambek) { @(Get-LambekCategoryKnown -Language es | ForEach-Object { "$($_.Fact.Text)" }) }
            $known -join ' ' | Should -Not -BeLike '*borra*'
        }

        It 'asks of nobody with two told together, or none told: <Asked>' -ForEach @(
            @{ Told = @('Rex y Max son perros', 'todos los perros ladran'); Asked = '¿Ladra?' }
            @{ Told = @('todos los perros ladran'); Asked = '¿Ladra?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -BeLike 'Sí*'
        }

        It 'does not in a language that writes it: <Asked>' -ForEach @(
            @{ Told = @('Rex is a dog', 'all dogs bark'); Asked = 'barks?'; Yes = 'Yes*' }
            @{ Told = @('Rex est un chien', 'tous les chiens aboient'); Asked = 'aboie ?'; Yes = 'Oui*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -BeLike $Yes
        }

        It 'reads a question whose first word has a capital only because it opens it: <Asked>' -ForEach @(
            @{ Told = @('Rex é um cão', 'todos os cães latem'); Asked = 'Late Rex?'; Said = 'Sim. Rex late.*' }
            @{ Told = @('Rex es un perro', 'todos los perros ladran'); Asked = '¿Ladra Rex?'; Said = 'Sí. Rex ladra.*' }
            @{ Told = @('Rex und Max sind Hunde', 'alle Hunde bellen'); Asked = 'Bellen Rex?'; Said = 'Ja. Rex bellen.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'learns which languages leave it out from their treebanks' {
            & (Get-Module Lambek) { @('fr', 'en', 'de', 'nl') | ForEach-Object { Get-LambekSubjectDropped -Language $_ } } | Should -Not -Contain $true
            & (Get-Module Lambek) { @('es', 'pt', 'it') | ForEach-Object { Get-LambekSubjectDropped -Language $_ } } | Should -Not -Contain $false
        }
    }

    Context 'Several named in a list, "qu ils", and a question told with what it follows from' {

        It 'reads three or more named in a list as each one: <Asked>' -ForEach @(
            @{ Told = @('Rex, Max et Bello sont des chiens', 'tous les chiens aboient'); Asked = 'Aboient-ils ?'; Said = 'Oui : Rex, Max et Bello aboient.*' }
            @{ Told = @('Rex, Max et Bello sont des chiens', 'tous les chiens aboient'); Asked = 'Bello aboie-t-il ?'; Said = 'Oui*Bello aboie*' }
            @{ Told = @('Rex, Max y Bello son perros', 'todos los perros ladran'); Asked = '¿Ladran?'; Said = 'Sí. Rex, Max y Bello ladran.*' }
            @{ Told = @('Rex, Max und Bello sind Hunde', 'alle Hunde bellen'); Asked = 'Bellen sie?'; Said = 'Ja. Rex, Max und Bello bellen.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'keeps a comma after a word that opens the sentence a pause, not a list' {
            & (Get-Module Lambek) { ConvertTo-LambekCategoryList -Text 'Normalement, Rex et Max dorment' -Language fr } | Should -Be 'Normalement, Rex et Max dorment'
            & (Get-Module Lambek) { ConvertTo-LambekCategoryList -Text 'Rex, Max et Bello sont des chiens' -Language fr } | Should -Be 'Rex et Max et Bello sont des chiens'
        }

        It 'reads the pronoun after an apostrophe: <Asked>' -ForEach @(
            @{ Told = @('Marie et Paul sont des étudiants', 'tous les étudiants travaillent'); Asked = "Est-ce qu'ils travaillent ?"; Said = 'Oui : Marie et Paul travaillent.*' }
            @{ Told = @('Marie et Anne sont des étudiantes', 'toutes les étudiantes travaillent'); Asked = "Est-ce qu'elles travaillent ?"; Said = 'Oui : Marie et Anne travaillent.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'answers a question asked in the message that told what it follows from: <Asked>' -ForEach @(
            @{ Asked = 'Rex est un chien. Tous les chiens aboient. Rex aboie-t-il ?'; Said = 'Oui, Rex aboie*' }
            @{ Asked = 'Rex is a dog. All dogs bark. Does Rex bark?'; Said = 'Yes, Rex does bark*' }
        ) {
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'keeps the other sentences as they were when it says the last one plain' {
            & (Get-Module Lambek) { ConvertTo-LambekPlainSentence -Text 'Rex est un chien. Rex aboie-t-il ?' } | Should -Be 'Rex est un chien. est-ce que Rex aboie ?'
        }
    }

    Context 'What someone was told to do, asked again' {

        It 'answers from what was told of each: <Asked>' -ForEach @(
            @{ Told = @('Rex et Max aboient'); Asked = 'Rex aboie-t-il ?'; Said = 'Oui : Rex aboie.*' }
            @{ Told = @("Rex et Max n'aboient pas"); Asked = 'Rex aboie-t-il ?'; Said = "Non : Rex n'aboie pas.*" }
            @{ Told = @('Rex is a dog. Rex barks.'); Asked = 'Does Rex bark?'; Said = 'Yes: Rex does bark.*' }
            @{ Told = @('Rex e Max non abbaiano'); Asked = 'Rex abbaia?'; Said = 'No.*Rex non abbaia*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'says neither yes nor no of what was not told: <Asked>' -ForEach @(
            @{ Told = @('Rex et Max aboient'); Asked = 'Rex dort-il ?' }
            @{ Told = @('Rex is a dog. Rex barks.'); Asked = 'Does Rex sleep?' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -Not -Match '^(Oui|Non|Yes|No)\b'
        }

        It 'says the verb of each in the singular after a word that says not: <Text>' -ForEach @(
            @{ Language = 'fr'; Text = "n'aboient pas"; Said = "n'aboie pas" }
            @{ Language = 'it'; Text = 'non abbaiano'; Said = 'non abbaia' }
        ) {
            & (Get-Module Lambek) { param($t, $l) Get-LambekSingular -Text $t -Language $l -Before 'Max' } $Text $Language | Should -Be $Said
        }
    }

    Context 'A name that ends as a plural does' {

        It 'reads it as one named, never as a kind: <Text>' -ForEach @(
            @{ Language = 'pt'; Text = 'Jonas é um cão'; Key = 'name:jonas' }
            @{ Language = 'de'; Text = 'Lukas ist ein Student'; Key = 'name:lukas' }
            @{ Language = 'en'; Text = 'Thomas is a dog'; Key = 'name:thomas' }
        ) {
            $read = & (Get-Module Lambek) { param($t, $l) Read-LambekCategorySentence -Sentence $t -Language $l } $Text $Language
            $read.Kind | Should -Be 'is'
            $read.Individual.Key | Should -Be $Key
        }

        It 'still reads a plural kind with no article as all of them: <Text>' -ForEach @(
            @{ Language = 'pt'; Text = 'Cães são animais' }
            @{ Language = 'en'; Text = 'Dogs are animals' }
            @{ Language = 'de'; Text = 'Hunde sind Tiere' }
        ) {
            (& (Get-Module Lambek) { param($t, $l) Read-LambekCategorySentence -Sentence $t -Language $l } $Text $Language).Kind | Should -Be 'all'
        }

        It 'reasons about it, alone or told with another: <Asked>' -ForEach @(
            @{ Told = @('Rex e Jonas são cães', 'todos os cães latem'); Asked = 'Jonas late?'; Said = 'Sim*' }
            @{ Told = @('Thomas est un chien', 'tous les chiens aboient'); Asked = 'Thomas aboie-t-il ?'; Said = 'Oui*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }
    }

    Context 'The user asking of himself, and the one an adjective says by its gender' {

        It 'reads the speaker left unsaid where the language leaves him out: <Asked>' -ForEach @(
            @{ Told = @('Soy un estudiante', 'todos los estudiantes trabajan'); Asked = '¿Trabajo?'; Said = 'Sí*' }
            @{ Told = @('Sono uno studente', 'tutti gli studenti lavorano'); Asked = 'Lavoro?'; Said = 'Sì*' }
            @{ Told = @('Sou um estudante', 'todos os estudantes trabalham'); Asked = 'Trabalho?'; Said = 'Sim*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
            $proof = & (Get-Module Lambek) { Get-LambekLastProof }
            $proof.Conclusion | Should -BeLike 'category(is|speaker|*'
        }

        It 'reads a verb the tagger read as a noun next to a pronoun of a person: <Text>' -ForEach @(
            @{ Language = 'it'; Text = 'io lavoro' }
            @{ Language = 'nl'; Text = 'werk ik' }
        ) {
            $read = & (Get-Module Lambek) { param($t, $l) Read-LambekCategorySentence -Sentence $t -Language $l -Question } $Text $Language
            $read.Kind | Should -Be 'askdoes'
            $read.Individual.Key | Should -Be 'speaker'
        }

        It 'takes the one whose gender the adjective agrees with: <Asked>' -ForEach @(
            @{ Told = @('Luna es una gata. Rex es un perro. Todas las gatas son negras.'); Asked = '¿Es negra?'; Said = 'Sí. Luna es negra.*' }
            @{ Told = @('Luna è una gatta. Rex è un cane. Tutte le gatte sono nere.'); Asked = 'È nera?'; Said = 'Sì. Luna è nera.*' }
        ) {
            Tell $Told
            (Ask $Asked) -join ' ' | Should -BeLike $Said
        }

        It 'never takes a verb that may be said of several as said of the user when what follows says one: "Sono uno studente"' {
            Tell 'Sono uno studente'
            $known = & (Get-Module Lambek) { @(Get-LambekCategoryKnown -Language it | ForEach-Object { "$($_.Item.Individual.Key)" }) }
            $known | Should -Contain 'speaker'
        }
    }
}
