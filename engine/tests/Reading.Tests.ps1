BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    $script:French = [LambekForms]::Load((Resolve-Path "$PSScriptRoot/../Lambek/Data/Forms/fr.forms.gz").Path)

    # Two bzip2 streams one after the other, as the multistream dumps are: "Bonjour Lambek." three times, then "Deux flux."
    $script:Bzip2 = 'QlpoOTFBWSZTWbusdEQAAAXVgAAQQAEQBDIbkgAgACM/9VR6jIeIKYAA6W/Q7YS+UlK1LaQ2LuSKcKEhd1joiEJaaDkxQVkmU1nM8IvTAAAB1YAAEEABBAADBAJAIAAho0000IMmIMBSb6DxdyRThQkMzwi9MA=='

    function Read-TestBzip2 {
        param([byte[]] $Bytes)
        $reader = [LambekBzip2Reader]::new([IO.MemoryStream]::new($Bytes))
        $text = [IO.StreamReader]::new($reader, [Text.Encoding]::UTF8)
        try { return $text.ReadToEnd() } finally { $text.Dispose() }
    }

    # Plain text where a word the treebanks never had comes back in many sentences
    function New-TestText {
        param([int] $Times)
        $sentences = foreach ($i in 1..$Times) {
            "Le cerisier du jardin donne des fruits en juin."
            "Les cerisiers de la colline sont en fleurs."
        }
        return [string[]] @($sentences)
    }
}

Describe 'Reading bzip2' {

    It 'reads every stream of a multistream file' {
        Read-TestBzip2 -Bytes ([Convert]::FromBase64String($script:Bzip2)) | Should -BeExactly ("Bonjour Lambek.`n" * 3 + "Deux flux.`n")
    }

    It 'refuses a block that does not match its CRC' {
        $bytes = [Convert]::FromBase64String($script:Bzip2)
        # (the CRC of the first block, right after its magic number)
        $bytes[10] = $bytes[10] -bxor 0xFF
        { Read-TestBzip2 -Bytes $bytes } | Should -Throw '*bzip2*'
    }
}

Describe 'Words learned from plain text' {

    It 'writes down a word read the same way in many sentences, with its lemma and gender' {
        $reader = [LambekSelfReader]::new($script:French)
        $reader.Read('test', [string[]] (New-TestText -Times 4))
        $words = @($reader.Decide())
        $tree = $words | Where-Object Form -EQ 'cerisier'
        $tree.Upos | Should -Be 'NOUN'
        $tree.Lemma | Should -BeExactly 'cerisier'
        $tree.Feats | Should -BeLike '*Gender=Masc*'
        ($words | Where-Object Form -EQ 'cerisiers').Lemma | Should -BeExactly 'cerisier'
        $tree.Sources | Should -Be 'test:4'
    }

    It 'writes nothing down from too few sentences, nor a name' {
        $reader = [LambekSelfReader]::new($script:French)
        $reader.Read('test', [string[]] (@(New-TestText -Times 1) + @(foreach ($i in 1..5) { 'Hier, Zorblax est venu me voir.' })))
        @($reader.Decide()).Count | Should -Be 0
    }

    It 'says a word again before writing it down, and takes the lemma that says it back' {
        $reader = [LambekSelfReader]::new($script:French)
        $wrong = [LambekLearnedWord]@{ Form = 'mangeons'; Upos = 'VERB'; Lemma = 'boire'; Feats = 'Mood=Ind|Number=Plur|Person=1|Tense=Pres|VerbForm=Fin'; Count = 5; Agreeing = 5; Sources = 'test:5'; Why = 'lemma known' }
        $kept = @($reader.Confirm([LambekLearnedWord[]] @($wrong)))
        $kept.Count | Should -Be 1
        $kept[0].Lemma | Should -BeExactly 'manger'
        $kept[0].Why | Should -Be 'said again'
    }

    It 'does not change what the forms model reads while it reads' {
        $before = $script:French.SecondReader
        $reader = [LambekSelfReader]::new($script:French)
        $reader.Read('test', [string[]] (New-TestText -Times 1))
        $script:French.SecondReader | Should -Be $before
    }

    It 'keeps the notebook in a file and reads it back as it was' {
        $reader = [LambekSelfReader]::new($script:French)
        $reader.Read('test', [string[]] (New-TestText -Times 4))
        $words = @($reader.Decide())
        $path = Join-Path $TestDrive 'fr.learned.gz'
        [LambekSelfReader]::Write($path, [LambekLearnedWord[]] $words, 'test')
        $back = @([LambekSelfReader]::Load($path))
        $back.Count | Should -Be $words.Count
        ($back | ForEach-Object { "$($_.Form) $($_.Upos) $($_.Lemma) $($_.Feats) $($_.Count) $($_.Why)" }) -join ';' |
            Should -BeExactly (($words | ForEach-Object { "$($_.Form) $($_.Upos) $($_.Lemma) $($_.Feats) $($_.Count) $($_.Why)" }) -join ';')
    }

    It 'reads with what it learned, and forgets it when asked' {
        $model = [LambekForms]::Load((Resolve-Path "$PSScriptRoot/../Lambek/Data/Forms/fr.forms.gz").Path)
        $word = [LambekLearnedWord]@{ Form = 'blorpette'; Upos = 'NOUN'; Lemma = 'blorpette'; Feats = 'Gender=Fem|Number=Sing'; Count = 9; Agreeing = 9; Sources = 'test:9'; Why = 'own lemma' }
        $model.AddLearned([LambekLearnedWord[]] @($word))
        $read = $model.ReadText('Elle range la blorpette.')
        ($read | Where-Object Form -EQ 'blorpette').Upos | Should -Be 'NOUN'
        $model.KnowsLemma('blorpette') | Should -BeTrue
        $model.ClearLearned()
        $model.KnowsLemma('blorpette') | Should -BeFalse
        $model.Learned.Count | Should -Be 0
    }
}

Describe 'The forms model read from its file' {

    It 'is saved again byte for byte after being loaded' {
        $tiny = Join-Path $TestDrive 'tiny.conllu'
        $lines = @(
            "1`tElles`til`tPRON`t_`tGender=Fem|Number=Plur|Person=3`t2`tnsubj`t_`t_"
            "2`thabitaient`thabiter`tVERB`t_`tMood=Ind|Number=Plur|Person=3|Tense=Imp`t0`troot`t_`t_"
            "3`tici`tici`tADV`t_`t_`t2`tadvmod`t_`t_"
            ''
        )
        [IO.File]::WriteAllText($tiny, ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
        $model = [LambekForms]::new()
        $model.Passes = 3
        $model.LearnTokens([string[]] @($tiny))
        $model.Train([LambekTreebank]::Read($tiny), $null)
        $first = Join-Path $TestDrive 'first.forms.gz'
        $again = Join-Path $TestDrive 'again.forms.gz'
        $model.Save($first)
        [LambekForms]::Load($first).Save($again)
        (Get-FileHash -LiteralPath $again).Hash | Should -Be (Get-FileHash -LiteralPath $first).Hash
    }

    It 'reads a verb seen only as a noun with the lemma of the verb: <Text>' -ForEach @(
        @{ Text = 'je bois un café'; Form = 'bois'; Lemma = 'boire' }
        @{ Text = 'quand je suis fatigué, je bois un café'; Form = 'bois'; Lemma = 'boire' }
    ) {
        ($script:French.ReadText($Text) | Where-Object Form -EQ $Form).Lemma | Should -BeExactly $Lemma
    }
}
