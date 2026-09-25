BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
}

Describe 'Spelling correction' {

    It 'corrects "<Typo>" to "<Word>"' -ForEach @(
        @{ Typo = 'delet'; Word = 'delete' }
        @{ Typo = 'dleete'; Word = 'delete' }
        @{ Typo = 'folfer'; Word = 'folder' }
        @{ Typo = 'fiels'; Word = 'file' }
    ) {
        $request = ConvertTo-LambekRequest "$Typo the old files"
        $request.Words | Should -Contain $Word
    }

    It 'lists every correction' {
        $request = ConvertTo-LambekRequest 'delet the fils'
        $request.Corrections.From | Should -Contain 'delet'
        $request.Corrections.To | Should -Contain 'delete'
    }

    It 'does not change words it knows' {
        (ConvertTo-LambekRequest 'delete the files').Corrections.Count | Should -Be 0
    }

    It 'does not change short words' {
        (ConvertTo-LambekRequest 'delete the abc files').Words | Should -Contain 'abc'
    }

    It 'does not change words too far from any known word' {
        (ConvertTo-LambekRequest 'delete the weather files').Words | Should -Contain 'weather'
    }
}
