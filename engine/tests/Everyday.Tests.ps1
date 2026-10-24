BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    # A conversation of its own, never written down
    function Reset-TestConversation {
        InModuleScope Lambek {
            $script:Told = $null; $script:Board = $null; $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
            $script:Incognito = $true; $script:CategoryPending = $null; $script:LastProofs = $null; $script:ProblemStores = $null
        }
    }
    function Get-TestAnswer {
        param([string] $Text)
        New-LambekPlan -Text $Text | ConvertTo-LambekAnswer
    }
}

AfterAll {
    InModuleScope Lambek { $script:Incognito = $false }
}

Describe 'A question is never kept as something told' {

    BeforeEach { Reset-TestConversation }

    It 'does not note a question no reading answers, in English and in French' {
        Get-TestAnswer 'what is the colour of the moon?' | Should -Not -BeLike 'Noted*'
        # (a question about the world Lambek read about is answered, still never noted)
        Get-TestAnswer 'what is the capital of Spain?' | Should -Be 'The capital of Spain is Madrid, according to Wikidata.'
        Get-TestAnswer "l'école est-elle fermée ?" | Should -Not -BeLike "C'est noté*"
    }

    It 'still notes what is told' {
        Get-TestAnswer 'ma sœur habite à Lyon' | Should -BeLike "C'est noté*Lyon*"
    }
}

Describe 'What Lambek does not understand' {

    It 'says so, and what it can do, instead of offering files and code only' {
        Get-TestAnswer 'patati et patata' | Should -BeLike "Je n'ai pas compris cette phrase.*raisonner*calculer*fichiers et code."
    }

    It 'says it in English to an English message' {
        InModuleScope Lambek { $script:LanguageHint = 'en' }
        try { Get-TestAnswer 'blah blah thingy stuff' | Should -BeLike 'I did not understand that.*reason about it*files and code.' }
        finally { InModuleScope Lambek { $script:LanguageHint = $null } }
    }
}

Describe 'Repair-LambekTyping' {

    It 'reads the shorthand of chats in full' {
        InModuleScope Lambek { (Repair-LambekTyping -Text 'slt' -Language fr).Text } | Should -Be 'salut'
        InModuleScope Lambek { (Repair-LambekTyping -Text 'cmt tu vas' -Language fr).Text } | Should -Be 'comment tu vas'
        InModuleScope Lambek { (Repair-LambekTyping -Text 'thx, idk' -Language en).Text } | Should -Be "thx, I don't know"
    }

    It 'corrects a word one slip from exactly one word of the dictionary, and says it' {
        $repaired = InModuleScope Lambek { Repair-LambekTyping -Text 'quelle est la capitalle de la france ?' -Language fr }
        $repaired.Text | Should -Be 'quelle est la capitale de la france ?'
        $repaired.Changes[0].From | Should -Be 'capitalle'
        $repaired.Changes[0].Sense | Should -Be 'spelling'
    }

    It 'leaves a word close to several words as it is: it does not choose' {
        InModuleScope Lambek { (Repair-LambekTyping -Text 'les fichers du dossier' -Language fr).Changes.Count } | Should -Be 0
    }

    It 'reads a word close to several words in its sentence, when one reading is far likelier: <Text>' -ForEach @(
        @{ Text = 'the .log files in C:\Temp mkst be deleted'; Language = 'en'; Read = 'the .log files in C:\Temp must be deleted' }
        @{ Text = 'please remove thwt event'; Language = 'en'; Read = 'please remove that event' }
        @{ Text = 'fibd the files in C:\Data'; Language = 'en'; Read = 'find the files in C:\Data' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text; Language = $Language } { param($Text, $Language) (Repair-LambekTyping -Text $Text -Language $Language).Text } | Should -BeExactly $Read
    }

    It 'leaves it as it is when the readings stay about as likely ("met" or "mets")' {
        $text = 'metd le rapport.txt dans C:\B'
        InModuleScope Lambek -Parameters @{ Text = $text } { (Repair-LambekTyping -Text $Text -Language fr).Changes.Count } | Should -Be 0
    }

    It 'never reads a frequent word of the language as a slip, even one no dictionary of meanings has' {
        InModuleScope Lambek { (Repair-LambekTyping -Text 'I take the bus when it rains' -Language en).Changes.Count } | Should -Be 0
    }

    It 'chooses the likeliest reading of the whole sentence, and says by how much (Viterbi)' {
        $read = InModuleScope Lambek {
            $model = Get-LambekFluency -Language fr
            $found = $model.Decode('supprime les Xxxx dahs Xxxxxxx', [int[]] @(18), [string[][]] @(, [string[]] @('dais', 'dans')), [double[][]] @(, [double[]] @(0, 0)), (Get-LambekDictionary -Language fr))
            [pscustomobject]@{ Choice = $found[0][0]; Margin = $found[0][1] }
        }
        $read.Choice | Should -Be 1
        $read.Margin | Should -BeGreaterThan 1
    }

    It 'never touches names, paths, file names or known words, nor a word of another language' {
        InModuleScope Lambek { (Repair-LambekTyping -Text 'Pingu is a penguin' -Language en).Changes.Count } | Should -Be 0
        InModuleScope Lambek { (Repair-LambekTyping -Text 'combien font 3/7 + 2/5 ?' -Language en).Changes.Count } | Should -Be 0
        $text = 'supprime Rapportt.txt dans C:\Tempp pour Amiin'
        InModuleScope Lambek -Parameters @{ Text = $text } { (Repair-LambekTyping -Text $Text -Language fr).Text } | Should -BeExactly $text
        InModuleScope Lambek { (Repair-LambekTyping -Text 'ma soeur habite a Lyon' -Language fr).Changes.Count } | Should -Be 0
    }

    It 'finds the forms one slip away in the dictionary' {
        InModuleScope Lambek { @((Get-LambekDictionary -Language fr).Near('capitalle', 'fr', 1)) } | Should -Be @('capitale')
        InModuleScope Lambek { @((Get-LambekDictionary -Language fr).Near('capitale', 'fr', 1)).Count } | Should -Be 0
    }
}

Describe 'Everyday messages' {

    BeforeEach { Reset-TestConversation }

    It 'answers small talk written fast or another way' {
        Get-TestAnswer 'cmt tu vas' | Should -BeLike '*bien*'
        Get-TestAnswer 'comment tu vas ?' | Should -BeLike '*bien*'
        Get-TestAnswer 'tu es un robot ?' | Should -BeLike '*Lambek*'
        Get-TestAnswer 'are you a robot?' | Should -BeLike '*Lambek*'
    }

    It 'calculates through a slip in the operation and with a square root' {
        Get-TestAnswer 'combien font 12 foi 7 ?' | Should -BeLike '*84*'
        Get-TestAnswer 'quelle est la racine carrée de 144 ?' | Should -BeLike '*12*'
    }

    It 'takes no question about the world for a calculation or a definition' {
        Get-TestAnswer 'quelle est la capitale de la France ?' | Should -Not -BeLike '*=*'
        Get-TestAnswer "c'est quoi la capitale de la France ?" | Should -Not -BeLike '*dictionnaires*'
    }

    It 'defines a word asked with "c''est quoi la"' {
        Get-TestAnswer "c'est quoi la photosynthèse ?" | Should -BeLike '*photosynth*'
    }

    It 'solves a problem asked with the pronoun after the verb' {
        Get-TestAnswer 'Paul a 3 pommes de plus que Léa. Léa a 5 pommes. Combien Paul a-t-il de pommes ?' | Should -BeLike 'Paul a 8 pommes*'
        Get-TestAnswer 'Marc a deux fois plus de billes que Tom. Ensemble ils ont 30 billes. Combien Tom a-t-il de billes ?' | Should -BeLike 'Tom a 10 billes*'
    }
}

Describe 'What was told of someone' {

    BeforeEach { Reset-TestConversation }

    It 'reads a name that is also a word ("Marie" is also "marie") as a name' {
        Get-TestAnswer 'Marie est une étudiante.' | Should -BeLike "C'est noté*Marie est une étudiante*"
    }

    It 'answers whether someone is what was told of them' {
        $null = Get-TestAnswer 'Marie est une étudiante.'
        Get-TestAnswer 'Marie est-elle une étudiante ?' | Should -BeLike 'Oui*'
    }

    It 'says it cannot conclude what was not told of them' {
        $null = Get-TestAnswer 'Tom est un chat'
        Get-TestAnswer 'Tom est-il un chien ?' | Should -BeLike 'Je ne peux pas le conclure*'
    }

    It 'leaves how someone is to the memory, which says what was told' {
        $null = Get-TestAnswer 'Minou est noir'
        Get-TestAnswer 'est-ce que Minou est noir ?' | Should -BeLike "D'après ce qui m'a été dit*"
    }

    It 'still deduces from a rule told with "si"' {
        $null = Get-TestAnswer "s'il pleut, je prends le bus"
        $null = Get-TestAnswer 'il pleut'
        Get-TestAnswer 'est-ce que je prends le bus ?' | Should -BeLike "J'en déduis*"
    }
}
