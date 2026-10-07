BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Resolve-Text {
        param([string] $Text)
        ConvertTo-LambekRequest $Text | Resolve-LambekIntent
    }
}

Describe 'Resolve-LambekIntent' {

    Context 'Recognition' {
        It 'recognizes <Action> in "<Text>"' -ForEach @(
            @{ Text = 'delete the .log files in C:\Temp'; Action = 'files.delete' }
            @{ Text = 'remove the files older than 30 days in C:\Temp'; Action = 'files.delete' }
            @{ Text = 'list the files in C:\Users'; Action = 'files.list' }
            @{ Text = 'find the large files in C:\Data'; Action = 'files.list' }
            @{ Text = 'copy report.txt to D:\Backup'; Action = 'files.copy' }
            @{ Text = 'move the files in C:\Temp to D:\Archive'; Action = 'files.move' }
            @{ Text = 'rename report.txt to "summary.txt"'; Action = 'files.rename' }
            @{ Text = 'create a folder named "logs" in C:\Temp'; Action = 'files.create' }
            @{ Text = 'create a script'; Action = 'code.generate' }
            @{ Text = 'generate a powershell function named Get-Report'; Action = 'code.generate' }
            @{ Text = 'supprime les fichiers .log dans C:\Temp'; Action = 'files.delete' }
            @{ Text = 'deplace les fichiers de C:\Temp vers D:\Archive'; Action = 'files.move' }
            @{ Text = 'genere une fonction python nommee "rapport"'; Action = 'code.generate' }
        ) {
            $card = Resolve-Text $Text
            $card.Status | Should -Be 'Ready'
            $card.Action | Should -Be $Action
        }

        It 'understands a request with typos' {
            $card = Resolve-Text 'delet the fils in C:\Temp'
            $card.Status | Should -Be 'Ready'
            $card.Action | Should -Be 'files.delete'
        }

        It 'asks how old when a delete only says "old"' {
            $card = Resolve-Text 'delet the old fils in C:\Temp'
            $card.Status | Should -Be 'NeedsInput'
            $card.Action | Should -Be 'files.delete'
            $card.Questions | Should -Contain 'What age or duration?'
        }
    }

    Context 'Parameters' {
        It 'fills every filter of a delete request' {
            $card = Resolve-Text 'Delete the files older than 30 days in C:\Temp larger than 5 GB'
            $card.Parameters.Path | Should -BeExactly 'C:\Temp'
            $card.Parameters.OlderThan | Should -Be ([timespan]::FromDays(30))
            $card.Parameters.MinSize | Should -Be 5GB
        }

        It 'tells the source from the destination' {
            $card = Resolve-Text 'move the files in C:\Temp to D:\Archive'
            $card.Parameters.Source | Should -BeExactly 'C:\Temp'
            $card.Parameters.Destination | Should -BeExactly 'D:\Archive'
        }

        It 'tells the old name from the new name' {
            $card = Resolve-Text 'rename report.txt to "summary.txt"'
            $card.Parameters.Name | Should -Be 'report.txt'
            $card.Parameters.NewName | Should -Be 'summary.txt'
        }

        It 'tells a minimum size from a maximum size' {
            (Resolve-Text 'list the files larger than 1 GB in C:\Data').Parameters.MinSize | Should -Be 1GB
            (Resolve-Text 'list the files smaller than 1 GB in C:\Data').Parameters.MaxSize | Should -Be 1GB
        }

        It 'reads French filters' {
            $card = Resolve-Text 'supprime les fichiers .log de plus de 5 Go dans "D:\Mes Logs"'
            $card.Parameters.Path | Should -BeExactly 'D:\Mes Logs'
            $card.Parameters.Extension | Should -Be '.log'
            $card.Parameters.MinSize | Should -Be 5GB
        }

        It 'reads word parameters and defaults' {
            $card = Resolve-Text 'generate a function named Get-Report'
            $card.Parameters.Kind | Should -Be 'Function'
            $card.Parameters.Language | Should -Be 'PowerShell'
            $card.Parameters.Name | Should -Be 'Get-Report'
        }
    }

    Context 'Questions' {
        It 'asks for the destination of a move' {
            $card = Resolve-Text 'move the files'
            $card.Status | Should -Be 'NeedsInput'
            $card.Missing | Should -Contain 'Destination'
            $card.Questions | Should -Contain 'Where to?'
        }

        It 'asks for the folder of a delete' {
            $card = Resolve-Text 'delete the .log files'
            $card.Status | Should -Be 'NeedsInput'
            $card.Questions | Should -Contain 'In which folder?'
        }

        It 'asks in French' {
            $card = Resolve-Text 'deplace les fichiers'
            $card.Questions | Should -Contain 'Vers quel emplacement ?'
        }

        It 'asks which action when two are equally possible' {
            $card = Resolve-Text 'create'
            $card.Status | Should -Be 'Ambiguous'
            $card.Questions[0] | Should -BeLike 'Did you mean*'
        }

        It 'does not guess an unrelated request' {
            $card = Resolve-Text 'what is the weather'
            $card.Status | Should -Be 'Unknown'
            $card.Action | Should -BeNullOrEmpty
            $card.Questions | Should -Be @('What do you want to do?')
        }
    }

    Context 'Safety guards' {
        It 'does not act on "<Text>"' -ForEach @(
            @{ Text = "don't delete the files in C:\Temp" }
            @{ Text = 'never delete the files in C:\Temp' }
            @{ Text = 'ne supprime pas les fichiers dans C:\Temp' }
            @{ Text = "n'efface jamais les fichiers dans C:\Temp" }
            @{ Text = 'delete the files except in C:\Temp' }
            @{ Text = 'delete the obsolete files in C:\Temp' }
            @{ Text = 'delete the largest files in C:\Temp' }
            @{ Text = 'delete 5 files in C:\Temp' }
        ) {
            $card = Resolve-Text $Text
            $card.Status | Should -Be 'NeedsInput'
            $card.CardHash | Should -BeNullOrEmpty
        }

        It 'says which value it could not use' {
            (Resolve-Text 'delete report.txt notes.txt in C:\Temp').Questions | Should -Contain 'I could not use: notes.txt. Could you say it another way?'
        }
    }

    Context 'Card hash' {
        It 'is the same for different wording with the same meaning' {
            $first = Resolve-Text 'delete the .log files in C:\Temp'
            $second = Resolve-Text 'Remove   the .LOG files in C:\Temp please'
            $first.CardHash | Should -Be $second.CardHash
        }

        It 'is the same in English and French' {
            $english = Resolve-Text 'delete the .log files in C:\Temp'
            $french = Resolve-Text 'supprime les fichiers .log dans C:\Temp'
            $english.CardHash | Should -Be $french.CardHash
        }

        It 'changes when a parameter changes' {
            $first = Resolve-Text 'delete the .log files in C:\Temp'
            $second = Resolve-Text 'delete the .log files in C:\Logs'
            $first.CardHash | Should -Not -Be $second.CardHash
        }

        It 'is empty when the card is not ready' {
            (Resolve-Text 'move the files').CardHash | Should -BeNullOrEmpty
        }
    }

    Context 'Determinism' {
        It 'gives the same card every time' {
            $first = Resolve-Text 'Delete the files older than 30 days in C:\Temp larger than 5 GB'
            $second = Resolve-Text 'Delete the files older than 30 days in C:\Temp larger than 5 GB'
            ($first | ConvertTo-Json -Depth 5) | Should -Be ($second | ConvertTo-Json -Depth 5)
        }
    }
}
