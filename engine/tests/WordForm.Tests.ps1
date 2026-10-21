BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force

    # A tiny treebank, written for the tests: enough to learn a few rules and a few tags
    $script:Tiny = Join-Path $TestDrive 'tiny.conllu'
    $lines = @(
        '# sent_id = 1'
        "1`tElles`til`tPRON`t_`tGender=Fem|Number=Plur|Person=3`t2`tnsubj`t_`t_"
        "2`thabitaient`thabiter`tVERB`t_`tMood=Ind|Number=Plur|Person=3|Tense=Imp`t0`troot`t_`t_"
        "3-4`tau`t_`t_`t_`t_`t_`t_`t_`t_"
        "3`tà`tà`tADP`t_`t_`t5`tcase`t_`t_"
        "4`tle`tle`tDET`t_`tDefinite=Def|Gender=Masc|Number=Sing`t5`tdet`t_`t_"
        "5`tport`tport`tNOUN`t_`tGender=Masc|Number=Sing`t2`tobl`t_`t_"
        ''
        '# sent_id = 2'
        "1`tIls`til`tPRON`t_`tGender=Masc|Number=Plur|Person=3`t2`tnsubj`t_`t_"
        "2`tchantaient`tchanter`tVERB`t_`tMood=Ind|Number=Plur|Person=3|Tense=Imp`t0`troot`t_`t_"
        "3`tl'`tle`tDET`t_`tDefinite=Def|Number=Sing`t4`tdet`t_`t_"
        "4`thymne`thymne`tNOUN`t_`tGender=Masc|Number=Sing`t2`tobj`t_`t_"
        ''
    )
    [IO.File]::WriteAllText($script:Tiny, ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
}

Describe 'Rules of form' {

    It 'gives back the lemma of the form it was read from: <Form> -> <Lemma>' -ForEach @(
        @{ Form = 'habitaient'; Lemma = 'habiter' }
        @{ Form = 'went'; Lemma = 'go' }
        @{ Form = 'Paris'; Lemma = 'Paris' }
        @{ Form = 'Elles'; Lemma = 'il' }
        @{ Form = 'NATO'; Lemma = 'NATO' }
        @{ Form = 'children'; Lemma = 'child' }
    ) {
        [LambekFormRule]::Apply([LambekFormRule]::Of($Form, $Lemma), $Form) | Should -BeExactly $Lemma
    }

    It 'applies a rule learned on one word to another word of the same kind' {
        $rule = [LambekFormRule]::Of('habitaient', 'habiter')
        [LambekFormRule]::Apply($rule, 'dansaient') | Should -BeExactly 'danser'
    }

    It 'does not apply a rule to a form too short for it' {
        [LambekFormRule]::Apply([LambekFormRule]::Of('habitaient', 'habiter'), 'ai') | Should -BeNullOrEmpty
    }
}

Describe 'Learning the forms of words' {

    It 'learns from a treebank, and learns the same model twice, byte for byte' {
        $first = Join-Path $TestDrive 'first.forms.gz'
        $second = Join-Path $TestDrive 'second.forms.gz'
        foreach ($out in $first, $second) {
            $model = [LambekForms]::new()
            $model.Language = 'fr'
            $model.Passes = 3
            $model.LearnTokens([string[]] @($script:Tiny))
            $model.Train([LambekTreebank]::Read($script:Tiny), $null)
            $model.Save($out)
        }
        (Get-FileHash -LiteralPath $first).Hash | Should -Be (Get-FileHash -LiteralPath $second).Hash
    }

    It 'reads again what it learned, after being saved and loaded' {
        $path = Join-Path $TestDrive 'tiny.forms.gz'
        $model = [LambekForms]::new()
        $model.Passes = 5
        $model.LearnTokens([string[]] @($script:Tiny))
        $model.Train([LambekTreebank]::Read($script:Tiny), $null)
        $model.Save($path)
        $loaded = [LambekForms]::Load($path)
        $read = $loaded.Read([string[]] @('Elles', 'habitaient', 'à', 'le', 'port'))
        $read[1].Lemma | Should -BeExactly 'habiter'
        $read[1].Upos | Should -Be 'VERB'
        $read[4].Lemma | Should -BeExactly 'port'
    }

    It 'learns how text is cut into words: contractions and elisions' {
        $model = [LambekForms]::new()
        $model.LearnTokens([string[]] @($script:Tiny))
        $model.Tokenize("Ils chantaient l'hymne au port.") | Should -Be @('Ils', 'chantaient', "l'", 'hymne', 'à', 'le', 'port', '.')
    }
}

Describe 'Get-LambekWordForm' {

    It 'reads a French sentence without a dictionary: <Text>' -ForEach @(
        @{ Text = 'Mes sœurs habitaient à Lyon.'; Word = 'habitaient'; Lemma = 'habiter'; Upos = 'VERB'; Feat = 'Tense=Imp' }
        @{ Text = "Les enfants jouent dans le jardin."; Word = 'enfants'; Lemma = 'enfant'; Upos = 'NOUN'; Feat = 'Number=Plur' }
    ) {
        $word = Get-LambekWordForm -Text $Text -Language fr | Where-Object Form -EQ $Word
        $word.Lemma | Should -BeExactly $Lemma
        $word.Upos | Should -Be $Upos
        $word.Feats | Should -BeLike "*$Feat*"
    }

    It 'reads an English sentence, and an irregular form' {
        $word = Get-LambekWordForm -Text 'The children went home.' -Language en | Where-Object Form -EQ 'went'
        $word.Lemma | Should -BeExactly 'go'
        $word.Upos | Should -Be 'VERB'
    }

    It 'finds the lemma of a verb never seen by analogy with the verbs seen' {
        $word = Get-LambekWordForm -Text 'Vous dormez.' -Language fr | Where-Object Form -EQ 'dormez'
        $word.Known | Should -BeFalse
        $word.Lemma | Should -BeExactly 'dormir'
    }

    It 'cuts du into de le, as the treebanks do' {
        @(Get-LambekWordForm -Text 'le chien du voisin' -Language fr | ForEach-Object Form) | Should -Be @('le', 'chien', 'de', 'le', 'voisin')
    }

    It 'says why it read a word as it did' {
        $word = Get-LambekWordForm -Text 'Ils zorglubaient tout le temps.' -Language fr -Explain | Where-Object Form -EQ 'zorglubaient'
        @($word.Why | Where-Object { $_ -like 'tag: *' }).Count | Should -BeGreaterThan 0
        @($word.Why | Where-Object { $_ -like 'lemma: *' }).Count | Should -BeGreaterThan 0
        @($word.Why | Where-Object { $_ -like '*aient*' }).Count | Should -BeGreaterThan 0
    }

    It 'reads a word it never saw from its ends' {
        $word = Get-LambekWordForm -Text 'Ils zorglubaient tout le temps.' -Language fr | Where-Object Form -EQ 'zorglubaient'
        $word.Known | Should -BeFalse
        $word.Lemma | Should -BeExactly 'zorgluber'
        $word.Upos | Should -Be 'VERB'
    }
}

Describe 'The forms models on the treebanks they never learned from' {

    It 'reads French at least as well as the published baseline, the same way every time' {
        $report = Invoke-LambekFormBenchmark -Path "$PSScriptRoot/../../bench/forms/fr_gsd-ud-test.conllu" -Language fr
        $report.Lemma | Should -BeGreaterOrEqual 0.9797
        $report.Feats | Should -BeGreaterOrEqual 0.9463
        $report.Determinism | Should -Be 1
    }

    It 'reads English' {
        $report = Invoke-LambekFormBenchmark -Path "$PSScriptRoot/../../bench/forms/en_ewt-ud-test.conllu" -Language en
        $report.Lemma | Should -BeGreaterOrEqual 0.96
        $report.Upos | Should -BeGreaterOrEqual 0.93
        $report.Determinism | Should -Be 1
    }
}

Describe 'Reading sentences with the learned forms' {

    BeforeAll {
        Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
        Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
    }

    BeforeEach {
        InModuleScope Lambek {
            $script:Told = $null; $script:Board = $null; $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
            $script:Incognito = $true; $script:CategoryPending = $null; $script:LastProofs = $null; $script:ProblemStores = $null
        }
    }

    AfterAll {
        InModuleScope Lambek { $script:Incognito = $false }
    }

    It 'offers every part of speech a word was seen with, the one read here first' {
        $words = InModuleScope Lambek { Get-LambekSentenceReading -Text 'my brother lives in Paris' -Language en }
        $lemmas = @($words.Lemmas('lives', 'en'))
        $lemmas[0].Pos | Should -Be 'n'
        @($lemmas | Where-Object { $_.Pos -eq 'v' -and $_.Lemma -eq 'live' }).Count | Should -Be 1
    }

    It 'doubts a word never seen when its two readers disagree, and keeps both readings' {
        $reading = @(InModuleScope Lambek { (Get-LambekSentenceReading -Text 'ma sœur zorglube à Lyon' -Language fr).Readings }) | Where-Object Form -EQ 'zorglube'
        $reading.Upos | Should -Be 'VERB'
        $reading.Second | Should -Not -BeNullOrEmpty
    }

    It 'reads what is told with a verb it never saw, the grammar choosing what the word is' {
        New-LambekPlan -Text 'ma sœur zorglube à Lyon' | ConvertTo-LambekAnswer | Should -BeLike "C'est noté*zorglube à Lyon*"
    }

    It 'reads what is told and answers it without any dictionary' {
        InModuleScope Lambek {
            $saved = $script:DictionaryPath
            $script:DictionaryPath = Join-Path $TestDrive 'no-dictionaries'
            try {
                $null = New-LambekPlan -Text 'ma sœur habite à Lyon' | ConvertTo-LambekAnswer
                New-LambekPlan -Text 'où habite ma sœur ?' | ConvertTo-LambekAnswer | Should -BeLike '*sœur habite à Lyon*'
            }
            finally { $script:DictionaryPath = $saved }
        }
    }

    It 'still reads with the dictionaries when asked to, to compare' {
        InModuleScope Lambek {
            $script:WordSource = 'dictionary'
            try { (Get-LambekSentenceReading -Text 'ma sœur habite à Lyon' -Language fr).GetType().Name | Should -Be 'LambekDictionary' }
            finally { $script:WordSource = 'forms' }
        }
    }
}

Describe 'Saying words from what was learned' {

    It 'says a lemma with the features asked: <Lemma> <Wanted> -> <Form>' -ForEach @(
        @{ Lemma = 'prendre'; Upos = 'VERB'; Wanted = 'Mood=Ind|Number=Plur|Person=2|Tense=Pres'; Form = 'prenez' }
        @{ Lemma = 'être'; Upos = 'VERB'; Wanted = 'Mood=Ind|Number=Plur|Person=2|Tense=Pres'; Form = 'êtes' }
        @{ Lemma = 'voler'; Upos = 'VERB'; Wanted = 'Mood=Cnd|Number=Sing|Person=3'; Form = 'volerait' }
        @{ Lemma = 'noir'; Upos = 'ADJ'; Wanted = 'Gender=Fem|Number=Sing'; Form = 'noire' }
    ) {
        $model = InModuleScope Lambek { Get-LambekFormModel -Language fr }
        @($model.Inflect($Lemma, $Upos, $Wanted))[0] | Should -BeExactly $Form
    }

    It 'says by analogy a form it never saw: <Lemma> -> <Form>' -ForEach @(
        # (never seen in the second person plural: the verbs seen in "-ir" that change as it does)
        @{ Lemma = 'réussir'; Wanted = 'Mood=Ind|Number=Plur|Person=2|Tense=Pres'; Form = 'réussissez' }
        @{ Lemma = 'dormir'; Wanted = 'Mood=Ind|Number=Sing|Person=1|Tense=Pres'; Form = 'dors' }
        @{ Lemma = 'zorgluber'; Wanted = 'Mood=Ind|Number=Plur|Person=2|Tense=Pres'; Form = 'zorglubez' }
    ) {
        $model = InModuleScope Lambek { Get-LambekFormModel -Language fr }
        $model.Paradigms.ContainsKey("VERB`t$Lemma`t$Wanted|VerbForm=Fin") | Should -BeFalse
        @($model.Inflect($Lemma, 'VERB', $Wanted))[0] | Should -BeExactly $Form
    }

    It 'finds what a word never seen may be by saying it again' {
        $model = InModuleScope Lambek { Get-LambekFormModel -Language fr }
        $model.Knows('aboient') | Should -BeFalse
        $verb = @($model.Analyze('aboient') | Where-Object Upos -EQ 'VERB')[0]
        $verb.Lemma | Should -BeExactly 'aboyer'
        @($model.Inflect('aboyer', 'VERB', $verb.Feats))[0] | Should -BeExactly 'aboient'
    }

    It 'speaks well enough on the treebank it never learned from' {
        $report = Invoke-LambekFormBenchmark -Path "$PSScriptRoot/../../bench/forms/fr_gsd-ud-test.conllu" -Language fr
        $report.Speak | Should -BeGreaterOrEqual 0.98
        $report.SpeakUnseen | Should -BeGreaterOrEqual 0.9
    }

    It 'offers the words it learned the way the dictionaries offer theirs, in their tags' {
        $words = InModuleScope Lambek { [LambekLearnedWords]::new((Get-LambekFormModel -Language fr), 'fr') }
        $read = @($words.Lemmas('prends', 'fr'))
        @($read | Where-Object { $_.Lemma -eq 'prendre' -and $_.Pos -eq 'v' -and $_.Tag -eq 'P1s' }).Count | Should -Be 1
        @($words.Forms('prendre', 'fr', 'v', 'P2p'))[0] | Should -BeExactly 'prenez'
        @($words.Forms('noir', 'fr', 'a', 'fp'))[0] | Should -BeExactly 'noires'
        $words.Participle('supprimer', 'fr') | Should -BeExactly 'supprimé'
        @($words.Near('capitalle', 'fr', 1)) | Should -Be @('capitale')
    }
}

Describe 'Lambek without its dictionaries' {

    BeforeAll {
        Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
        Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
    }

    BeforeEach {
        InModuleScope Lambek {
            $script:Told = $null; $script:Board = $null; $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
            $script:Incognito = $true; $script:CategoryPending = $null; $script:LastProofs = $null; $script:ProblemStores = $null
            $script:SavedDictionaryPath = $script:DictionaryPath
            $script:DictionaryPath = Join-Path $TestDrive 'no-dictionaries'
        }
    }

    AfterEach {
        InModuleScope Lambek { $script:DictionaryPath = $script:SavedDictionaryPath }
    }

    AfterAll {
        InModuleScope Lambek { $script:Incognito = $false }
    }

    It 'conjugates what it says back for the one it speaks to' {
        $null = New-LambekPlan -Text "s'il pleut, je prends le bus" | ConvertTo-LambekAnswer
        $null = New-LambekPlan -Text 'il pleut' | ConvertTo-LambekAnswer
        New-LambekPlan -Text 'est-ce que je prends le bus ?' | ConvertTo-LambekAnswer | Should -BeLike '*vous prenez le bus*'
    }

    It 'reasons on categories with the words it learned' {
        foreach ($text in 'tous les hommes sont mortels', 'Socrate est un homme') { $null = New-LambekPlan -Text $text | ConvertTo-LambekAnswer }
        New-LambekPlan -Text 'Socrate est-il mortel ?' | ConvertTo-LambekAnswer | Should -BeLike 'Oui*'
    }

    It 'links two forms of a verb it never saw' {
        foreach ($text in 'normalement, les chiens aboient', 'Rex est un chien') { $null = New-LambekPlan -Text $text | ConvertTo-LambekAnswer }
        New-LambekPlan -Text 'Rex aboie-t-il ?' | ConvertTo-LambekAnswer | Should -BeLike 'Normalement oui*'
    }
}

Describe 'Two words the grammar does not know' {

    BeforeAll {
        Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    }

    It 'solves both, and asks only about the one that names the action' {
        $step = (New-LambekPlan -Text 'zorglube les flurps dans C:\Temp').Steps[0]
        $step.Guess.Token | Should -Be 'zorglube'
        $step.Guess.IsAction | Should -BeTrue
        $step.Guess.Also.Token | Should -Be 'flurps'
        @($step.Guess.Also.Types) | Should -Contain 'o'
        $step.Questions[0] | Should -BeLike '*zorglube*:*'
    }
}

Describe 'Reading a message once' {

    It 'reads the same sentence once in a message, and again in the next' {
        InModuleScope Lambek {
            Clear-LambekReadCache
            $first = ConvertTo-LambekRequest -Text 'liste les fichiers dans C:\Temp'
            $second = ConvertTo-LambekRequest -Text 'liste les fichiers dans C:\Temp'
            $second.Hash | Should -Be $first.Hash
            # (a copy: what a reader adds to its request is not added to the one kept)
            $second | Add-Member -NotePropertyName Extra -NotePropertyValue 1
            (ConvertTo-LambekRequest -Text 'liste les fichiers dans C:\Temp').PSObject.Properties['Extra'] | Should -BeNullOrEmpty
            $script:ReadCache.Count | Should -BeGreaterThan 0
            $null = New-LambekPlan -Text 'bonjour'
            $script:ReadCache.ContainsKey("request`nauto`nliste les fichiers dans C:\Temp") | Should -BeFalse
        }
    }
}
