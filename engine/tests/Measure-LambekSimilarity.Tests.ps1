BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
}

Describe 'Measure-LambekSimilarity' {

    BeforeAll {
        $request = ConvertTo-LambekRequest 'delet the old fils'
    }

    It 'scores a close phrase higher than an unrelated one' {
        $close = Measure-LambekSimilarity -Request $request -Reference 'delete old files'
        $far = Measure-LambekSimilarity -Request $request -Reference 'restart the network adapter'

        $close.EditSimilarity | Should -BeGreaterThan $far.EditSimilarity
        $close.NGramJaccard | Should -BeGreaterThan $far.NGramJaccard
        $close.Cosine | Should -BeGreaterThan $far.Cosine
    }

    It 'keeps every score between 0 and 1' {
        $result = Measure-LambekSimilarity -Request $request -Reference 'delete old files'

        foreach ($score in $result.EditSimilarity, $result.WordJaccard, $result.NGramJaccard, $result.Cosine) {
            $score | Should -BeGreaterOrEqual 0
            $score | Should -BeLessOrEqual 1
        }
    }

    It 'gives 1 for the same phrase' {
        $same = ConvertTo-LambekRequest 'delete old files'
        $result = Measure-LambekSimilarity -Request $same -Reference 'delete old files'

        $result.EditSimilarity | Should -Be 1
        $result.WordJaccard | Should -Be 1
        $result.Cosine | Should -Be 1
    }

    It 'uses a corpus when one is given' {
        $corpus = 'delete old files', 'copy files', 'stop the service'
        $result = Measure-LambekSimilarity -Request $request -Reference 'delete old files' -Corpus $corpus

        $result.Cosine | Should -BeGreaterThan 0
    }

    It 'gives the same result every time' {
        $first = Measure-LambekSimilarity -Request $request -Reference 'delete old files'
        $second = Measure-LambekSimilarity -Request $request -Reference 'delete old files'

        ($first | ConvertTo-Json) | Should -Be ($second | ConvertTo-Json)
    }
}
