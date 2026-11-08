BeforeAll {
    $env:LAMBEK_DATA = Join-Path $TestDrive 'data'
    Import-Module (Join-Path $PSScriptRoot '../Lambek/Lambek.psd1') -Force
    function Tell {
        param([string[]] $Sentences)
        foreach ($sentence in $Sentences) { $null = New-LambekPlan -Text $sentence }
    }
    function Ask {
        param([string] $Question)
        (New-LambekPlan -Text $Question | ConvertTo-LambekAnswer) -join "`n"
    }
}

Describe 'A dialogue learned, not written' {

    BeforeEach {
        InModuleScope Lambek { Clear-LambekTold; $script:Told = $null }
    }

    # The languages with no dialogue written for them talk with the one learned from their treebanks and from sentences
    # translated from English (tools/Learn-LambekDialogue.ps1): told rules and facts, then asked
    It 'reasons in <Language>: <Question>' -ForEach @(
        @{ Language = 'de'; Told = 'jeder Hund ist ein Tier', 'Rex ist ein Hund'; Question = 'ist Rex ein Tier?'; Said = "Ja. Rex ist ein Tier.*- jeder Hund ist ein Tier*- Rex ist ein Hund*" }
        @{ Language = 'de'; Told = 'kein Fisch ist ein Säugetier', 'Nemo ist ein Fisch'; Question = 'ist Nemo ein Säugetier?'; Said = 'Nein.*- kein Fisch ist ein Säugetier*' }
        @{ Language = 'de'; Told = 'alle Hunde bellen', 'Rex ist ein Hund'; Question = 'bellt Rex?'; Said = 'Ja. Rex bellt.*' }
        @{ Language = 'de'; Told = 'Rex ist ein Hund', 'jeder Hund ist ein Tier'; Question = 'ist Rex ein Tier?'; Said = 'Ja. Rex ist ein Tier.*' }
        @{ Language = 'es'; Told = 'todos los perros son animales', 'Rex es un perro'; Question = '¿es Rex un animal?'; Said = 'Sí. Rex es un animal.*' }
        @{ Language = 'es'; Told = 'ningún pez es un mamífero', 'Nemo es un pez'; Question = '¿es Nemo un mamífero?'; Said = 'No.*' }
        @{ Language = 'nl'; Told = 'elke hond is een dier', 'Rex is een hond'; Question = 'is Rex een dier?'; Said = 'Ja. Rex is een dier.*' }
        @{ Language = 'nl'; Told = 'geen vis is een zoogdier', 'Nemo is een vis'; Question = 'is Nemo een zoogdier?'; Said = 'Nee.*' }
        @{ Language = 'pt'; Told = 'todos os cães são animais', 'Rex é um cão'; Question = 'Rex é um animal?'; Said = 'Sim. Rex é um animal.*' }
        @{ Language = 'pt'; Told = 'nenhum peixe é um mamífero', 'Nemo é um peixe'; Question = 'Nemo é um mamífero?'; Said = 'Não.*' }
        @{ Language = 'it'; Told = 'ogni cane è un animale', 'Rex è un cane'; Question = 'Rex è un animale?'; Said = 'Sì. Rex è un animale.*' }
        @{ Language = 'it'; Told = 'tutti i cani mangiano carne', 'Rex è un cane'; Question = 'Rex mangia carne?'; Said = 'Sì. Rex mangia carne.*' }
    ) {
        Tell $Told
        Ask $Question | Should -BeLike $Said
    }

    It 'does not know what it was not told: <Question>' -ForEach @(
        @{ Told = 'Rex ist ein Hund'; Question = 'ist Rex ein Tier?'; Said = 'Ich weiß nicht.' }
        @{ Told = 'Rex es un perro'; Question = '¿es Rex un animal?'; Said = 'No sé.' }
    ) {
        Tell $Told
        Ask $Question | Should -Be $Said
    }

    It 'has its small words learned in <Language>' -ForEach @(
        @{ Language = 'de'; Article = 'ein'; Of = 'von'; Speaker = 'ich'; Yes = 'Ja.' }
        @{ Language = 'es'; Article = 'un'; Of = 'de'; Speaker = 'yo'; Yes = 'Sí.' }
        @{ Language = 'nl'; Article = 'een'; Of = 'van'; Speaker = 'ik'; Yes = 'Ja.' }
        @{ Language = 'pt'; Article = 'um'; Of = 'de'; Speaker = 'eu'; Yes = 'Sim.' }
        @{ Language = 'it'; Article = 'un'; Of = 'di'; Speaker = 'io'; Yes = 'Sì.' }
    ) {
        $dialogue = InModuleScope Lambek -Parameters $_ { param($Language) (Get-LambekLexicon -Language $Language).Dialogue }
        $dialogue['Learned'] | Should -BeTrue
        $dialogue['Categories']['Articles'] | Should -Contain $Article
        $dialogue['Categories']['Of'] | Should -Contain $Of
        $dialogue['Categories']['Speaker'] | Should -Contain $Speaker
        $dialogue['Categories']['YesShort'] | Should -Be $Yes
    }

    It 'tells a language by the words its forms hold when the small words tie' {
        InModuleScope Lambek {
            $tokens = Get-LambekLanguageToken -Text 'Rex es un perro'
            Get-LambekLanguage -Tokens $tokens -Forms | Should -Be 'es'
        }
    }

    It 'tells a language by how often its treebanks write the words, whatever one small word says: <Text>' -ForEach @(
        # ("come" is a small word of Italian; "ningun", "perro", "hierba" are written in Spanish)
        @{ Text = 'ningún perro come hierba'; Language = 'es'; Chat = $null }
        # (a close call is the chat's: "bellen" is also Dutch)
        @{ Text = 'alle Hunde bellen'; Language = 'de'; Chat = 'de' }
        @{ Text = 'nenhum cão come erva'; Language = 'pt'; Chat = 'pt' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text; Chat = $Chat } {
            param($Text, $Chat)
            $script:LanguageHint = $Chat
            try { Get-LambekLanguage -Tokens (Get-LambekLanguageToken -Text $Text) -Text $Text -Forms }
            finally { $script:LanguageHint = $null }
        } | Should -Be $Language
    }

    It 'learns which translation to say, and a word met where English says it' {
        $english = [string[]] @('No.', 'No.', 'a friend of mine', 'the end of it', 'a box full of toys', 'Hello.')
        $other = [string[]] @('Noe.', 'Nein.', 'ein Freund von mir', 'das Ende von ihm', 'eine Kiste voller Spielzeug', 'Nein, hallo.')
        [LambekDialogueWords]::Phrase($english, $other, 'No.') | Should -Be 'Nein.'
        [LambekDialogueWords]::Aligned($english, $other, 'of', [string[]] @('von', 'voller', 'mir'), 1, 12) | Should -Be 'von'
    }
}
