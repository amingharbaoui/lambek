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
