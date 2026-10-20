BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    # A conversation of its own, never written down
    function Reset-TestConversation {
        InModuleScope Lambek {
            $script:Told = $null; $script:Board = $null; $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
            $script:Incognito = $true; $script:CategoryPending = $null; $script:LastProofs = $null; $script:ProblemStores = $null
            $script:LanguageHint = $null
        }
    }
    function Get-TestAnswer {
        param([string] $Text)
        New-LambekPlan -Text $Text | ConvertTo-LambekAnswer
    }
    function Get-TestRoute {
        param([string] $Text)
        InModuleScope Lambek -Parameters @{ Text = $Text } { Get-LambekRoute -Text $Text }
    }
    # Compared as the bench compares texts: small letters, no accents, no punctuation
    function ConvertTo-TestKey {
        param([string] $Text)
        InModuleScope Lambek -Parameters @{ Text = $Text } { ((ConvertTo-LambekBenchText -Text $Text) -replace '[^\p{L}\p{N}]+', ' ').Trim() }
    }
}

AfterAll {
    InModuleScope Lambek { $script:Incognito = $false }
}

Describe 'Get-LambekRoute' {

    BeforeEach { Reset-TestConversation }

    It 'says what a message is when both ways agree' {
        (Get-TestRoute 'combien font 7 fois 9 ?').Act | Should -Be 'Calculate'
        (Get-TestRoute 'supprime les fichiers .tmp dans C:\Temp').Act | Should -Be 'Order'
        (Get-TestRoute 'raconte-moi une blague').Act | Should -Be 'Open'
    }

    It 'sees the files a message names' {
        (Get-TestRoute 'supprime les fichiers .tmp dans C:\Temp').Files | Should -BeTrue
        (Get-TestRoute 'raconte-moi une blague').Files | Should -BeFalse
    }

    It 'abstains on what is like none of its examples' {
        (Get-TestRoute 'xq zzv blorp').Act | Should -BeNullOrEmpty
    }

    It 'says the same act every time' {
        $first = Get-TestRoute 'envoie un mail à Paul'
        $second = Get-TestRoute 'envoie un mail à Paul'
        $second.Act | Should -Be $first.Act
        $second.Margin | Should -Be $first.Margin
    }
}

Describe 'What the router lets Lambek say' {

    BeforeEach { Reset-TestConversation }

    It 'says it cannot tell stories or give advice yet, rather than that it did not understand' {
        Get-TestAnswer 'raconte-moi une blague' | Should -BeLike 'Ça, je ne sais pas encore le faire*fichiers et code.'
    }

    It 'says it has no hold on what is done elsewhere' {
        Get-TestAnswer 'envoie un mail à Paul' | Should -BeLike 'Ça, je ne peux pas le faire*'
    }

    It 'says in their language what it reads only in French and English' {
        Get-TestAnswer 'Was ist die Hauptstadt von Spanien?' | Should -BeLike 'Ich verstehe, dass Sie mir etwas sagen oder fragen*'
    }

    It 'leaves the readers the last word when they read something' {
        Get-TestAnswer 'lösche die Dateien in C:\Temp' | Should -BeLike 'Ich werde die Dateien in C:\Temp löschen*'
        Get-TestAnswer 'je suis fatigué' | Should -BeLike "C'est noté*"
        Get-TestAnswer 'bonjour' | Should -Not -BeLike 'Ça, je*'
    }

    It 'still says it did not understand what it cannot place' {
        Get-TestAnswer 'patati et patata' | Should -BeLike "Je n'ai pas compris cette phrase.*"
    }
}

Describe 'The examples of the router and its bench' {

    BeforeAll {
        $examples = (Get-Content "$PSScriptRoot/../Lambek/Data/acts.json" -Raw | ConvertFrom-Json)
        $bench = (Get-Content "$PSScriptRoot/../../bench/acts.json" -Raw | ConvertFrom-Json)
        $messages = (Get-Content "$PSScriptRoot/../../bench/messages.json" -Raw | ConvertFrom-Json)
        $requests = (Get-Content "$PSScriptRoot/../../bench/requests.json" -Raw | ConvertFrom-Json)
    }

    It 'names only acts it declares' {
        $declared = @($examples.Acts.PSObject.Properties.Name)
        @($examples.Examples | Where-Object { $_.Act -notin $declared }).Count | Should -Be 0
        @($bench.Cases | Where-Object { $_.Act -notin $declared }).Count | Should -Be 0
    }

    It 'never learns from a message it is measured on, nor from a test split' {
        $learnt = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($example in $examples.Examples) { [void] $learnt.Add((ConvertTo-TestKey $example.Text)) }
        $measured = @($bench.Cases | ForEach-Object Text)
        $measured += @($messages.Cases | Where-Object Split -EQ 'test' | ForEach-Object { if ($_.PSObject.Properties['Turns']) { $_.Turns.Text } else { $_.Text } })
        $measured += @($requests.Cases | Where-Object Split -NE 'calibration' | ForEach-Object Text)
        @($measured | Where-Object { $learnt.Contains((ConvertTo-TestKey $_)) }) | Should -BeNullOrEmpty
    }

    It 'keeps the test split of its bench frozen' {
        (Invoke-LambekActBenchmark -Path "$PSScriptRoot/../../bench/acts.json" -Split test).TestFrozen | Should -BeTrue
    }

    It 'routes its bench the same way every time, and is right most of the time it speaks' {
        $report = Invoke-LambekActBenchmark -Path "$PSScriptRoot/../../bench/acts.json" -Split calibration
        $report.Determinism | Should -Be 1
        $report.Precision | Should -BeGreaterOrEqual 0.9
    }
}
