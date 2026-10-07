BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null

    function Invoke-TestPlan {
        param([pscustomobject] $Plan, [string] $Audit)
        $simulation = Invoke-LambekPlan -Plan $Plan -Simulate -AuditPath $Audit
        $approval = $null
        if ($simulation.ConfirmationCode) { $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $Audit }
        return Invoke-LambekPlan -Plan $Plan -Approval $approval -AuditPath $Audit
    }

    function Sha {
        param([byte[]] $Bytes)
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
    }
}

Describe 'Memory store' {

    It 'ranks the request that shares the rare words first (BM25 and trigrams, fused by rank)' {
        $memory = [LambekMemory]::new()
        $memory.Add('run', 'liste les images du bureau', 'fr', [string[]] @('lister', 'image', 'bureau'), [string[]] @('files.list'), '', 100) | Out-Null
        $memory.Add('run', 'supprime les fichiers .tmp', 'fr', [string[]] @('supprimer', 'fichier', 'tmp'), [string[]] @('files.delete'), '', 100) | Out-Null
        $found = $memory.Recall([string[]] @('supprimer', 'tmp'), 'supprime les tmp', [string[]] @(), 200, 5, '')
        $found[0].Item.Text | Should -Be 'supprime les fichiers .tmp'
        $found[0].Lexical | Should -BeGreaterThan 0
    }

    It 'keeps one item for the same request, with one more use' {
        $memory = [LambekMemory]::new()
        $first = $memory.Add('run', 'a b', 'en', [string[]] @('a'), [string[]] @(), '{}', 10)
        $second = $memory.Add('run', 'a b', 'en', [string[]] @('a'), [string[]] @(), '{}', 20)
        $memory.Count | Should -Be 1
        $second.Id | Should -Be $first.Id
        $second.Uses.Count | Should -Be 2
    }

    It 'computes the base-level activation of ACT-R: ln of the sum of age^-0.5' {
        $memory = [LambekMemory]::new()
        $item = $memory.Add('run', 'x', 'en', [string[]] @('x'), [string[]] @(), '', 0)
        $memory.Use($item.Id, 300)
        $expected = [math]::Log([math]::Pow(400, -0.5) + [math]::Pow(100, -0.5))
        [LambekMemory]::Activation($item, 400) | Should -BeLessThan ($expected + 1e-9)
        [LambekMemory]::Activation($item, 400) | Should -BeGreaterThan ($expected - 1e-9)
        [LambekMemory]::Probability(-7) | Should -Be 0.5
    }

    It 'gives back the most active item when nothing is asked' {
        $memory = [LambekMemory]::new()
        $memory.Add('run', 'old', 'en', [string[]] @('old'), [string[]] @(), '', 0) | Out-Null
        $memory.Add('run', 'recent', 'en', [string[]] @('recent'), [string[]] @(), '', 1000) | Out-Null
        $memory.Recall([string[]] @(), '', [string[]] @(), 1010, 1, '')[0].Item.Text | Should -Be 'recent'
    }

    It 'proves what it holds with a Merkle root (RFC 6962)' {
        $memory = [LambekMemory]::new()
        $memory.Root() | Should -Be (Sha ([byte[]] @()))
        $a = $memory.Add('run', 'a', 'en', [string[]] @('a'), [string[]] @(), '', 1)
        $leafA = Sha ([byte[]] (@(0) + [Text.Encoding]::UTF8.GetBytes([LambekMemory]::Line($a))))
        $memory.Root() | Should -Be $leafA

        $b = $memory.Add('run', 'b', 'en', [string[]] @('b'), [string[]] @(), '', 2)
        $leafB = Sha ([byte[]] (@(0) + [Text.Encoding]::UTF8.GetBytes([LambekMemory]::Line($b))))
        $node = [byte[]] (@(1) + [Convert]::FromHexString($leafA) + [Convert]::FromHexString($leafB))
        $memory.Root() | Should -Be (Sha $node)
    }

    It 'reads back what it wrote, and skips a broken line' {
        $path = Join-Path $TestDrive 'memory.jsonl'
        $memory = [LambekMemory]::new()
        $item = $memory.Add('run', 'supprime les .tmp', 'fr', [string[]] @('supprimer', 'tmp'), [string[]] @('files.delete'), '{"Steps":[]}', 5)
        [LambekMemory]::Append($path, [LambekMemory]::Line($item))
        [LambekMemory]::Append($path, '{ broken')
        [LambekMemory]::Append($path, [LambekMemory]::UseLine($item.Id, 9))

        $loaded = [LambekMemory]::Load($path)
        $loaded.Count | Should -Be 1
        $loaded.Broken | Should -Be 1
        $loaded.Items[0].Uses.Count | Should -Be 2
        $loaded.Items[0].Payload | Should -Be '{"Steps":[]}'
        $loaded.Root() | Should -Be $memory.Root()
    }
}

Describe 'Remembering what ran' {

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $audit = Join-Path $root 'audit.jsonl'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        'a' | Set-Content -LiteralPath (Join-Path $root 'a.log')
        'b' | Set-Content -LiteralPath (Join-Path $root 'b.tmp')
        $data = Join-Path $root 'data'
        InModuleScope Lambek -Parameters @{ Data = $data } {
            $script:MemoryPath = Join-Path $Data 'memory.jsonl'
            $script:PursuitPath = Join-Path $Data 'pursuit.json'
            $script:LearnedPath = Join-Path $Data 'words.json'
            $script:Memory = $null
            $script:Pursuit = $null
            $script:LearnedWords = $null
            $script:Incognito = $false
            $script:LexiconCache.Clear()
            $script:ActionIndexCache.Clear()
        }
    }

    AfterAll {
        InModuleScope Lambek {
            $script:Memory = $null
            $script:Pursuit = $null
            $script:LearnedWords = $null
            $script:LexiconCache.Clear()
            $script:ActionIndexCache.Clear()
        }
    }

    It 'keeps a plan that ran, and writes it to the memory file' {
        $result = Invoke-TestPlan -Plan (New-LambekPlan "liste les fichiers .log dans ""$root""") -Audit $audit
        $result.Status | Should -Be 'Completed'
        $found = @(Get-LambekMemory -Text 'liste les .log')
        $found[0].Text | Should -Be "liste les fichiers .log dans ""$root"""
        (Get-LambekMemory -Integrity).Requests | Should -Be 1
        Test-Path (Join-Path $data 'memory.jsonl') | Should -BeTrue
    }

    It 'keeps nothing from an incognito chat' {
        InModuleScope Lambek { $script:Incognito = $true }
        try { Invoke-TestPlan -Plan (New-LambekPlan "liste les fichiers .log dans ""$root""") -Audit $audit | Out-Null }
        finally { InModuleScope Lambek { $script:Incognito = $false } }
        Test-Path (Join-Path $data 'memory.jsonl') | Should -BeFalse
    }

    It 'does it again "like last time": <Text>' -ForEach @(
        @{ Text = 'comme la dernière fois' }
        @{ Text = 'like last time' }
        @{ Text = "refais pareil" }
    ) {
        Invoke-TestPlan -Plan (New-LambekPlan "liste les fichiers .log dans ""$root""") -Audit $audit | Out-Null
        $plan = New-LambekPlan $Text
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Action | Should -Be 'files.list'
        $plan.Steps[0].Parameters['Extension'] | Should -Be '.log'
        $plan.Recalled | Should -Not -BeNullOrEmpty
    }

    It 'takes from the memory only what the new request does not say' {
        Invoke-TestPlan -Plan (New-LambekPlan "liste les fichiers .log dans ""$root""") -Audit $audit | Out-Null
        $plan = New-LambekPlan 'liste les fichiers .tmp comme la dernière fois'
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Parameters['Extension'] | Should -Be '.tmp'
        $plan.Steps[0].Parameters['Path'] | Should -Be $root
    }

    It 'says so when it remembers nothing' {
        $plan = New-LambekPlan 'comme la dernière fois'
        ConvertTo-LambekAnswer -Plan $plan | Should -Match "Je ne me souviens d'aucune demande"
    }

    It 'suggests the closest request when nothing is understood, and "oui" takes it' {
        $plan = New-LambekPlan 'suprimer fichers'
        $plan.Suggestion | Should -Be 'supprimer des fichiers'
        ConvertTo-LambekAnswer -Plan $plan | Should -Match 'supprimer des fichiers'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text 'oui'
        $reply.Kind | Should -Be 'new'
        $reply.Plan.Steps[0].Action | Should -Be 'files.delete'
    }

    It 'suggests nothing for a request far from anything it knows' {
        $plan = New-LambekPlan 'je veux ranger ma cuisine'
        $plan.PSObject.Properties['Suggestion'] | Should -BeNullOrEmpty
    }

    It 'learns an unknown word from a rephrasing, without asking' {
        $plan = New-LambekPlan "vire les fichiers .tmp dans ""$root"""
        $plan.Status | Should -Be 'NeedsInput'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "supprime les fichiers .tmp dans ""$root"""
        $reply.Plan.Unresolved[0].Word | Should -Be 'vire'
        $result = Invoke-TestPlan -Plan $reply.Plan -Audit $audit
        $result.Learned[0].Meaning | Should -Be 'supprimer'
        ConvertTo-LambekAnswer -Plan $reply.Plan -Execution $result | Should -Match '« vire » veut dire « supprimer »'

        $again = New-LambekPlan "vire les fichiers .log dans ""$root"""
        $again.Status | Should -Be 'Ready'
        $again.Steps[0].Action | Should -Be 'files.delete'
    }

    It 'learns nothing when the next request is about something else' {
        $plan = New-LambekPlan "vire les fichiers .tmp dans ""$root"""
        $other = Join-Path $root 'other'
        New-Item -Path $other -ItemType Directory | Out-Null
        'p' | Set-Content -LiteralPath (Join-Path $other 'p.pdf')
        $reply = Resolve-LambekFollowUp -Plan $plan -Text "liste les fichiers .pdf dans ""$other"""
        $result = Invoke-TestPlan -Plan $reply.Plan -Audit $audit
        $result.Status | Should -Be 'Completed'
        @($result.Learned).Count | Should -Be 0
    }
}

Describe 'Pursuit' {

    It 'tries one meaning, keeps it while it is seen, and drops it when it is not' {
        $pursuit = [LambekPursuit]::new()
        $pursuit.Observe('w', [string[]] @('a', 'b'))
        $pursuit.Hypothesis('w') | Should -Be 'a'
        $pursuit.Observe('w', [string[]] @('b', 'c'))
        $pursuit.Words['w']['a'] | Should -Be (0.25 * 0.75)
        $pursuit.Hypothesis('w') | Should -Be 'b'
        $pursuit.Learned('w') | Should -BeNullOrEmpty
        1..3 | ForEach-Object { $pursuit.Observe('w', [string[]] @('b')) }
        $pursuit.Learned('w') | Should -Be 'b'
    }

    It 'saves and reads back the same associations' {
        $pursuit = [LambekPursuit]::new()
        $pursuit.Observe('w', [string[]] @('a'))
        $again = [LambekPursuit]::Load($pursuit.Save())
        $again.Words['w']['a'] | Should -Be 0.25
    }
}
