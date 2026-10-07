BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null

    function Invoke-Logic {
        param([string] $Program, [string] $Predicate)
        InModuleScope Lambek -Parameters @{ Program = $Program; Predicate = $Predicate } {
            $logic = [LambekLogic]::new()
            $clauses = ConvertFrom-LambekLogic -Text $Program
            foreach ($clause in $clauses) {
                if ($clause.Body.Count -eq 0) { [void] $logic.Add($clause.Head.Name, [string[]] @($clause.Head.Terms | ForEach-Object { [LambekLogic]::Value($_) })) }
                else { $logic.Rules.Add($clause) }
            }
            $logic.Run()
            @($logic.Get($Predicate) | ForEach-Object { $_ -join ',' } | Sort-Object)
        }
    }
}

Describe 'Datalog knowledge base' {

    It 'derives every fact that follows, recursion included' {
        $program = 'edge(a, b). edge(b, c). edge(c, d). path(X, Y) :- edge(X, Y). path(X, Z) :- edge(X, Y), path(Y, Z).'
        $paths = Invoke-Logic -Program $program -Predicate 'path'
        $paths.Count | Should -Be 6
        $paths | Should -Contain 'a,d'
    }

    It 'reads "not" after what it negates is complete (stratified)' {
        $program = 'file(a). file(b). kept(a). gone(F) :- file(F), not kept(F).'
        Invoke-Logic -Program $program -Predicate 'gone' | Should -Be @('b')
    }

    It 'refuses rules that negate themselves in a loop' {
        { Invoke-Logic -Program 'p(a). q(X) :- p(X), not r(X). r(X) :- p(X), not q(X).' -Predicate 'q' } | Should -Throw '*loop*'
    }

    It 'compares folders without regard to case or separators' {
        $program = 'changes("C:\Windows\System32"). protected("c:\windows\"). hit(P) :- changes(P), protected(Q), under(P, Q).'
        Invoke-Logic -Program $program -Predicate 'hit' | Should -Be @('C:\Windows\System32')
        Invoke-Logic -Program 'changes("C:\Windowsold"). protected("C:\Windows"). hit(P) :- changes(P), protected(Q), under(P, Q).' -Predicate 'hit' | Should -BeNullOrEmpty
    }

    It 'keeps quoted text as it is written' {
        Invoke-Logic -Program 'name("Say ""hi"", Bob").' -Predicate 'name' | Should -Be @('Say "hi", Bob')
    }

    It 'answers questions about the machine' {
        @(Invoke-LambekQuery 'home(H)').H | Should -Be ([Environment]::GetFolderPath('UserProfile'))
        @(Invoke-LambekQuery 'root(R)').Count | Should -BeGreaterThan 0
    }
}

Describe 'Rules Lambek follows' {

    It 'never changes a folder of the system, a whole drive, or the whole user folder' {
        $system = [Environment]::GetFolderPath('Windows')
        if (-not $system) { $system = '/etc' }
        $drive = @([IO.DriveInfo]::GetDrives())[0].Name
        foreach ($text in "delete the files in $system", "delete the files in $drive", "delete the files in ~") {
            $plan = New-LambekPlan $text
            $plan.Status | Should -Be 'Invalid' -Because $text
            $plan.Steps[0].Status | Should -Be 'Blocked'
        }
    }

    It 'never changes the folder of every user, nor the folder of another user' {
        $users = @(Invoke-LambekQuery 'users(U)')[0].U
        $users | Should -Not -BeNullOrEmpty
        $other = Join-Path (Join-Path $users 'zz-someone-else') 'Documents'
        (New-LambekPlan "delete the files in $users").Questions[0] | Should -BeLike '*the folder of every user*'
        (New-LambekPlan "delete the .tmp files in $other").Questions[0] | Should -BeLike "*in another user's folder*"
        (New-LambekPlan "list the files in $other").Status | Should -Be 'Ready'
    }

    It 'says why in the language of the request' {
        $system = [Environment]::GetFolderPath('Windows')
        if (-not $system) { $system = '/etc' }
        (New-LambekPlan "supprime les fichiers dans $system").Questions[0] | Should -BeLike '*dossier du syst*'
    }

    It 'follows the rules of the user' {
        $rules = Join-Path $TestDrive 'rules.dl'
        Set-Content -LiteralPath $rules -Value 'kept("D:\Photos").'
        InModuleScope Lambek -Parameters @{ Path = $rules } { $script:RulesPath = $Path; $script:Knowledge = $null }
        try {
            (New-LambekPlan 'delete the files in D:\Photos\2024').Questions[0] | Should -BeLike '*kept safe by your rules*'
            (New-LambekPlan 'delete the files in D:\Music').Status | Should -Be 'Ready'
        }
        finally {
            InModuleScope Lambek { $script:RulesPath = Join-Path $TestDrive 'none.dl'; $script:Knowledge = $null }
        }
    }

    It 'lets reading go anywhere' {
        $system = [Environment]::GetFolderPath('Windows')
        if (-not $system) { $system = '/etc' }
        (New-LambekPlan "list the files in $system").Status | Should -Be 'Ready'
    }
}
