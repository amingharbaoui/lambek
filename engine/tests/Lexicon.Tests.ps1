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

    It 'takes the lemma the treebanks met more often, where the tagger guessed one they met seldom' {
        $readings = InModuleScope Lambek { @((Get-LambekFormModel -Language es).ReadText('todos los gatos comen pescado')) }
        $readings[3].Lemma | Should -Be 'comer'
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

        It 'reads a sentence with what was said before it: <Question>' -ForEach @(
            # (the same verb in the rule and in the question, "comen" and "come" both "comer")
            @{ Language = 'es'; Told = 'todos los gatos comen pescado', 'Kiki es un gato'; Question = '¿come Kiki pescado?'; Said = 'Sí. Kiki come pescado.*' }
            # (a plural and its singular, the same lemma: "gatos" and "gato")
            @{ Language = 'pt'; Told = 'todas as rosas são flores', 'todas as flores são plantas', 'Lia é uma rosa'; Question = 'Lia é uma planta?'; Said = 'Sim.*' }
            # (a sentence with no verb read, one word the dictionary gives as one: "blaffen", "late")
            @{ Language = 'nl'; Told = 'alle honden blaffen', 'Bello is een hond'; Question = 'blaft Bello?'; Said = 'Ja. Bello blaft.*' }
            @{ Language = 'pt'; Told = 'nenhum gato late', 'Kiki é um gato'; Question = 'Kiki late?'; Said = 'Não.*' }
            # (a name told before is a name, whatever the tagger guessed)
            @{ Language = 'pt'; Told = 'todos os cães latem', 'Rex é um cão'; Question = 'Rex late?'; Said = 'Sim. Rex late.*' }
            # (what says not as each treebank tags it: "kein", "geen" after the verb, "non")
            @{ Language = 'de'; Told = @('Pip ist kein Vogel'); Question = 'ist Pip ein Vogel?'; Said = 'Nein.*' }
            @{ Language = 'nl'; Told = @('Pip is geen vogel'); Question = 'is Pip een vogel?'; Said = 'Nee.*' }
            @{ Language = 'it'; Told = @('Pip non è un uccello'); Question = 'Pip è un uccello?'; Said = 'No.*' }
        ) {
            # (sent as the app sends them, in the language the user speaks, each conversation a chat of its own)
            $answer = InModuleScope Lambek -Parameters @{ Sentences = @($Told) + @($Question); Language = $Language; Audit = (Join-Path $TestDrive 'audit.jsonl'); Chat = "lexicon-$Question" } {
                param($Sentences, $Language, $Audit, $Chat)
                $id = 0
                $said = $null
                foreach ($sentence in $Sentences) {
                    $id++
                    $line = ConvertTo-Json -InputObject ([ordered]@{ id = $id; method = 'ask'; params = [ordered]@{ text = $sentence; chat = $Chat; incognito = $true; language = $Language } }) -Compress -Depth 5
                    $said = (Invoke-LambekHostRequest -Line $line -AuditPath $Audit | ConvertFrom-Json).result.answer
                }
                $said
            }
            $answer | Should -BeLike $Said
        }
    }
}
