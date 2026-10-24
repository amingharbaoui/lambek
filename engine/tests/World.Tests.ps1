BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    # A small world of its own, in the shape tools/Get-LambekFacts.ps1 writes: what is answered depends on it only
    $lines = @(
        "# lambek-facts-1`tWikidata (CC0)`thttps://qlever.dev/api/wikidata`t2026-10-18"
        "K`tQ142`tcountry`t300", "L`tQ142`tfr`tFrance", "L`tQ142`ten`tFrance", "A`tQ142`tfr`tRépublique française"
        "F`tQ142`tP36`tQ90`t", "F`tQ142`tP37`tQ150`t", "F`tQ142`tP38`tQ4916`t", "F`tQ142`tP1082`t68373433`t2025", "F`tQ142`tP30`tQ46`t"
        "K`tQ90`tcity`t250", "L`tQ90`tfr`tParis", "L`tQ90`ten`tParis", "F`tQ90`tP17`tQ142`t"
        "K`tQ150`tvalue`t0", "L`tQ150`tfr`tfrançais", "L`tQ150`ten`tFrench"
        "K`tQ4916`tvalue`t0", "L`tQ4916`tfr`teuro", "L`tQ4916`ten`teuro"
        "K`tQ46`tvalue`t0", "L`tQ46`tfr`tEurope", "L`tQ46`ten`tEurope"
        "K`tQ535`tperson`t250", "L`tQ535`tfr`tVictor Hugo", "L`tQ535`ten`tVictor Hugo"
        "D`tQ535`tfr`técrivain, poète et homme politique français", "D`tQ535`ten`tFrench poet, novelist and politician"
        "F`tQ535`tP21`tQ6581097`t", "F`tQ535`tP569`t1802-02-26`t11", "F`tQ535`tP570`t1885-05-22`t11", "F`tQ535`tP19`tQ37776`t"
        "K`tQ37776`tcity`t100", "L`tQ37776`tfr`tBesançon", "L`tQ37776`ten`tBesançon"
        "K`tQ180736`tbook`t80", "L`tQ180736`tfr`tLes Misérables", "L`tQ180736`ten`tLes Misérables", "F`tQ180736`tP50`tQ535`t", "F`tQ180736`tP577`t1862-01-01`t9"
        "K`tQ7186`tperson`t300", "L`tQ7186`tfr`tMarie Curie", "L`tQ7186`ten`tMarie Curie", "F`tQ7186`tP21`tQ6581072`t", "F`tQ7186`tP569`t1867-11-07`t11"
        "K`tQ44578`tfilm`t120", "L`tQ44578`tfr`tTitanic", "L`tQ44578`ten`tTitanic", "F`tQ44578`tP57`tQ42574`t", "F`tQ44578`tP577`t1997-11-01`t11"
        "K`tQ42574`tperson`t150", "L`tQ42574`tfr`tJames Cameron", "L`tQ42574`ten`tJames Cameron", "F`tQ42574`tP19`tQ1027634`t"
        "K`tQ1027634`tvalue`t0", "L`tQ1027634`tfr`tKapuskasing", "L`tQ1027634`ten`tKapuskasing"
        "F`tQ90`tP1082`t2100000`t2023", "F`tQ37776`tP17`tQ142`t", "F`tQ37776`tP1082`t120000`t2023"
        "K`tQ183`tcountry`t300", "L`tQ183`tfr`tAllemagne", "L`tQ183`ten`tGermany", "F`tQ183`tP36`tQ64`t", "F`tQ183`tP30`tQ46`t", "F`tQ183`tP1082`t84000000`t2024"
        "K`tQ64`tcity`t250", "L`tQ64`tfr`tBerlin", "L`tQ64`ten`tBerlin", "F`tQ64`tP17`tQ183`t", "F`tQ64`tP1082`t3700000`t2025"
        "K`tQ1469`triver`t108", "L`tQ1469`tfr`tLoire", "L`tQ1469`ten`tLoire", "F`tQ1469`tP17`tQ142`t", "F`tQ1469`tP2043`t1006.0`t"
        "K`tQ584`triver`t190", "L`tQ584`tfr`tRhin", "L`tQ584`ten`tRhine", "F`tQ584`tP17`tQ142`t", "F`tQ584`tP17`tQ183`t", "F`tQ584`tP2043`t1232.7`t"
        "K`tQ583`tmountain`t127", "L`tQ583`tfr`tmont Blanc", "L`tQ583`ten`tMont Blanc", "F`tQ583`tP17`tQ142`t", "F`tQ583`tP2044`t4805.6`t"
        "K`tQ1471`triver`t100", "L`tQ1471`tfr`tSeine", "L`tQ1471`ten`tSeine", "F`tQ1471`tP17`tQ142`t", "F`tQ1471`tP2043`t777.0`t"
        "K`tQ3375`tmountain`t80", "L`tQ3375`tfr`tZugspitze", "L`tQ3375`ten`tZugspitze", "F`tQ3375`tP17`tQ183`t", "F`tQ3375`tP2044`t2962`t"
        "K`tQ520`tmountain`t90", "L`tQ520`tfr`tOlympus Mons", "L`tQ520`ten`tOlympus Mons", "F`tQ520`tP2044`t21229`t"
        "K`tQ458`tvalue`t0", "L`tQ458`tfr`tUnion européenne", "L`tQ458`ten`tEuropean Union", "F`tQ142`tP463`tQ458`t", "F`tQ183`tP463`tQ458`t", "F`tQ142`tP2046`t643801`t"
        "K`tQ1055`tcity`t200", "L`tQ1055`tfr`tHambourg", "L`tQ1055`ten`tHamburg", "F`tQ1055`tP17`tQ183`t", "F`tQ1055`tP1082`t1900000`t2024"
        "K`tQ3052772`tperson`t200", "L`tQ3052772`tfr`tEmmanuel Macron", "L`tQ3052772`ten`tEmmanuel Macron", "F`tQ3052772`tP569`t1977-12-21`t11"
        "K`tQ155`tcountry`t250", "L`tQ155`tfr`tBrésil", "L`tQ155`ten`tBrazil", "F`tQ155`tP37`tQ5146`t", "F`tQ155`tP36`tQ2844`t"
        "K`tQ2844`tcity`t150", "L`tQ2844`tfr`tBrasilia", "L`tQ2844`ten`tBrasília", "F`tQ2844`tP17`tQ155`t"
        "K`tQ5146`tvalue`t0", "L`tQ5146`tfr`tportugais", "L`tQ5146`ten`tPortuguese"
        "K`tQ1033`tcountry`t200", "L`tQ1033`tfr`tNigeria", "L`tQ1033`ten`tNigeria", "F`tQ1033`tP36`tQ3787`t"
        "K`tQ3787`tcity`t120", "L`tQ3787`tfr`tAbuja", "L`tQ3787`ten`tAbuja", "F`tQ3787`tP17`tQ1033`t"
        "K`tQ101`tcity`t150", "L`tQ101`tfr`tMarrakech", "L`tQ101`ten`tMarrakesh", "F`tQ101`tP17`tQ1028`t"
        "K`tQ1028`tcountry`t200", "L`tQ1028`tfr`tMaroc", "L`tQ1028`ten`tMorocco"
        "F`tQ142`tP35`tQ3052772`t", "F`tQ90`tP6`tQ100`t", "K`tQ100`tvalue`t0", "L`tQ100`tfr`tEmmanuel Grégoire", "L`tQ100`ten`tEmmanuel Grégoire"
        "K`tQ30`tcountry`t300", "L`tQ30`tfr`tÉtats-Unis", "L`tQ30`ten`tUnited States", "A`tQ30`ten`tthe United States", "F`tQ30`tP36`tQ61`t"
        "K`tQ61`tcity`t200", "L`tQ61`tfr`tWashington", "L`tQ61`ten`tWashington, D.C.", "F`tQ61`tP17`tQ30`t"
    )
    $path = Join-Path $TestDrive 'world.facts.gz'
    $file = [IO.File]::Create($path)
    $zip = [IO.Compression.GZipStream]::new($file, [IO.Compression.CompressionMode]::Compress)
    $writer = [IO.StreamWriter]::new($zip, [Text.UTF8Encoding]::new($false))
    foreach ($line in $lines) { $writer.Write("$line`n") }
    $writer.Dispose()
    $file.Dispose()
    $script:World = $path

    function Ask {
        param([string] $Text)
        New-LambekPlan $Text | ConvertTo-LambekAnswer
    }
}

Describe 'What Lambek knows of the world' {

    BeforeEach {
        InModuleScope Lambek -Parameters @{ World = $script:World } {
            param($World)
            $script:FactBase = [LambekFacts]::Load($World)
            Clear-LambekTold
            $script:Told = $null
            $script:Incognito = $true
        }
    }
    AfterAll {
        InModuleScope Lambek { $script:FactBase = $null; Clear-LambekTold; $script:Told = $null; $script:Incognito = $false }
    }

    It 'answers a question about the world from what it read, and says where it read it: <Text>' -ForEach @(
        @{ Text = 'quelle est la capitale de la France ?'; Said = "La capitale de la France est Paris, d'après Wikidata." }
        @{ Text = 'quelle est la capitale du nigéria'; Said = "La capitale du Nigeria est Abuja, d'après Wikidata." }
        @{ Text = 'et la capitale du Brésil ?'; Said = "La capitale du Brésil est Brasilia, d'après Wikidata." }
        @{ Text = 'qui a écrit Les Misérables ?'; Said = "C'est Victor Hugo qui a écrit Les Misérables, d'après Wikidata." }
        @{ Text = 'quand est né Victor Hugo ?'; Said = "Victor Hugo est né le 26 février 1802, d'après Wikidata." }
        @{ Text = 'quand est née Marie Curie ?'; Said = "Marie Curie est née le 7 novembre 1867, d'après Wikidata." }
        @{ Text = 'où est né Victor Hugo ?'; Said = "Victor Hugo est né à Besançon, d'après Wikidata." }
        @{ Text = 'quelle langue parle-t-on au Brésil ?'; Said = "Au Brésil, on parle portugais, d'après Wikidata." }
        @{ Text = 'quelle est la monnaie de la France ?'; Said = "La monnaie de la France est l'euro, d'après Wikidata." }
        @{ Text = "combien d'habitants a la France ?"; Said = "La population de la France est de 68$([char] 0x00A0)373$([char] 0x00A0)433 habitants (2025), d'après Wikidata." }
        @{ Text = 'dans quel pays se trouve Marrakech ?'; Said = "Marrakech se trouve au Maroc, d'après Wikidata." }
        @{ Text = 'sur quel continent se trouve la France ?'; Said = "La France se trouve en Europe, d'après Wikidata." }
        @{ Text = 'qui a réalisé Titanic ?'; Said = "C'est James Cameron qui a réalisé Titanic, d'après Wikidata." }
        @{ Text = 'qui est Victor Hugo ?'; Said = "Victor Hugo : écrivain, poète et homme politique français, d'après Wikidata." }
        @{ Text = 'what is the capital of France?'; Said = 'The capital of France is Paris, according to Wikidata.' }
        @{ Text = 'who wrote Les Misérables?'; Said = 'Les Misérables was written by Victor Hugo, according to Wikidata.' }
        @{ Text = 'when was Victor Hugo born?'; Said = 'Victor Hugo was born on February 26, 1802, according to Wikidata.' }
        @{ Text = 'what language do they speak in Brazil?'; Said = 'In Brazil, people speak Portuguese, according to Wikidata.' }
        @{ Text = 'how many people live in France?'; Said = 'The population of France is 68,373,433 (2025), according to Wikidata.' }
    ) {
        Ask $Text | Should -Be $Said
    }

    It 'says a year only as a year' {
        Ask 'quand a été publié Les Misérables ?' | Should -Be "Le livre Les Misérables a été publié en 1862, d'après Wikidata."
    }

    It 'answers yes or no about a fact, and the fact when it is no' {
        Ask 'Paris est-elle la capitale de la France ?' | Should -Be "Oui, Paris est la capitale de la France, d'après Wikidata."
        Ask 'Brasilia est-elle la capitale de la France ?' | Should -Be "Non : la capitale de la France est Paris, d'après Wikidata."
        Ask 'is Paris the capital of France?' | Should -Be 'Yes, Paris is the capital of France, according to Wikidata.'
    }

    It 'finds the thing a fact points at' {
        Ask 'Paris est la capitale de quel pays ?' | Should -Be "Paris est la capitale de la France, d'après Wikidata."
    }

    It 'says nothing when a word of the question is more than one fact: <Text>' -ForEach @(
        @{ Text = 'quelle est la capitale de la France et du Brésil ?' }
        @{ Text = 'quelle était la capitale de la France en 1500 ?' }
        @{ Text = 'who is taller, Victor Hugo or Marie Curie?' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) Resolve-LambekFact -Text $Text } | Should -BeNullOrEmpty
    }

    It 'answers a question made of several facts, each one read: <Text>' -ForEach @(
        @{ Text = 'où est né le réalisateur de Titanic ?'; Said = "C'est James Cameron qui a réalisé Titanic, d'après Wikidata.`nJames Cameron est né à Kapuskasing, d'après Wikidata." }
        @{ Text = 'à quel âge est mort Victor Hugo ?'; Said = "Victor Hugo est mort à 83 ans, d'après Wikidata." }
        @{ Text = 'Victor Hugo est-il né avant Marie Curie ?'; Said = "Oui : Victor Hugo est né le 26 février 1802 ; Marie Curie est née le 7 novembre 1867, d'après Wikidata." }
        @{ Text = 'who is older, Victor Hugo or Marie Curie?'; Said = 'Victor Hugo: Victor Hugo was born on February 26, 1802; Marie Curie was born on November 7, 1867, according to Wikidata.' }
        @{ Text = 'quelle est la ville la plus peuplée de France ?'; Said = "La ville la plus peuplée de France est Paris, avec 2$([char] 0x00A0)100$([char] 0x00A0)000 habitants en 2023, d'après Wikidata." }
        @{ Text = "quelle est la capitale du pays le plus peuplé d'Europe ?"; Said = "Le pays le plus peuplé d'Europe est l'Allemagne, avec 84$([char] 0x00A0)000$([char] 0x00A0)000 habitants en 2024, d'après Wikidata.`nLa capitale de l'Allemagne est Berlin, d'après Wikidata." }
        @{ Text = 'what is the most populous city in Germany?'; Said = 'The most populous city in Germany is Berlin, with 3,700,000 inhabitants in 2025, according to Wikidata.' }
    ) {
        Ask $Text | Should -Be $Said
    }

    It 'answers from the facts of the other kinds of things it read: <Text>' -ForEach @(
        # (a river of France flows in France only: the Rhine flows in Germany too)
        @{ Text = 'quel est le plus long fleuve de France ?'; Said = "Le cours d'eau le plus long de France est la Loire, avec 1$([char] 0x00A0)006 km, d'après Wikidata." }
        # (a mountain of the world is on the Earth, in a country: Olympus Mons is on Mars)
        @{ Text = 'what is the highest mountain in the world?'; Said = 'The highest mountain in the world is Mont Blanc, at 4,806 m, according to Wikidata.' }
        @{ Text = "combien de pays sont membres de l'Union européenne ?"; Said = "2 pays sont membres de l'Union européenne, d'après Wikidata." }
        @{ Text = "la France fait-elle partie de l'Union européenne ?"; Said = "Oui, la France est membre de l'Union européenne, d'après Wikidata." }
        @{ Text = 'quelle est la superficie de la France ?'; Said = "La superficie de la France est de 643$([char] 0x00A0)801 km², d'après Wikidata." }
    ) {
        Ask $Text | Should -Be $Said
    }

    It 'counts only among things it has every one of' {
        InModuleScope Lambek { Resolve-LambekFact -Text 'combien de livres a écrit Victor Hugo ?' } | Should -BeNullOrEmpty
    }

    It 'says who leads a country or a city: <Text>' -ForEach @(
        @{ Text = 'qui est le président de la France ?'; Said = "Le chef de l'État de la France est Emmanuel Macron, d'après Wikidata." }
        @{ Text = 'qui est le maire de Paris ?'; Said = "Le maire de Paris est Emmanuel Grégoire, d'après Wikidata." }
    ) {
        Ask $Text | Should -Be $Said
    }

    It 'says a name with the article it was asked with' {
        Ask 'what is the capital of the United States?' | Should -Be 'The capital of the United States is Washington, D.C., according to Wikidata.'
    }

    It 'asks about the one a role names, not about the role ("quel âge a le président de la France ?")' {
        InModuleScope Lambek { $script:Now = [datetime] '2026-10-19T12:00:00' }
        try {
            Ask 'quel âge a le président de la France ?' | Should -Be (@(
                    "Le chef de l'État de la France est Emmanuel Macron, d'après Wikidata."
                    "Emmanuel Macron a 48 ans, d'après Wikidata."
                ) -join "`n")
        }
        finally { InModuleScope Lambek { $script:Now = $null } }
    }

    It 'gives the age of a living person from the day it is' {
        InModuleScope Lambek { $script:Now = [datetime] '2026-10-19T12:00:00' }
        try { Ask 'how old is Emmanuel Macron?' | Should -Be 'Emmanuel Macron is 48 years old, according to Wikidata.' }
        finally { InModuleScope Lambek { $script:Now = $null } }
    }

    It 'says nothing of several facts it cannot be sure of: <Text>' -ForEach @(
        # (the cities kept are those of 100 000 people or more: the least populous one is not among them)
        @{ Text = 'quelle est la ville la moins peuplée de France ?' }
        # (no death read, and older than anyone alive)
        @{ Text = 'quel âge a Marie Curie ?' }
        @{ Text = 'quand est mort le réalisateur de Titanic ?' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) Resolve-LambekFact -Text $Text } | Should -BeNullOrEmpty
    }

    It 'says where each fact of a question made of several was read when asked why' {
        Ask 'où est né le réalisateur de Titanic ?' | Out-Null
        Ask 'pourquoi ?' | Should -Be (@(
                'Je l''ai lu dans Wikidata (données lues le 18 octobre 2026) :'
                '- C''est James Cameron qui a réalisé Titanic. (Q44578)'
                '- James Cameron est né à Kapuskasing. (Q42574)'
            ) -join "`n")
    }

    It 'never takes what is told for a question about the world' {
        InModuleScope Lambek { Resolve-LambekFact -Text 'la capitale de la France est Lyon' } | Should -BeNullOrEmpty
    }

    It 'puts what it read on the board, as read, with its source and the day of the data' {
        Ask 'quelle est la capitale de la France ?' | Out-Null
        $entry = InModuleScope Lambek { @((Get-LambekBoard).Entries() | Where-Object Source -EQ 'wikidata')[-1] }
        $entry.Status | Should -Be 'read'
        $entry.Day | Should -Be '2026-10-18'
        $entry.Key | Should -Be 'wikidata(P36, Q142, Q90)'
    }

    It 'says where it read an answer when asked why' {
        Ask 'quelle est la capitale de la France ?' | Out-Null
        Ask 'pourquoi ?' | Should -Be (@(
                'Je l''ai lu dans Wikidata (données lues le 18 octobre 2026) :'
                '- La capitale de la France est Paris. (Q142)'
            ) -join "`n")
    }

    It 'says what the user told first, then what it read' {
        New-LambekPlan 'la capitale de la France est Lyon' | Out-Null
        Ask 'quelle est la capitale de la France ?' | Should -Be (@(
                'Vous m''avez dit : « la capitale de la France est Lyon ».'
                'La capitale de la France est Paris, d''après Wikidata.'
            ) -join "`n")
    }

    It 'knows nothing of the world without the file' {
        InModuleScope Lambek { $script:FactBase = $false; Resolve-LambekFact -Text 'quelle est la capitale de la France ?' } | Should -BeNullOrEmpty
    }
}

Describe 'The clock, the door and the register' {

    BeforeEach {
        InModuleScope Lambek { $script:Now = [datetime] '2026-10-19 10:05'; $script:HostState = @{ Plans = [ordered]@{}; Simulations = @{}; Approvals = @{} } }
    }
    AfterAll {
        InModuleScope Lambek { $script:Now = $null; $script:ChatRegister = $null }
    }

    It 'tells the time and the day from the clock of the computer: <Text>' -ForEach @(
        @{ Text = 'quelle heure est-il ?'; Said = "Il est 10 h 05, à l'horloge de cet ordinateur." }
        @{ Text = 'quelle heure est-il à Tokyo ?'; Said = "À l'horloge de cet ordinateur, il est 10 h 05 ; je ne connais pas l'heure des autres endroits." }
        @{ Text = 'quel jour sommes-nous ?'; Said = 'Nous sommes le lundi 19 octobre 2026.' }
        @{ Text = 'what day is it today?'; Said = 'Today is Monday, October 19, 2026.' }
        @{ Text = 'quel jour est le treize décembre ?'; Said = 'Le 13 décembre 2026 est un dimanche.' }
    ) {
        Ask $Text | Should -Be $Said
    }

    It 'calculates what is ordered with its numbers in words: <Text>' -ForEach @(
        @{ Text = 'divisez deux cents par quatre'; Said = '200 / 4 = 50' }
        @{ Text = 'quelle est la racine carré de six cent vingt cinq'; Said = "$([char] 0x221A)625 = 25" }
    ) {
        Ask $Text | Should -Be $Said
    }

    It 'says what it cannot do, and what it can' {
        Ask "qu'est-ce que tu ne sais pas faire ?" | Should -Match "^Je n'ai pas accès à internet"
        Ask 'what can you do?' | Should -Match 'general knowledge questions from Wikidata'
    }

    It 'keeps saying tu in a chat where the user said it' {
        $ask = {
            param([string] $Text)
            $line = ConvertTo-Json -Compress -InputObject ([ordered]@{ id = 1; method = 'ask'; params = [ordered]@{ text = $Text; chat = 'tu'; incognito = $true; language = 'fr' } })
            InModuleScope Lambek -Parameters @{ Line = $line; Audit = (Join-Path $TestDrive 'audit.jsonl') } { param($Line, $Audit) (Invoke-LambekHostRequest -Line $Line -AuditPath $Audit | ConvertFrom-Json).result.answer }
        }
        & $ask 'salut, tu vas bien ?' | Out-Null
        & $ask 'aide' | Should -Match 'Dis ce que tu veux'
        & $ask 'que savez-vous faire ?' | Should -Match 'Dites ce que vous voulez'
    }

    It 'never keeps a question typed without its mark as something told' {
        $plan = New-LambekPlan 'what was the last movie will smith was in'
        @($plan.Steps | Where-Object { $_.Statement }).Count | Should -Be 0
    }

    It 'never takes a question about when something happened for an order' {
        $plan = New-LambekPlan "Quand est-ce que le groupe Guns N' Roses a remporté son premier Billboard Music Award ?"
        $plan.Status | Should -Not -Be 'Ready'
        @($plan.Steps | Where-Object { $_.Action }).Count | Should -Be 0
    }

    It 'reads a word as its synonym from the dictionary only when a folder, a file or an extension is named' {
        $plan = New-LambekPlan 'les Guns N'' Roses ont-ils remporté un prix de musique ?'
        $plan.Status | Should -Not -Be 'Ready'
        @($plan.Steps | Where-Object { $_.Action }).Count | Should -Be 0
        (New-LambekPlan 'relocate the .log files in C:\Temp to D:\Old').Steps[0].Action | Should -Be 'files.move'
    }

    It 'plans nothing on files when no file is named: <Text>' -ForEach @(
        @{ Text = "c'est quelle chanson celle-ci" }
        @{ Text = 'liste moi le stock de apple tout de suite' }
        @{ Text = 'where is new zealand located on a map' }
        @{ Text = 'play the most popular elton john song' }
    ) {
        $plan = New-LambekPlan $Text
        $plan.Status | Should -Not -Be 'Ready'
        @($plan.Steps | Where-Object { $_.Action }).Count | Should -Be 0
    }

    It 'still plans on files named by a word: <Text>' -ForEach @(
        @{ Text = 'liste les fichiers récents' }
        @{ Text = 'show my photos' }
    ) {
        @((New-LambekPlan $Text).Steps | Where-Object { $_.Action -like 'files.*' }).Count | Should -Be 1
    }

    It 'proposes no action for what the router reads as no order' {
        $plan = New-LambekPlan 'when i came back from this place'
        $plan.PSObject.Properties['Suggestion'] | Should -BeNullOrEmpty
    }
}
