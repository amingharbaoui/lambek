BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Resolve-Text {
        param([string] $Text)
        ConvertTo-LambekRequest $Text | Resolve-LambekGrammar
    }
}

Describe 'Resolve-LambekGrammar' {

    Context 'Complete sentences' {
        It 'accepts "<Text>"' -ForEach @(
            @{ Text = 'delete the old files' }
            @{ Text = 'move the files in C:\Temp to D:\Archive' }
            @{ Text = 'Delete the files older than 30 days in C:\Temp larger than 5 GB' }
            @{ Text = 'create a folder in C:\Temp' }
            @{ Text = 'rename report.txt to "summary.txt"' }
            @{ Text = 'generate a powershell function named Get-Report' }
            @{ Text = 'write a python script' }
            @{ Text = 'supprime les fichiers .log de plus de 5 Go dans "D:\Mes Logs"' }
            @{ Text = 'deplace les fichiers vers D:\Archive' }
            @{ Text = 'genere une fonction python nommee "rapport"' }
        ) {
            (Resolve-Text $Text).IsSentence | Should -BeTrue
        }

        It 'reduces to the sentence type s' {
            $result = Resolve-Text 'move the files to D:\Archive'
            $result.Leftover | Should -Be 's'
            $result.Types | Should -Be 's p^l o^l o p d^l d'
        }

        It 'lists every cancellation' {
            $result = Resolve-Text 'move the files to D:\Archive'
            $result.Steps.Count | Should -Be 3
            $result.Steps | Should -Contain 'o^l o -> 1 (move, file)'
        }

        It 'chooses the right type for a word with two meanings' {
            $folder = Resolve-Text 'create a folder'
            $script = Resolve-Text 'create a script'

            ($folder.Assignment | Where-Object Word -EQ 'create').Type | Should -Be 's o^l'
            ($script.Assignment | Where-Object Word -EQ 'create').Type | Should -Be 's a^l'
        }
    }

    Context 'Incomplete sentences' {
        It 'asks for the object of "delete"' {
            $result = Resolve-Text 'delete'
            $result.IsSentence | Should -BeFalse
            $result.Missing | Should -Be @('o')
            $result.Questions | Should -Be @('Which files or folders?')
        }

        It 'asks for the destination of "move"' {
            $result = Resolve-Text 'move the files'
            $result.Missing | Should -Be @('p')
            $result.Questions | Should -Be @('Where to?')
        }

        It 'asks for the action when there is no verb' {
            $result = Resolve-Text 'old files'
            $result.Missing | Should -Contain 's'
            $result.Questions | Should -Contain 'What do you want to do?'
        }

        It 'asks the question in French' {
            $result = Resolve-Text 'deplace les fichiers vers'
            $result.Questions | Should -Be @('Dans quel dossier ?')
        }

        It 'asks for the name after "named"' {
            $result = Resolve-Text 'generate a function named'
            $result.Missing | Should -Be @('n')
        }

        It 'reports unknown words' {
            $result = Resolve-Text 'delete the files zorblax'
            $result.Unknown | Should -Contain 'zorblax'
        }
    }

    Context 'Determinism' {
        It 'gives the same result every time' {
            $first = Resolve-Text 'Delete the files older than 30 days in C:\Temp larger than 5 GB'
            $second = Resolve-Text 'Delete the files older than 30 days in C:\Temp larger than 5 GB'
            ($first | ConvertTo-Json -Depth 5) | Should -Be ($second | ConvertTo-Json -Depth 5)
        }
    }
}

Describe 'One chart for every choice of types' {

    It 'finds the same sentences as trying every combination, on random words' {
        InModuleScope Lambek {
            # Brute force: every combination of types, each reduced on its own
            $types = @('s o^l', 's p^l o^l', 'o', 'o^r o', 'o o^l', 'p d^l', 'd', 'o^r o d^l', 's s^l d^l', 'o^r o c^l', 'c z^l', 'z')
            $random = [System.Random]::new(7)
            for ($case = 0; $case -lt 60; $case++) {
                $words = [System.Collections.Generic.List[object]]::new()
                for ($w = 0; $w -lt $random.Next(1, 6); $w++) {
                    $candidates = @(for ($c = 0; $c -lt $random.Next(1, 3); $c++) { $types[$random.Next($types.Count)] }) | Select-Object -Unique
                    $words.Add([pscustomobject]@{ Candidates = [string[]] @($candidates) })
                }

                $expected = $false
                $choice = [int[]]::new($words.Count)
                do {
                    $simple = @(for ($w = 0; $w -lt $words.Count; $w++) { ConvertFrom-LambekType -Type $words[$w].Candidates[$choice[$w]] })
                    $left = @((Invoke-LambekReduction -SimpleTypes $simple).Leftover | ForEach-Object { $simple[$_] })
                    if ($left.Count -eq 1 -and $left[0].Base -eq 's' -and $left[0].Order -eq 0) { $expected = $true }
                    $position = $words.Count - 1
                    while ($position -ge 0) {
                        $choice[$position]++
                        if ($choice[$position] -lt $words[$position].Candidates.Count) { break }
                        $choice[$position] = 0
                        $position--
                    }
                } while ($position -ge 0 -and -not $expected)

                $root = Invoke-LambekChart -TypedWords $words -SentenceOnly
                $root.ContainsKey('s|0') | Should -Be $expected -Because (($words | ForEach-Object { $_.Candidates -join ' / ' }) -join ' + ')
            }
        }
    }

    It 'says how many readings make a sentence' {
        (Resolve-Text 'delete the old files').Readings | Should -Be 1
        (Resolve-Text 'move the files').Readings | Should -Be 0
    }

    It 'stops at a fixed amount of work, not at a time' {
        InModuleScope Lambek {
            $words = [System.Collections.Generic.List[object]]::new()
            1..6 | ForEach-Object { $words.Add([pscustomobject]@{ Candidates = [string[]] @('o', 'o^r o', 'o o^l') }) }
            { Invoke-LambekChart -TypedWords $words -Fuel 5 } | Should -Throw '*too many readings*'
        }
    }
}
