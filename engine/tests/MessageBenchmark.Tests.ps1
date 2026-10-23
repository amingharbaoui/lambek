BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
    $messages = "$PSScriptRoot/../../bench/messages.json"

    function New-TestMessageBenchmark {
        param([object[]] $Cases)

        $path = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        @{ Version = '1.0'; Cases = $Cases } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8
        return $path
    }
}

Describe 'What a reply is' {

    BeforeAll {
        $templates = InModuleScope Lambek { Get-LambekReplyTemplate }
        function Get-TestKind {
            param([string] $Text)
            InModuleScope Lambek -Parameters @{ Text = $Text; Templates = $templates } { Get-LambekReplyKind -Text $Text -Templates $Templates }
        }
    }

    It 'finds every kind of reply it looks for in the French and English files' {
        foreach ($language in 'fr', 'en') {
            foreach ($kind in 'NotUnderstood', 'Abstained', 'Asked') {
                @($templates | Where-Object { $_.Language -eq $language -and $_.Kind -eq $kind }).Count | Should -BeGreaterThan 0 -Because "$kind in $language"
            }
        }
    }

    It 'reads "I did not understand" as not understood, in every register' {
        Get-TestKind "Je n'ai pas compris cette phrase. Je sais retenir ce que vous me dites et raisonner dessus, calculer, définir un mot, répondre à des questions de culture générale, et m'occuper de : fichiers et code." | Should -Be 'NotUnderstood'
        Get-TestKind "Je n'ai pas compris cette phrase. Je sais retenir ce que tu me dis et raisonner dessus, calculer, définir un mot, répondre à des questions de culture générale, et m'occuper de : fichiers et code." | Should -Be 'NotUnderstood'
        Get-TestKind 'I did not understand that. I can remember what you tell me and reason about it, calculate, define a word, answer general knowledge questions, and take care of files and code.' | Should -Be 'NotUnderstood'
    }

    It 'reads an honest "I do not know" as abstained' {
        Get-TestKind 'I do not know: nobody told me, and I cannot find it out by myself yet.' | Should -Be 'Abstained'
        Get-TestKind "Je ne peux pas le conclure avec ce que vous m'avez dit : « Tweety vole » peut être vrai ou faux." | Should -Be 'Abstained'
    }

    It 'reads a question back as asked' {
        Get-TestKind 'Il me manque un détail. Que veut dire « julie » ici ?' | Should -Be 'Asked'
    }

    It 'reads an answer of its own as said, and nothing as empty' {
        Get-TestKind '12 x 7 = 84' | Should -Be 'Said'
        Get-TestKind '' | Should -Be 'Empty'
    }
}

Describe 'How a turn is scored' {

    BeforeAll {
        function Get-TestOutcome {
            param([hashtable] $Expect, [hashtable] $Turn)
            $parameters = @{ Expect = [pscustomobject] $Expect; Turn = [pscustomobject] $Turn }
            InModuleScope Lambek -Parameters $parameters { Get-LambekMessageOutcome -Expect $Expect -Turn $Turn }
        }
        $said = @{ Status = 'NeedsInput'; Actions = @(); Kind = 'Said' }
    }

    It 'counts the expected answer as Correct, accents and case aside' {
        Get-TestOutcome @{ Reply = 'answer'; Contains = @('lyon') } ($said + @{ Reply = 'Votre sœur habite à LYON.' }) | Should -Be 'Correct'
        Get-TestOutcome @{ Reply = 'answer'; Contains = @('ecole') } ($said + @{ Reply = "L'École est fermée." }) | Should -Be 'Correct'
    }

    It 'takes any of the choices split by |, and needs every item' {
        Get-TestOutcome @{ Reply = 'answer'; Contains = @('oui|yes') } ($said + @{ Reply = 'Yes, Rex is an animal.' }) | Should -Be 'Correct'
        Get-TestOutcome @{ Reply = 'answer'; Contains = @('oui', 'chat') } ($said + @{ Reply = 'Oui.' }) | Should -Be 'Wrong'
    }

    It 'counts another answer as Wrong, and an answer with what it must avoid as Wrong' {
        Get-TestOutcome @{ Reply = 'answer'; Contains = @('madrid') } ($said + @{ Reply = 'Noted. What is the capital of Spain?' }) | Should -Be 'Wrong'
        Get-TestOutcome @{ Reply = 'answer'; Contains = @('chat'); Avoid = @('rayons x') } ($said + @{ Reply = 'chat : scanner à rayons X' }) | Should -Be 'Wrong'
    }

    It 'counts "I did not understand", "I do not know" and a question back as Unanswered when an answer was expected' {
        foreach ($kind in 'NotUnderstood', 'Abstained', 'Asked', 'Empty') {
            Get-TestOutcome @{ Reply = 'answer'; Contains = @('paris') } @{ Status = 'NeedsInput'; Actions = @(); Kind = $kind; Reply = 'x' } | Should -Be 'Unanswered'
        }
    }

    It 'counts abstaining as Correct where Lambek cannot know' {
        Get-TestOutcome @{ Reply = 'abstain' } @{ Status = 'NeedsInput'; Actions = @(); Kind = 'Abstained'; Reply = 'x' } | Should -Be 'Correct'
        Get-TestOutcome @{ Reply = 'abstain' } ($said + @{ Reply = 'Ta soeur a 34 ans.' }) | Should -Be 'Wrong'
        Get-TestOutcome @{ Reply = 'abstain'; Accept = @('je ne sais pas') } ($said + @{ Reply = 'Je ne sais pas, personne ne le sait.' }) | Should -Be 'Correct'
    }

    It 'counts any action where none was asked as Wrong' {
        Get-TestOutcome @{ Reply = 'abstain' } @{ Status = 'Ready'; Actions = @('files.delete'); Kind = 'Empty'; Reply = '' } | Should -Be 'Wrong'
        Get-TestOutcome @{ Reply = 'answer'; Contains = @() } @{ Status = 'Ready'; Actions = @('files.delete'); Kind = 'Empty'; Reply = '' } | Should -Be 'Wrong'
    }

    It 'counts the asked action as Correct, another as Wrong, and a question back as Unanswered' {
        Get-TestOutcome @{ Reply = 'action'; Action = 'files.list' } @{ Status = 'Ready'; Actions = @('files.list'); Kind = 'Empty'; Reply = '' } | Should -Be 'Correct'
        Get-TestOutcome @{ Reply = 'action'; Action = 'files.list' } @{ Status = 'Ready'; Actions = @('files.delete'); Kind = 'Empty'; Reply = '' } | Should -Be 'Wrong'
        Get-TestOutcome @{ Reply = 'action'; Action = 'files.list' } @{ Status = 'NeedsInput'; Actions = @(); Kind = 'Asked'; Reply = 'x' } | Should -Be 'Unanswered'
    }
}

Describe 'Invoke-LambekMessageBenchmark' {

    It 'runs every turn of a conversation and scores the ones with an expectation' {
        $path = New-TestMessageBenchmark @(
            @{ Id = 'T1'; Split = 'test'; Language = 'fr'; Tags = @('calc'); Text = 'combien font 12 fois 7 ?'; Expect = @{ Reply = 'answer'; Contains = @('84') } }
            @{ Id = 'T2'; Split = 'test'; Language = 'en'; Tags = @('told'); Turns = @(
                    @{ Text = 'my brother lives in Paris' }
                    @{ Text = 'where does my brother live?'; Expect = @{ Reply = 'answer'; Contains = @('paris') } }
                ) }
            @{ Id = 'T3'; Split = 'test'; Language = 'en'; Tags = @('out'); Text = 'call my mom'; Expect = @{ Reply = 'abstain' } }
        )
        $report = Invoke-LambekMessageBenchmark -Path $path
        $report.Cases | Should -Be 3
        $report.Turns | Should -Be 3
        $report.Correct | Should -Be 3
        $report.Determinism | Should -Be 1
    }

    It 'keeps nothing of a case for the next one' {
        $path = New-TestMessageBenchmark @(
            @{ Id = 'T1'; Split = 'test'; Language = 'en'; Tags = @('told'); Text = 'my brother lives in Paris'; Expect = @{ Reply = 'answer'; Contains = @('paris') } }
            @{ Id = 'T2'; Split = 'test'; Language = 'en'; Tags = @('told'); Text = 'where does my brother live?'; Expect = @{ Reply = 'abstain' } }
        )
        (Invoke-LambekMessageBenchmark -Path $path).Correct | Should -Be 2
    }

    It 'says when the test split is not the one frozen' {
        $path = New-TestMessageBenchmark @(
            @{ Id = 'T1'; Split = 'test'; Language = 'en'; Tags = @('x'); Text = 'hello'; Expect = @{ Reply = 'answer'; Contains = @('hello') } }
        )
        (Invoke-LambekMessageBenchmark -Path $path).TestFrozen | Should -BeFalse
    }

    It 'rejects a split without cases' {
        $path = New-TestMessageBenchmark @(
            @{ Id = 'T1'; Split = 'test'; Language = 'en'; Tags = @('x'); Text = 'hello'; Expect = @{ Reply = 'abstain' } }
        )
        { Invoke-LambekMessageBenchmark -Path $path -Split calibration } | Should -Throw '*No message case*'
    }
}

Describe 'The free messages of the benchmark' {

    BeforeAll {
        $report = Invoke-LambekMessageBenchmark -Path $messages -Split test
    }

    It 'has a test split that nobody changed' {
        $report.TestFrozen | Should -BeTrue -Because 'bench/messages.json says TestHash; the test split is never edited while working on Lambek'
    }

    It 'never acts on a message that asks for no action' {
        $details = ($report.Failures | Where-Object { $_.Status -eq 'Ready' -and @($_.Actions).Count -gt 0 } | ForEach-Object { $_.Text }) -join ' | '
        $report.WrongActions | Should -Be 0 -Because $details
    }

    It 'gives the same replies in any order' {
        $report.Determinism | Should -Be 1
    }
}
