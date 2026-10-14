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

Describe 'Worlds imagined with et si' {

    BeforeEach {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
    }
    AfterAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
    }

    It 'says what would change, in the conditional, and changes nothing told' {
        Tell 'normalement, les oiseaux volent', 'les pingouins ne volent pas', 'tous les pingouins sont des oiseaux', 'Tweety est un oiseau'
        Ask 'et si Tweety était un pingouin ?' | Should -Be (@(
                'Dans ce monde imaginé (Tweety était un pingouin) :'
                '- Tweety ne volerait pas.'
                "Ce n'est qu'un monde imaginé : ce que vous m'avez dit ne change pas."
            ) -join "`n")
        @((Ask 'Tweety vole-t-il ?') -split "`n")[0] | Should -Be "Normalement oui, Tweety vole : c'est un oiseau et normalement, les oiseaux volent."
    }

    It 'answers a question asked in the world imagined, with what it rests on' {
        Tell 'les pingouins ne volent pas', 'tous les pingouins sont des oiseaux', 'Tweety est un oiseau'
        Ask "et si Tweety était un pingouin, est-ce qu'il volerait ?" | Should -Be (@(
                'Dans ce monde imaginé (Tweety était un pingouin) :'
                'Non : Tweety ne volerait pas.'
                "Parce que vous m'avez dit :"
                '- Les pingouins ne volent pas.'
                '- Tweety était un pingouin (imaginé)'
                "Ce n'est qu'un monde imaginé : ce que vous m'avez dit ne change pas."
            ) -join "`n")
    }

    It 'sets aside what contradicts what is imagined, and says it' {
        Tell 'tous les chats sont noirs', 'Minou est un chat'
        $lines = @((Ask "et si Minou n'était pas noir ?") -split "`n")
        $lines[1..2] | Should -Be @("Pour l'imaginer, je mets de côté ce qui le contredit :", '- Minou est un chat.')
        $lines | Should -Contain '- Minou ne serait pas un chat.'
        Ask 'Minou est-il noir ?' | Should -Be "Oui, Minou est noir, car c'est un chat et tous les chats sont noirs."
    }

    It 'imagines about the user' {
        Tell 'tous les hommes sont mortels'
        @((Ask "et si j'étais un homme ?") -split "`n")[1] | Should -Be '- vous seriez mortel.'
    }

    It 'follows the rules told with si in the world imagined' {
        Tell "s'il pleut, je prends le bus", "s'il pleut, la route est mouillée", 'il ne pleut pas'
        Ask "et s'il pleuvait ?" | Should -Be (@(
                'Dans ce monde imaginé (il pleuvait) :'
                "Pour l'imaginer, je mets de côté ce qui le contredit :"
                '- Il ne pleut pas.'
                "Ce qui en suivrait, d'après les règles que vous m'avez dites :"
                '- Vous prenez le bus.'
                '- La route est mouillée.'
                "Ce n'est qu'un monde imaginé : ce que vous m'avez dit ne change pas."
            ) -join "`n")
        Ask 'est-ce qu''il pleut ?' | Should -Not -BeLike '*Il pleut.*'
    }

    It 'imagines in English' {
        Tell 'Birds normally fly.', 'Penguins do not fly.', 'All penguins are birds.', 'Tweety is a bird.'
        @((Ask 'What if Tweety were a penguin, would he fly?') -split "`n")[1] | Should -Be 'No: Tweety would not fly.'
    }

    It 'leaves a rule told with a plain si to the rest of Lambek' {
        Tell "s'il pleut, je prends le bus"
        Ask "s'il pleut, est-ce que je prends le bus ?" | Should -Not -BeLike 'Dans ce monde imaginé*'
    }
}
