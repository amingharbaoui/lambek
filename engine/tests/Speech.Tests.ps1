BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
    $dictionary = InModuleScope Lambek { $null = Get-LambekDictionary -Language 'en'; Get-LambekDictionary -Language 'fr' } | Select-Object -Last 1
}

Describe 'The rules of each language' {

    It 'contracts, elides and agrees in French: <Text>' -ForEach @(
        @{ Text = 'copier le image de le dossier'; Said = "copier l'image du dossier" }
        @{ Text = 'les fichiers de les dossiers à le bureau'; Said = 'les fichiers des dossiers au bureau' }
        @{ Text = 'si il faut, que il le fasse'; Said = "s'il faut, qu'il le fasse" }
        @{ Text = 'générer un classe PowerShell nommé Facture'; Said = 'générer une classe PowerShell nommée Facture' }
        @{ Text = 'une dossier et un liste'; Said = 'un dossier et une liste' }
        @{ Text = 'Terminé. 1 éléments traités.'; Said = 'Terminé. 1 élément traité.' }
        @{ Text = 'Terminé. 3 élément traité.'; Said = 'Terminé. 3 éléments traités.' }
        @{ Text = 'je le copie dans le dossier'; Said = 'je le copie dans le dossier' }
    ) {
        [LambekSpeech]::Polish($Text, 'fr', $dictionary) | Should -BeExactly $Said
    }

    It 'never changes a quote, a path or a name: <Text>' -ForEach @(
        @{ Text = '« de le » reste' }
        @{ Text = 'la copie de C:\Temp\de le.txt' }
        @{ Text = 'l''étape 1 modifie D:\Archive' }
    ) {
        [LambekSpeech]::Polish($Text, 'fr', $dictionary) | Should -BeExactly $Text
    }

    It 'chooses a or an, and the plural after a number, in English: <Text>' -ForEach @(
        @{ Text = 'I found 1 files and a image'; Said = 'I found 1 file and an image' }
        @{ Text = 'a .exe file, a .log file, a hour, a user'; Said = 'an .exe file, a .log file, an hour, a user' }
        @{ Text = '3 copy and 2 item'; Said = '3 copies and 2 items' }
        @{ Text = 'step 1 changes D:\Archive'; Said = 'step 1 changes D:\Archive' }
    ) {
        [LambekSpeech]::Polish($Text, 'en', $dictionary) | Should -BeExactly $Said
    }

    It 'says tu to a user who says tu: <Text>' -ForEach @(
        @{ Text = 'Voulez-vous dire « éliminer » ? Répondez oui pour le faire.'; Said = 'Veux-tu dire « éliminer » ? Réponds oui pour le faire.' }
        @{ Text = "Simulez d'abord, puis confirmez avec un code."; Said = "Simule d'abord, puis confirme avec un code." }
        @{ Text = 'Dites-moi ce que vous voulez faire.'; Said = 'Dis-moi ce que tu veux faire.' }
        @{ Text = 'Je vous montre vos fichiers sur votre ordinateur.'; Said = 'Je te montre tes fichiers sur ton ordinateur.' }
        @{ Text = "Je ne me souviens d'aucune demande que vous avez confirmée."; Said = "Je ne me souviens d'aucune demande que tu as confirmée." }
    ) {
        [LambekSpeech]::Familiar($Text, $dictionary) | Should -BeExactly $Said
    }

    It 'takes the form a number asks for: 0 and 1 are singular in French, only 1 in English' {
        [LambekSpeech]::Plural('{0:fichier|fichiers}/{1:fichier|fichiers}/{2:fichier|fichiers}', 'fr', [long[]] @(0, 1, 2)) | Should -Be 'fichier/fichier/fichiers'
        [LambekSpeech]::Plural('{0:file|files}/{1:file|files}/{2:file|files}', 'en', [long[]] @(0, 1, 2)) | Should -Be 'files/file/files'
    }

    It 'gives the past participle of a verb' {
        $dictionary.Participle('supprimer', 'fr') | Should -Be 'supprimé'
        $dictionary.Participle('déplacer', 'fr') | Should -Be 'déplacé'
        $dictionary.Participle('delete', 'en') | Should -Be 'deleted'
        $dictionary.Participle('find', 'en') | Should -Be 'found'
        $dictionary.Participle('copy', 'en') | Should -Be 'copied'
        $dictionary.Participle('write', 'en') | Should -Be 'written'
    }

    It 'hashes the same text the same way in every process (FNV-1a)' {
        [LambekSpeech]::Hash('') | Should -Be 14695981039346656037
        [LambekSpeech]::Hash('a') | Should -Be 12638187200555641996
    }

    It 'picks a phrasing not used in the last turns' {
        $first = [LambekSpeech]::Pick('greeting', 3, [int[]] @())
        $next = [LambekSpeech]::Pick('greeting', 3, [int[]] @($first))
        $next | Should -Not -Be $first
        [LambekSpeech]::Pick('greeting', 3, [int[]] @()) | Should -Be $first
    }
}

Describe 'Saying the plan' {

    It 'reads its own sentence back to the same plan, for every request of the benchmark' {
        $cases = @((Get-Content "$PSScriptRoot/../../bench/requests.json" -Raw | ConvertFrom-Json).Cases | Where-Object { $_.Expected.Status -eq 'Ready' })
        $wrong = foreach ($case in $cases) {
            $plan = New-LambekPlan $case.Text -NoRecall
            if ($plan.Status -ne 'Ready') { continue }
            foreach ($step in $plan.Steps) {
                if ($step.Output -eq 'mcp') { continue }
                $said = InModuleScope Lambek -Parameters @{ Step = $step } { Get-LambekStepSentence -Step $Step -Language $Step.Language -Units (Get-LambekLexicon -Language $Step.Language).Answer.Units }
                # A sentence that does not read back ends with the exact values, between brackets
                if ($said -match '\)$' -and $said -match ' = ') { "$($case.Id): $said" }
            }
        }
        @($wrong) | Should -BeNullOrEmpty
    }

    It 'puts a name between quotes when it would not read back without them' {
        (New-LambekPlan 'create a folder named "logs" in C:\Temp' | ConvertTo-LambekAnswer).Split("`n")[0] | Should -Be 'I''ll create a folder named "logs" in C:\Temp.'
    }

    It 'says a value of the pack in the language of the answer' {
        (New-LambekPlan 'cree une classe nommee "Facture"' | ConvertTo-LambekAnswer).Split("`n")[0] | Should -Be 'Je vais générer une classe PowerShell nommée « Facture ».'
    }

    It 'answers in the register of the user' {
        $answer = New-LambekPlan 'tu peux supprimer les fichiers .log dans C:\Temp ?' | ConvertTo-LambekAnswer
        $answer | Should -BeLike "*Simule d'abord, puis confirme avec un code.*"
        (New-LambekPlan 'pouvez-vous supprimer les fichiers .log dans C:\Temp ?' | ConvertTo-LambekAnswer) | Should -BeLike "*Simulez d'abord*"
    }

    It 'drops a greeting before a request' {
        (New-LambekPlan 'salut, supprime les fichiers .log dans C:\Temp').Steps[0].Action | Should -Be 'files.delete'
    }

    It 'varies small talk without chance: the first phrasing first' {
        InModuleScope Lambek { $script:SpeechRecent.Clear() }
        $first = New-LambekPlan 'merci' | ConvertTo-LambekAnswer
        $second = New-LambekPlan 'merci' | ConvertTo-LambekAnswer
        $first | Should -Be 'Avec plaisir.'
        $second | Should -Not -Be $first
    }
}

Describe 'Saying what was done' {

    BeforeAll {
        $root = Join-Path $TestDrive 'report'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        'a' * 1000 | Set-Content -LiteralPath (Join-Path $root 'a.log')
        'b' * 5000 | Set-Content -LiteralPath (Join-Path $root 'b.log')
        # Two bytes on every system (a line end is one byte on Linux, two on Windows)
        'cc' | Set-Content -LiteralPath (Join-Path $root 'c.txt') -NoNewline
        $audit = Join-Path $TestDrive 'audit.jsonl'
    }

    It 'gives the numbers of a read: how many, how large, the largest' {
        $plan = New-LambekPlan "liste les fichiers dans ""$root"""
        $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
        $approval = Approve-LambekPlan -Simulation $simulation -AuditPath $audit
        $run = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
        $answer = ConvertTo-LambekAnswer -Plan $plan -Execution $run
        $answer | Should -BeLike "*J'ai trouvé 3 fichiers, 5,9 Ko au total. Le plus volumineux : b.log (4,9 Ko).*"
    }

    It 'says a change with the verb of the action in the past' {
        $plan = New-LambekPlan "delete the .txt files in ""$root"""
        $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $audit
        $approval = Approve-LambekPlan -Simulation $simulation -Confirmation $simulation.ConfirmationCode -AuditPath $audit
        $run = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $audit
        ConvertTo-LambekAnswer -Plan $plan -Execution $run -Brief | Should -Be "Done.`nI deleted 1 file (2 bytes)."
    }
}

Describe 'Meaning and logical form' {

    It 'computes the actions a sentence can mean on its reduction: <Text>' -ForEach @(
        @{ Text = 'delete the .log files in C:\Temp'; Meaning = @('files.delete') }
        @{ Text = 'create a function named Get-Report'; Meaning = @('code.generate') }
        @{ Text = 'create a folder named "x" in C:\Temp'; Meaning = @('files.create') }
        @{ Text = 'free 5 GB in C:\Temp'; Meaning = @('files.free') }
        @{ Text = 'free the folder C:\Temp'; Meaning = @() }
    ) {
        $request = ConvertTo-LambekRequest $Text
        $meaning = InModuleScope Lambek -Parameters @{ Request = $request } { Get-LambekMeaning -Grammar $Request.Grammar -Language $Request.Language }
        @($meaning) | Should -Be $Meaning
    }

    It 'gives one logical form to two ways of saying the same thing' {
        $a = (New-LambekPlan 'delete the .log files in C:\Temp').Steps[0]
        $b = (New-LambekPlan 'in C:\Temp, delete the .log files').Steps[0]
        $form = InModuleScope Lambek -Parameters @{ Step = $a } { Get-LambekLogicalForm -Step $Step }
        $form | Should -Be 'delete(all(object and extension(.log) and path(C:\Temp)))'
        InModuleScope Lambek -Parameters @{ Step = $b } { Get-LambekLogicalForm -Step $Step } | Should -Be $form
    }

    It 'writes a superlative as top(n, order, set)' {
        $step = (New-LambekPlan 'delete the 2 largest .log files in C:\Temp').Steps[0]
        InModuleScope Lambek -Parameters @{ Step = $step } { Get-LambekLogicalForm -Step $Step } | Should -Be 'delete(top(2, largest, object and extension(.log) and path(C:\Temp)))'
    }
}

Describe 'Explaining and defining' {

    It 'names a verb borrowed from another language in the language of the sentence' {
        # "suprime" is Spanish: the sentence is French, the verb is read as its Spanish word and said in French
        $plan = New-LambekPlan 'suprime les fichiers .log dans C:\Temp'
        $plan.Steps[0].Action | Should -Be 'files.delete'
        $answer = (Resolve-LambekFollowUp -Plan $plan -Text 'pourquoi ?').Answer
        $answer | Should -BeLike '*Le verbe est « supprimer »*'
        $answer | Should -BeLike '*mot espagnol pour « supprimer »*'
    }

    It 'says its reasoning when asked why' {
        $plan = New-LambekPlan 'supprimme les fichiers .log dans C:\Temp'
        $answer = (Resolve-LambekFollowUp -Plan $plan -Text 'pourquoi ?').Answer
        $answer | Should -BeLike '*Le verbe est « supprimer »*'
        $answer | Should -BeLike '*« supprimme » comme « supprime »*'
        $answer | Should -BeLike '*Forme logique : delete(*'
        $answer | Should -BeLike '*elle redonne exactement ce plan*'
    }

    It 'understands "why?" with its question mark' {
        $plan = New-LambekPlan 'delete the .log files in C:\Temp'
        (Resolve-LambekFollowUp -Plan $plan -Text 'why?').Kind | Should -Be 'explain'
    }

    It 'defines a word from the dictionaries: <Text>' -ForEach @(
        @{ Text = 'what does relocate mean?'; Like = '*move or establish in a new location*' }
        @{ Text = 'que veut dire purge ?'; Like = '*« purge »*WordNet*' }
        @{ Text = 'que signifie zorblax'; Like = '*Je ne trouve pas « zorblax »*' }
    ) {
        $plan = New-LambekPlan $Text
        @($plan.Steps | Where-Object Action).Count | Should -Be 0
        ($plan | ConvertTo-LambekAnswer) | Should -BeLike $Like
    }

    It 'does not take a question about the world for a definition' {
        (New-LambekPlan 'what is the weather').PSObject.Properties['Definition'] | Should -BeNullOrEmpty
    }
}
