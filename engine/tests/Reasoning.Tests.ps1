BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Exact math' {

    It 'adds fractions exactly' {
        $result = [LambekMath]::Evaluate('3/7 + 2/5')
        $result.Exact | Should -Be '29/35'
    }

    It 'solves a quadratic equation: <Text>' -ForEach @(
        @{ Text = 'x^2 - 5x + 6 = 0'; Roots = '2,3' }
        @{ Text = 'x^2 = 2'; Roots = '±√2' }
    ) {
        $result = [LambekMath]::Evaluate($Text)
        $result.Kind | Should -Be 'equation'
        @($result.Roots) -join ',' | Should -Be $Roots
    }

    It 'converts units, temperatures with their offset' {
        [math]::Round([LambekMath]::Convert(100, 'f', 'c'), 4) | Should -Be 37.7778
        [LambekMath]::Convert(1, 'km', 'm') | Should -Be 1000
    }

    It 'counts days between two dates' {
        [LambekMath]::DaysBetween([datetime] '2026-03-12', [datetime] '2026-10-03') | Should -Be 205
    }

    It 'answers a calculation in the language of the question: <Text>' -ForEach @(
        @{ Text = 'combien font 3/7 + 2/5 ?'; Like = '*29/35*' }
        @{ Text = 'résous x² - 5x + 6 = 0'; Like = '*x = 2 ou 3*' }
        @{ Text = 'quel jour de la semaine était le 1 janvier 2000 ?'; Like = '*samedi*' }
        @{ Text = 'convert 100 °F to celsius'; Like = '*37.7778*' }
    ) {
        (InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) Resolve-LambekCalculation -Text $Text }).Answer | Should -BeLike $Like
    }

    It 'never takes a request on files for a calculation: <Text>' -ForEach @(
        @{ Text = 'supprime les fichiers de plus de 5 Go dans C:\Temp' }
        @{ Text = 'delete logs older than 30 days in c:\logs' }
        @{ Text = 'move the logs older than 7 days to s3' }
        @{ Text = 'list the files smaller than 500 KB in C:\Data' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) Resolve-LambekCalculation -Text $Text } | Should -BeNullOrEmpty
    }

    It 'reads a comma as thousands in English, and stays bounded: <Text>' -ForEach @(
        @{ Text = 'what is 1,000 * 3'; Like = '*= 3000*' }
        @{ Text = 'what is 1e99999999'; Like = '*too large*' }
        @{ Text = 'what is sqrt(-4)'; Like = '*no real square root*' }
    ) {
        (InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) Resolve-LambekCalculation -Text $Text }).Answer | Should -BeLike $Like
    }

    It 'asks before reading a dictionary synonym as a change' {
        $plan = New-LambekPlan 'withdraw the log files in C:\Temp'
        $plan.Status | Should -Not -Be 'Ready'
    }
}

Describe 'Datalog with aggregates and proofs' {

    BeforeAll {
        $script:Logic = InModuleScope Lambek {
            $logic = [LambekLogic]::new()
            $text = @'
file("a.log", "T", 100). file("b.log", "T", 300). file("c.txt", "D", 50).
total(F, sum<S>) :- file(_, F, S).
many(F, count<N>) :- file(N, F, _).
largest(F, max<S>) :- file(_, F, S).
biggest(N, F) :- file(N, F, S), largest(F, S).
small(N) :- file(N, _, S), lt(S, 100).
edge("a", "b"). edge("b", "c").
path(X, Y) :- edge(X, Y).
path(X, Z) :- edge(X, Y), path(Y, Z).
'@
            $clauses = ConvertFrom-LambekLogic -Text $text
            foreach ($clause in $clauses) {
                if ($clause.Body.Count -eq 0) { [void] $logic.Add($clause.Head.Name, [string[]] @($clause.Head.Terms | ForEach-Object { [LambekLogic]::Value($_) })) }
                else { $logic.Rules.Add($clause) }
            }
            $logic.Run()
            return , $logic
        }
    }

    It 'sums, counts and takes the largest by group' {
        @($script:Logic.Get('total') | ForEach-Object { $_ -join '=' }) | Should -Be @('D=50', 'T=400')
        @($script:Logic.Get('many') | ForEach-Object { $_ -join '=' }) | Should -Be @('D=1', 'T=2')
        @($script:Logic.Get('biggest') | ForEach-Object { $_[0] }) | Should -Be @('b.log', 'c.txt')
    }

    It 'compares numbers as numbers' {
        @($script:Logic.Get('small') | ForEach-Object { $_[0] }) | Should -Be @('c.txt')
    }

    It 'explains a fact with its proof tree' {
        $proof = $script:Logic.Explain('path', [string[]] @('a', 'c'), 5)
        $proof[0] | Should -Be 'path("a", "c") :-'
        $proof | Should -Contain '    edge("b", "c")'
    }
}

Describe 'Kinds made of kinds' {

    It 'gives media the extensions of images, videos and sounds' {
        $extensions = InModuleScope Lambek { Get-LambekKindExtension -Kind media }
        $extensions | Should -Contain '.jpg'
        $extensions | Should -Contain '.mp4'
        $extensions | Should -Contain '.mp3'
        $extensions | Should -Not -Contain '.pdf'
    }

    It 'understands the word: <Text>' -ForEach @(
        @{ Text = 'list the media files in C:\Temp' }
        @{ Text = 'liste les médias dans C:\Temp' }
    ) {
        $card = ConvertTo-LambekRequest $Text | Resolve-LambekIntent
        $card.Action | Should -Be 'files.list'
        @($card.Parameters.Kind) | Should -Contain 'media'
    }
}

Describe 'Why a change is blocked' {

    It 'gives the proof of the block' {
        $folder = [Environment]::GetFolderPath('UserProfile')
        $blocked = @(InModuleScope Lambek -Parameters @{ Path = $folder } { param($Path) Test-LambekPolicy -Paths @($Path) })
        $blocked.Count | Should -BeGreaterThan 0
        $blocked[0].Proof[0] | Should -BeLike 'blocked(*) :-'
    }

    It 'answers a query with its proof' {
        $folder = [Environment]::GetFolderPath('UserProfile')
        $answer = @(Invoke-LambekQuery 'blocked(P, R)' -Changes $folder -Explain)
        $answer[0].Proof[0] | Should -BeLike 'blocked(*'
    }
}
