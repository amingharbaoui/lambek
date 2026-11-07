BeforeAll {
    $env:LAMBEK_DATA = Join-Path $TestDrive 'data'
    Import-Module (Join-Path $PSScriptRoot '../Lambek/Lambek.psd1') -Force
    $script:English = @(
        'the dog eats', 'the cat eats', 'a dog sleeps', 'a cat sleeps', 'the dog sleeps', 'the cat runs', 'a dog runs',
        'the bird eats', 'a bird sleeps', 'the bird runs'
    )
    $script:Italian = @(
        'il cane mangia', 'il gatto mangia', 'un cane dorme', 'un gatto dorme', 'il cane dorme', 'il gatto corre', 'un cane corre',
        "l'uccello mangia", "un uccello dorme", "l'uccello corre"
    )
}

Describe 'Which word says what an English word says' {

    It 'learns the words of a language from sentences translated from English, both ways' {
        $aligner = [LambekAligner]::new([string[]] $script:English, [string[]] $script:Italian, 12)
        $aligner.Train(5)
        $aligner.Translations('dog', 2, 1)[0].Key | Should -Be 'cane'
        $aligner.Translations('sleeps', 2, 1)[0].Key | Should -Be 'dorme'
        $aligner.Translations('the', 2, 1)[0].Key | Should -Be 'il'
    }

    It 'links each word of a pair to the English word it says' {
        $english = [System.Collections.Generic.List[string[]]]::new()
        $italian = [System.Collections.Generic.List[string[]]]::new()
        for ($i = 0; $i -lt 7; $i++) { $english.Add([string[]] $script:English[$i].Split(' ')); $italian.Add([string[]] $script:Italian[$i].Split(' ')) }
        $aligner = [LambekAligner]::new($english, $italian)
        $aligner.Train(5)
        # "un cane dorme": a dog sleeps
        $aligner.Links(2) | Should -Be @(0, 1, 2)
    }

    It 'gives the same table from the same sentences, every time' {
        $one = [LambekAligner]::new([string[]] $script:English, [string[]] $script:Italian, 12)
        $two = [LambekAligner]::new([string[]] $script:English, [string[]] $script:Italian, 12)
        $one.Train(5); $two.Train(5)
        foreach ($word in 'the', 'a', 'dog', 'cat', 'bird', 'eats', 'sleeps', 'runs') {
            ($one.Translations($word, 1, 3) | ForEach-Object { "$($_.Key) $($_.Value.ToString('R'))" }) -join ';' |
                Should -Be (($two.Translations($word, 1, 3) | ForEach-Object { "$($_.Key) $($_.Value.ToString('R'))" }) -join ';')
        }
    }
}

Describe 'More sentences for a language, confirmed by English' {

    It 'keeps the sentences English confirms, with a word the treebanks never met, and learns what carries over right' {
        $result = InModuleScope Lambek -Parameters @{ English = $script:English; Italian = $script:Italian } {
            param($English, $Italian)
            $sides = @(); $translations = @()
            for ($i = 0; $i -lt 30; $i++) { $sides += $English; $translations += $Italian }
            [LambekProjection]::Project((Get-LambekFormModel -Language en), (Get-LambekFormModel -Language it), [string[]] $sides, [string[]] $translations, 12, 5, 0.9, 0.6, 10)
        }
        $result.Pairs | Should -Be 300
        # ("il", "un": what the treebanks know as determiners, carried over from "the", "a")
        $result.Trust['DET'] | Should -Be 1
        # ("cane" the treebanks never met, "dog" a noun, as the model reads it)
        @($result.Sentences | ForEach-Object { ($_ | ForEach-Object { "$($_.Form)/$($_.Upos)" }) -join ' ' }) | Should -Contain 'un/DET cane/NOUN dorme/VERB'
        foreach ($sentence in $result.Sentences) {
            $sentence.Count | Should -BeGreaterThan 0
            ($sentence | Where-Object Upos -NotIn 'NOUN', 'VERB', 'DET', 'PROPN', 'ADJ', 'ADV', 'PRON', 'AUX', 'PUNCT', 'ADP', 'NUM', 'CCONJ', 'SCONJ', 'INTJ', 'PART', 'SYM', 'X') | Should -BeNullOrEmpty
        }
        $result.Sentences.Count + $result.Refused + $result.Unsure + $result.Known | Should -Be 300
    }
}
