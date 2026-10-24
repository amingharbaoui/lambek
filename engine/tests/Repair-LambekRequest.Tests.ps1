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
        (ConvertTo-LambekRequest 'delete the qzx folders').Words | Should -Contain 'qzx'
    }

    It 'does not change words too far from any known word' {
        (ConvertTo-LambekRequest 'delete the weather files').Words | Should -Contain 'weather'
    }

    It 'never changes a name written with a capital inside the sentence ("France" is not "grande")' {
        $request = ConvertTo-LambekRequest 'quel âge a le président de la France ?'
        @($request.Corrections | Where-Object From -EQ 'france').Count | Should -Be 0
    }
}

Describe 'Correction chosen by the grammar' {

    It 'keeps a correction only when the sentence explains more with it' {
        # "must" is one slip away from "list" on an AZERTY keyboard, but a second verb explains nothing
        (ConvertTo-LambekRequest 'the .log files in C:\Temp must be deleted').Corrections.Count | Should -Be 0
    }

    It 'corrects a small word, then reads the place after it: <Text>' -ForEach @(
        @{ Text = 'remet le fichier qui est dans desktop verrs pictures'; Place = 'Pictures' }
        @{ Text = 'move the files from C:\A intoo D:\B'; Place = 'D:\B' }
        @{ Text = 'list the files in Dowloads'; Place = 'Downloads' }
    ) {
        $request = ConvertTo-LambekRequest $Text
        $request.Corrections.Count | Should -Be 1
        $request.Entities[-1].Value | Should -BeLike "*$Place"
    }

    It 'never changes a value: paths, file names and quoted text stay as typed' {
        (ConvertTo-LambekRequest 'list the files in C:\Vera\docs').Entities[0].Value | Should -Be 'C:\Vera\docs'
        (ConvertTo-LambekRequest 'find the files named "dleete" in C:\A').Entities.Value | Should -Contain 'dleete'
        (ConvertTo-LambekRequest 'delete delet.txt').Entities.Value | Should -Contain 'delet.txt'
    }

    It 'keeps the reading it checked, so the grammar is not read twice' {
        $request = ConvertTo-LambekRequest 'delete the .tmp files in C:\Temp'
        $request.Grammar.IsSentence | Should -BeTrue
    }
}

Describe 'Typing distance' {

    It 'costs <Expected> from <Source> to <Target>' -ForEach @(
        @{ Source = 'dnas'; Target = 'dans'; Expected = 0.5 }
        @{ Source = 'verrs'; Target = 'vers'; Expected = 0.5 }
        @{ Source = 'folfer'; Target = 'folder'; Expected = 0.5 }
        @{ Source = 'delet'; Target = 'delete'; Expected = 1 }
        @{ Source = 'delete'; Target = 'delete'; Expected = 0 }
        @{ Source = 'must'; Target = 'list'; Expected = 1 }
        @{ Source = 'abc'; Target = 'xyz'; Expected = 3 }
    ) {
        InModuleScope Lambek -Parameters $_ {
            Measure-LambekKeyDistance -Source $Source -Target $Target | Should -Be $Expected
        }
    }

    It 'knows the keys next to each other on QWERTY and AZERTY' {
        InModuleScope Lambek {
            $keys = Get-LambekKeyNeighbor
            $keys.Contains('df') | Should -BeTrue
            $keys.Contains('ml') | Should -BeTrue
            $keys.Contains('az') | Should -BeTrue
            $keys.Contains('ap') | Should -BeFalse
        }
    }
}
