BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
}

Describe 'Measure-LambekEditDistance' {

    It 'returns <Expected> for <Source> and <Target>' -ForEach @(
        @{ Source = 'kitten'; Target = 'sitting'; Expected = 3 }
        @{ Source = 'ca'; Target = 'ac'; Expected = 1 }
        @{ Source = ''; Target = 'abc'; Expected = 3 }
        @{ Source = 'same'; Target = 'same'; Expected = 0 }
    ) {
        InModuleScope Lambek -Parameters $_ {
            (Measure-LambekEditDistance -Source $Source -Target $Target).Distance | Should -Be $Expected
        }
    }

    It 'gives a similarity of 1 for equal words' {
        InModuleScope Lambek {
            (Measure-LambekEditDistance -Source 'file' -Target 'file').Similarity | Should -Be 1
        }
    }
}

Describe 'Measure-LambekJaccard' {

    It 'returns 0.5 for {a,b,c} and {b,c,d}' {
        InModuleScope Lambek {
            Measure-LambekJaccard -SetA 'a', 'b', 'c' -SetB 'b', 'c', 'd' | Should -Be 0.5
        }
    }

    It 'returns 1 for two empty sets' {
        InModuleScope Lambek {
            Measure-LambekJaccard -SetA @() -SetB @() | Should -Be 1
        }
    }

    It 'returns 0 for sets with nothing in common' {
        InModuleScope Lambek {
            Measure-LambekJaccard -SetA 'a' -SetB 'b' | Should -Be 0
        }
    }
}

Describe 'Measure-LambekCosine' {

    It 'returns 1 for the same vector' {
        InModuleScope Lambek {
            $vector = @{ x = 1.0; y = 2.0 }
            [math]::Round((Measure-LambekCosine -VectorA $vector -VectorB $vector), 10) | Should -Be 1
        }
    }

    It 'returns 0 for orthogonal vectors' {
        InModuleScope Lambek {
            Measure-LambekCosine -VectorA @{ x = 1.0 } -VectorB @{ y = 1.0 } | Should -Be 0
        }
    }

    It 'returns 0 for an empty vector' {
        InModuleScope Lambek {
            Measure-LambekCosine -VectorA @{} -VectorB @{ y = 1.0 } | Should -Be 0
        }
    }
}

Describe 'TF-IDF' {

    It 'gives a rare term a higher weight than a common one' {
        InModuleScope Lambek {
            $documents = @(
                , @('file', 'delete')
                , @('file', 'copy')
                , @('file', 'move')
            )
            $model = ConvertTo-LambekTfIdfModel -Documents $documents

            $model.Idf['delete'] | Should -BeGreaterThan $model.Idf['file']
        }
    }
}

Describe 'Get-LambekHash' {

    It 'matches the official SHA-256 of "abc"' {
        InModuleScope Lambek {
            Get-LambekHash -Text 'abc' | Should -Be 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        }
    }
}

Describe 'Get-LambekCharNGram' {

    It 'pads words with #' {
        InModuleScope Lambek {
            $nGrams = Get-LambekCharNGram -Terms 'file'
            $nGrams | Should -Be @('#fi', 'fil', 'ile', 'le#')
        }
    }
}

Describe 'Pregroup types' {

    It 'reads <Text> as order <Order>' -ForEach @(
        @{ Text = 'o'; Order = 0 }
        @{ Text = 'o^l'; Order = -1 }
        @{ Text = 'o^r'; Order = 1 }
        @{ Text = 'o^ll'; Order = -2 }
        @{ Text = 'o^rr'; Order = 2 }
    ) {
        InModuleScope Lambek -Parameters $_ {
            (ConvertFrom-LambekType -Type $Text).Order | Should -Be $Order
        }
    }

    It 'writes a type back the same way' {
        InModuleScope Lambek {
            Format-LambekType -SimpleTypes (ConvertFrom-LambekType -Type 's p^l o^rr') | Should -Be 's p^l o^rr'
        }
    }

    It 'rejects an invalid type' {
        InModuleScope Lambek {
            { ConvertFrom-LambekType -Type 'o^x' } | Should -Throw
        }
    }
}

Describe 'Pregroup reduction' {

    It 'reduces <Text> to <Expected>' -ForEach @(
        @{ Text = 's o^l o'; Expected = 's' }
        @{ Text = 'n n^r s o^l o'; Expected = 's' }
        @{ Text = 's p^l o^l o p'; Expected = 's' }
        @{ Text = 's o^l o o^r o d^l d'; Expected = 's' }
        @{ Text = 'o^ll o^l'; Expected = '' }
        @{ Text = 's o^l'; Expected = 's o^l' }
        @{ Text = 'o s'; Expected = 'o s' }
        @{ Text = 'o^r o'; Expected = 'o^r o' }
    ) {
        InModuleScope Lambek -Parameters $_ {
            $simpleTypes = ConvertFrom-LambekType -Type $Text
            $result = Invoke-LambekReduction -SimpleTypes $simpleTypes
            $left = @($result.Leftover | ForEach-Object { $simpleTypes[$_] })

            Format-LambekType -SimpleTypes $left | Should -Be $Expected
        }
    }

    It 'finds the cancellation that a left-to-right scan would miss' {
        InModuleScope Lambek {
            $simpleTypes = ConvertFrom-LambekType -Type 's o^l o o^r o'
            $result = Invoke-LambekReduction -SimpleTypes $simpleTypes

            $result.Leftover.Count | Should -Be 1
            $result.Pairs.Count | Should -Be 2
        }
    }

    It 'returns nothing for an empty list' {
        InModuleScope Lambek {
            $result = Invoke-LambekReduction -SimpleTypes @()
            $result.Leftover.Count | Should -Be 0
        }
    }
}
