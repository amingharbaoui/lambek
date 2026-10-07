BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
    $dictionary = InModuleScope Lambek { Get-LambekDictionary -Language 'fr'; $null = Get-LambekDictionary -Language 'en' } | Select-Object -Last 1
}

Describe 'Dictionaries' {

    It 'loads WordNet, WOLF and Lefff, with their sources' {
        $dictionary.Languages | Should -Contain 'fr'
        $dictionary.Languages | Should -Contain 'en'
        ($dictionary.Sources -join ' ') | Should -BeLike '*Open English WordNet*'
        ($dictionary.Sources -join ' ') | Should -BeLike '*WOLF*'
        ($dictionary.Sources -join ' ') | Should -BeLike '*Lefff*'
    }

    It 'reads a form back to its lemma: <Form>' -ForEach @(
        @{ Form = 'supprimons'; Language = 'fr'; Lemma = 'supprimer'; Pos = 'v' }
        @{ Form = 'effaçons'; Language = 'fr'; Lemma = 'effacer'; Pos = 'v' }
        @{ Form = 'fichiers'; Language = 'fr'; Lemma = 'fichier'; Pos = 'n' }
        @{ Form = 'copied'; Language = 'en'; Lemma = 'copy'; Pos = 'v' }
        @{ Form = 'stopped'; Language = 'en'; Lemma = 'stop'; Pos = 'v' }
        @{ Form = 'ran'; Language = 'en'; Lemma = 'run'; Pos = 'v' }
    ) {
        $lemmas = @($dictionary.Lemmas($Form, $Language) | Where-Object Pos -EQ $Pos | ForEach-Object Lemma)
        $lemmas | Should -Contain $Lemma
    }

    It 'gives the features of a French form' {
        $reading = @($dictionary.Lemmas('supprimons', 'fr') | Where-Object Pos -EQ 'v')
        $reading.Tag | Should -Contain 'P1p'
    }

    It 'gives the forms of a lemma to speak with' {
        $dictionary.Forms('supprimer', 'fr', 'v', 'P3s') | Should -Contain 'supprime'
        $dictionary.Forms('déplacer', 'fr', 'v', 'Kms') | Should -Contain 'déplacé'
    }

    It 'finds the known words a word leads to, and how: <Word>' -ForEach @(
        @{ Word = 'enumerate'; Known = 'list'; Relation = 'hypo' }
        @{ Word = 'relocate'; Known = 'move'; Relation = 'hyper' }
        @{ Word = 'get_rid_of'; Known = 'remove'; Relation = 'synonym' }
    ) {
        $words = [System.Collections.Generic.HashSet[string]]::new([string[]] @('list', 'move', 'remove', 'delete', 'copy'))
        $found = @($dictionary.Related($Word, 'en', 'v', $words, 1) | Where-Object Word -EQ $Known)
        $found.Count | Should -Be 1
        $found[0].Relation | Should -Be $Relation
    }

    It 'measures Wu-Palmer similarity: a synset with itself is 1' {
        $synset = $dictionary.Senses('delete', 'en', 'v')[0]
        $dictionary.WuPalmer($synset, $synset) | Should -Be 1
        $dictionary.WuPalmer($synset, $dictionary.Senses('swim', 'en', 'v')[0]) | Should -BeLessThan 0.5
    }

    It 'keeps only the senses the words of an action agree on' {
        InModuleScope Lambek {
            $domain = Get-LambekDomainSense -Language 'en'
            $domain['delete'].Count | Should -BeGreaterThan 0
            # "kill" reaches "erase" only through the sense "remove from existence", which no file action means
            $vocabulary = (Get-LambekLexicon -Language 'en').Vocabulary
            @([LambekDictionary]::Shared.Related('kill', 'en', 'v', $vocabulary, $domain, 1)).Count | Should -Be 0
            @([LambekDictionary]::Shared.Related('transport', 'en', 'v', $vocabulary, $domain, 1)).Word | Should -Contain 'transfer'
        }
    }

    It 'gives the same answer every time' {
        $first = ($dictionary.Related('transport', 'en', 'v', [string[]] @('transfer', 'move'), 1) | ForEach-Object { "$($_.Word)|$($_.Synset)|$($_.Rank)" }) -join ';'
        $again = ($dictionary.Related('transport', 'en', 'v', [string[]] @('transfer', 'move'), 1) | ForEach-Object { "$($_.Word)|$($_.Synset)|$($_.Rank)" }) -join ';'
        $first | Should -Be $again
        $first | Should -Not -BeNullOrEmpty
    }
}

Describe 'Reading with the dictionaries' {

    BeforeEach {
        $words = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        InModuleScope Lambek -Parameters @{ Path = $words } { $script:LearnedPath = $Path; $script:LearnedWords = $null; $script:LexiconCache.Clear(); $script:ActionIndexCache.Clear() }
    }

    It 'reads any form of a known verb: <Text>' -ForEach @(
        @{ Text = 'supprimons les fichiers .log dans C:\Temp'; Action = 'files.delete' }
        @{ Text = 'déplaçons les fichiers de C:\A vers D:\B'; Action = 'files.move' }
        @{ Text = 'copions rapport.txt vers D:\Backup'; Action = 'files.copy' }
        @{ Text = 'listons les fichiers dans C:\Data'; Action = 'files.list' }
    ) {
        $plan = New-LambekPlan $Text
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Action | Should -Be $Action
    }

    It 'asks before reading a synonym of a change, then reads it on yes' {
        $plan = New-LambekPlan 'transport the files in C:\A to D:\B'
        $plan.Status | Should -Be 'NeedsInput'
        $plan.Questions[0] | Should -BeLike '*"transport"*"transfer"*'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text 'yes'
        $reply.Plan.Status | Should -Be 'Ready'
        $reply.Plan.Steps[0].Action | Should -Be 'files.move'
    }

    It 'only proposes a meaning next to a known word, then learns it on yes' {
        $plan = New-LambekPlan 'catalog the files in C:\Data'
        $plan.Status | Should -Be 'NeedsInput'
        $plan.Questions[0] | Should -BeLike '*"catalog"*"sort"*'
        $reply = Resolve-LambekFollowUp -Plan $plan -Text 'yes'
        $reply.Plan.Status | Should -Be 'Ready'
        $reply.Plan.Steps[0].Action | Should -Be 'files.list'
        $reply.Answer | Should -BeLike '*"catalog" means "sort"*'
        (New-LambekPlan 'catalog the files in C:\Data').Status | Should -Be 'Ready'
    }

    It 'never acts on a sense no file action means: <Text>' -ForEach @(
        @{ Text = 'kill the .log files in C:\Temp' }
        @{ Text = 'play some music' }
        @{ Text = 'tue les fichiers .log dans C:\Temp' }
    ) {
        (New-LambekPlan $Text).Status | Should -Not -Be 'Ready'
    }

    It 'reads phrases the packs rewrite: <Text>' -ForEach @(
        @{ Text = 'get rid of the .tmp files in C:\Temp'; Action = 'files.delete' }
        @{ Text = 'débarrasse-toi des .tmp dans C:\Temp'; Action = 'files.delete' }
        @{ Text = 'look for the .pdf files in C:\Docs'; Action = 'files.list' }
    ) {
        $plan = New-LambekPlan $Text
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Action | Should -Be $Action
    }

    It 'still works without the dictionaries' {
        InModuleScope Lambek -Parameters @{ Folder = (Join-Path $TestDrive 'none') } { $script:DictionaryPath = $Folder; $script:DomainSenseCache.Clear() }
        try {
            (New-LambekPlan 'delete the .log files in C:\Temp').Status | Should -Be 'Ready'
            (New-LambekPlan 'transport the files in C:\A to D:\B').Status | Should -Not -Be 'Ready'
        }
        finally {
            InModuleScope Lambek { $script:DictionaryPath = Join-Path (Split-Path (Get-Module Lambek).Path) 'Data/Dictionaries'; $script:DomainSenseCache.Clear() }
        }
    }
}

Describe 'Find-LambekWord' {

    It 'gives the senses of a word with their definitions' {
        $senses = @(Find-LambekWord -Word relocate -Language en)
        $senses.Count | Should -BeGreaterThan 0
        $senses[0].Lemma | Should -Be 'relocate'
        $senses[0].Definition | Should -Not -BeNullOrEmpty
        @($senses | ForEach-Object Broader) | Should -Contain 'move'
    }

    It 'reads a French form, then gives its synonyms' {
        $senses = @(Find-LambekWord -Word 'éliminons' -Language fr)
        @($senses | ForEach-Object Lemma) | Should -Contain 'éliminer'
        @($senses | ForEach-Object Synonyms) | Should -Contain 'supprimer'
    }

    It 'looks up a phrase' {
        @(Find-LambekWord -Word 'get rid of' -Language en | ForEach-Object Synonyms) | Should -Contain 'remove'
    }
}
