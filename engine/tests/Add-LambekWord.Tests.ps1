BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Type of an unknown word' {

    BeforeEach {
        $words = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        InModuleScope Lambek -Parameters @{ Path = $words } { $script:LearnedPath = $Path; $script:LearnedWords = $null; $script:LexiconCache.Clear() }
    }

    It 'solves the type the sentence needs: <Text>' -ForEach @(
        @{ Text = 'vire les .tmp dans C:\Temp'; Word = 'vire'; Type = 's o^l' }
        @{ Text = 'zap the files in C:\A to D:\B'; Word = 'zap'; Type = 's p^l o^l' }
        @{ Text = 'delete the screenshots in C:\A'; Word = 'screenshots'; Type = 'o' }
    ) {
        $step = (New-LambekPlan $Text).Steps[0]
        $step.Guess.Token | Should -Be $Word
        $step.Guess.Types | Should -Contain $Type
        $step.Status | Should -Not -Be 'Ready'
    }

    It 'asks what the word means, with the actions of that type' {
        $plan = New-LambekPlan 'zap the files in C:\A to D:\B'
        $plan.Questions[0] | Should -BeLike '*"zap"*'
        $plan.Questions[0] | Should -BeLike '*move*'
        $plan.Questions[0] | Should -Not -BeLike '*delete*'
    }

    It 'solves nothing with two unknown words' {
        (New-LambekPlan 'zorp blarg the .tmp files in C:\Temp').Steps[0].Guess | Should -BeNullOrEmpty
    }

    It 'never lets a folder stand for files an unknown word names' {
        (New-LambekPlan 'delete the screenshots in C:\A').Status | Should -Be 'NeedsInput'
    }

    It 'keeps the count invariant: even orders minus odd orders of each base' {
        InModuleScope Lambek {
            $types = [System.Collections.Generic.List[object]]::new()
            foreach ($type in 's o^l', 'o') { foreach ($simple in ConvertFrom-LambekType -Type $type) { $types.Add($simple) } }
            Test-LambekTypeCount -SimpleTypes $types | Should -BeTrue
            $types.Add((ConvertFrom-LambekType -Type 'o')[0])
            Test-LambekTypeCount -SimpleTypes $types | Should -BeFalse
        }
    }

    It 'tries a type for a word with -Hypothesis' {
        $request = ConvertTo-LambekRequest 'zap the files'
        (Resolve-LambekGrammar -Request $request).IsSentence | Should -BeFalse
        (Resolve-LambekGrammar -Request $request -Hypothesis @{ zap = @('s o^l') }).IsSentence | Should -BeTrue
        (Resolve-LambekGrammar -Request $request -Hypothesis @{ zap = @('o') } -SentenceOnly).IsSentence | Should -BeFalse
    }
}

Describe 'Learning a word' {

    BeforeEach {
        $words = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        InModuleScope Lambek -Parameters @{ Path = $words } { $script:LearnedPath = $Path; $script:LearnedWords = $null; $script:Incognito = $false; $script:LexiconCache.Clear() }
    }

    It 'learns the word from the reply, then reads the request again' {
        $plan = New-LambekPlan 'vire les .tmp dans C:\Temp'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text 'supprimer'
        $reply.Kind | Should -Be 'edit'
        $reply.Answer | Should -BeLike '*vire*supprimer*'
        $reply.Plan.Status | Should -Be 'Ready'
        $reply.Plan.Steps[0].Action | Should -Be 'files.delete'
        (New-LambekPlan 'vire les fichiers .log dans C:\Logs').Steps[0].Action | Should -Be 'files.delete'
    }

    It 'learns a noun as a kind of file' {
        $plan = New-LambekPlan 'delete the screenshots in C:\A'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text 'images'
        $reply.Plan.Status | Should -Be 'Ready'
        $reply.Plan.Steps[0].Parameters.Kind | Should -Be 'image'
    }

    It 'refuses a meaning whose type does not fit' {
        $plan = New-LambekPlan 'vire les .tmp dans C:\Temp'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text 'fichier'
        $reply.PSObject.Properties['Learned'] | Should -BeNullOrEmpty
        Get-LambekWord | Should -BeNullOrEmpty
    }

    It 'keeps the words in a file, sorted' {
        Add-LambekWord -Word zap -Meaning delete -Language en | Out-Null
        Add-LambekWord -Word vire -Meaning supprimer -Language fr | Out-Null
        $file = InModuleScope Lambek { Get-Content -LiteralPath $script:LearnedPath -Raw | ConvertFrom-Json -AsHashtable }
        $file.en.zap | Should -Be 'delete'
        $file.fr.vire | Should -Be 'supprimer'
        (Get-LambekWord).Word | Should -Be @('zap', 'vire')
    }

    It 'reads a learned word as the word it means' {
        Add-LambekWord -Word zap -Meaning delete -Language en | Out-Null
        $plan = New-LambekPlan 'zap the .log files in C:\Temp'
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Action | Should -Be 'files.delete'
    }

    It 'forgets a word' {
        Add-LambekWord -Word zap -Meaning delete -Language en | Out-Null
        Remove-LambekWord -Word zap -Language en
        (New-LambekPlan 'zap the .log files in C:\Temp').Status | Should -Not -Be 'Ready'
        { Remove-LambekWord -Word zap -Language en } | Should -Throw '*did not learn*'
    }

    It 'refuses a word it already knows, or a meaning it does not' {
        { Add-LambekWord -Word delete -Meaning list -Language en } | Should -Throw '*already*'
        { Add-LambekWord -Word zap -Meaning banana -Language en } | Should -Throw '*not a word*'
        { Add-LambekWord -Word 'two words' -Meaning delete -Language en } | Should -Throw '*one word*'
    }

    It 'writes nothing in an incognito chat' {
        InModuleScope Lambek { $script:Incognito = $true }
        try {
            Add-LambekWord -Word zap -Meaning delete -Language en | Out-Null
            InModuleScope Lambek { Test-Path -LiteralPath $script:LearnedPath } | Should -BeFalse
        }
        finally { InModuleScope Lambek { $script:Incognito = $false } }
    }
}
