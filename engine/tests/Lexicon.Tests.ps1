BeforeAll {
    $env:LAMBEK_DATA = Join-Path $TestDrive 'data'
    Import-Module (Join-Path $PSScriptRoot '../Lambek/Lambek.psd1') -Force
    Import-LambekPack -Path (Join-Path $PSScriptRoot '../../dsl/files') | Out-Null
    function Tell {
        param([string[]] $Sentences)
        foreach ($sentence in $Sentences) { $null = New-LambekPlan -Text $sentence }
    }
    function Ask {
        param([string] $Question)
        (New-LambekPlan -Text $Question | ConvertTo-LambekAnswer) -join "`n"
    }
    function New-Raw {
        param([string] $Kind, [string] $Form, [string] $Lemma, [string] $Pos, [string[]] $Tags)
        $raw = [LambekLexicon+Raw]::new()
        $raw.Kind = $Kind; $raw.Form = $Form; $raw.Lemma = $Lemma; $raw.Pos = $Pos; $raw.Tags = [string[]] @($Tags)
        $raw
    }
}

Describe 'The words of a language as Wiktionary says them' {

    It 'learns how the names of Wiktionary turn into the tags of the treebanks, and leaves out the words it cannot turn' {
        $raws = [System.Collections.Generic.List[LambekLexicon+Raw]]::new()
        $words = [System.Collections.Generic.List[LambekTreebankWord[]]]::new()
        for ($i = 0; $i -lt 40; $i++) {
            $raws.Add((New-Raw 'head' "chat$i" "chat$i" 'noun' @()))
            $raws.Add((New-Raw 'of' "chats$i" "chat$i" 'noun' @('form-of', 'plural')))
            $raws.Add((New-Raw 'of' "chatte$i" "chat$i" 'noun' @('feminine', 'form-of')))
            $raws.Add((New-Raw 'table' "chaton$i" "chat$i" 'noun' @('diminutive')))
            $one = [LambekTreebankWord]::new(); $one.Form = "chat$i"; $one.Lemma = "chat$i"; $one.Upos = 'NOUN'; $one.Feats = 'Number=Sing'
            $many = [LambekTreebankWord]::new(); $many.Form = "chats$i"; $many.Lemma = "chat$i"; $many.Upos = 'NOUN'; $many.Feats = 'Number=Plur'
            $small = [LambekTreebankWord]::new(); $small.Form = "chaton$i"; $small.Lemma = "chaton$i"; $small.Upos = 'NOUN'; $small.Feats = 'Number=Sing'
            $she = [LambekTreebankWord]::new(); $she.Form = "chatte$i"; $she.Lemma = "chat$i"; $she.Upos = 'NOUN'; $she.Feats = 'Gender=Fem|Number=Sing'
            $words.Add([LambekTreebankWord[]] @($one, $many, $small, $she))
        }
        $languages = [System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[System.Collections.Generic.List[LambekLexicon+Raw], System.Collections.Generic.List[LambekTreebankWord[]]]]]::new()
        $languages.Add([System.Collections.Generic.KeyValuePair[System.Collections.Generic.List[LambekLexicon+Raw], System.Collections.Generic.List[LambekTreebankWord[]]]]::new($raws, $words))
        $mapping = [LambekLexicon]::Learn($languages, 30)
        $mapping.Pos['noun'] | Should -Be 'NOUN'
        $mapping.Tags['plural'] | Should -Be 'Number=Plur'
        $mapping.Tags['feminine'] | Should -Be 'Gender=Fem'
        $mapping.Neutral | Should -Contain 'form-of'
        $mapping.Neutral | Should -Not -Contain 'diminutive'
        $attested = [System.Collections.Generic.HashSet[string]]::new([string[]] @('chats1', 'chaton1', 'chat1'), [StringComparer]::Ordinal)
        $lexicon = [LambekLexicon]::Build($raws, $mapping, $attested)
        $entries = $null
        $lexicon.TryGet('chats1', [ref] $entries) | Should -BeTrue
        $entries[0].Lemma | Should -Be 'chat1'
        $entries[0].Feats | Should -Be 'Number=Plur'
        $lexicon.TryGet('chaton1', [ref] $entries) | Should -BeFalse
        $lexicon.TryGet('chats2', [ref] $entries) | Should -BeFalse
    }

    It 'reads a word the treebanks never met as the lexicon says it' {
        $readings = InModuleScope Lambek { @((Get-LambekFormModel -Language it).ReadText('tutti i cani abbaiano')) }
        $readings[3].Upos | Should -Be 'VERB'
        $readings[3].Lemma | Should -Be 'abbaiare'
    }

    It 'keeps the lemma the treebanks name a word with, where the lexicon names it otherwise' {
        $readings = InModuleScope Lambek { @((Get-LambekFormModel -Language fr).ReadText('le chat mange')) }
        $readings[2].Lemma | Should -Be 'manger'
    }

    Context 'Reasoning with the words learned' {

        BeforeEach {
            InModuleScope Lambek { Clear-LambekTold; $script:Told = $null }
        }

        It 'reasons about a verb the treebanks never met: <Question>' -ForEach @(
            @{ Told = 'tutti i cani abbaiano', 'Rex è un cane'; Question = 'Rex abbaia?'; Said = 'Sì. Rex abbaia.*' }
            @{ Told = 'alle Hunde fressen Fleisch', 'Rex ist ein Hund'; Question = 'frisst Rex Fleisch?'; Said = 'Ja. Rex frisst Fleisch.*' }
            @{ Told = 'todos los perros ladran', 'Rex es un perro'; Question = '¿ladra Rex?'; Said = 'Sí. Rex ladra.*' }
        ) {
            Tell $Told
            Ask $Question | Should -BeLike $Said
        }
    }
}
