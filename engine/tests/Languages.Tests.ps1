BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null

    function Send-ChatTurn {
        param([string] $Text, [string] $Chat)
        $line = @{ id = 1; method = 'ask'; params = @{ text = $Text; chat = $Chat } } | ConvertTo-Json -Compress
        $json = InModuleScope Lambek -Parameters @{ Line = $line; Audit = (Join-Path $TestDrive 'audit.jsonl') } { param($Line, $Audit) Invoke-LambekHostRequest -Line $Line -AuditPath $Audit }
        return ($json | ConvertFrom-Json -AsHashtable).result
    }
}

Describe 'Seven languages' {

    It 'reads a request in <Language>: <Text>' -ForEach @(
        @{ Language = 'es'; Text = 'elimina los archivos .log en C:\Temp'; Action = 'files.delete' }
        @{ Language = 'de'; Text = 'zeige die Dateien in C:\Data'; Action = 'files.list' }
        @{ Language = 'it'; Text = 'copia i file da C:\A a D:\B'; Action = 'files.copy' }
        @{ Language = 'nl'; Text = 'verwijder de .log bestanden in C:\Temp'; Action = 'files.delete' }
        @{ Language = 'pt'; Text = 'liste os arquivos em C:\Data'; Action = 'files.list' }
    ) {
        $plan = New-LambekPlan $Text
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Action | Should -Be $Action
    }

    It 'has a dictionary for every language' {
        foreach ($language in 'de', 'es', 'it', 'nl', 'pt') {
            $dictionary = InModuleScope Lambek -Parameters @{ Language = $language } { param($Language) Get-LambekDictionary -Language $Language }
            $dictionary | Should -Not -BeNullOrEmpty -Because $language
        }
    }

    It 'reads the forms of a word in Spanish, German, Italian, Dutch and Portuguese' {
        $dictionary = InModuleScope Lambek { foreach ($language in 'de', 'es', 'it', 'nl', 'pt') { Get-LambekDictionary -Language $language | Out-Null }; Get-LambekDictionary -Language 'es' }
        @($dictionary.Lemmas('borrando', 'es') | ForEach-Object Lemma) | Should -Contain 'borrar'
        @($dictionary.Lemmas('gelöscht', 'de') | ForEach-Object Lemma) | Should -Contain 'loschen'
        @($dictionary.Lemmas('cancellato', 'it') | ForEach-Object Lemma) | Should -Contain 'cancellare'
    }

    It 'asks about an unknown Dutch word the dictionary knows' {
        $plan = New-LambekPlan 'uitwissen de .log bestanden in C:\Temp'
        $plan.Status | Should -Be 'NeedsInput'
        $plan.Questions[0] | Should -BeLike '*uitwissen*verwijderen*'
    }
}

Describe 'The languages of a conversation' {

    It 'follows the user from one language to another, and keeps it for a message in no language' {
        $chat = [guid]::NewGuid().ToString()
        (Send-ChatTurn 'supprime les fichiers .log dans C:\Temp' $chat).language | Should -Be 'fr'
        (Send-ChatTurn 'ok' $chat).language | Should -Be 'fr'
        (Send-ChatTurn 'list the files in C:\Data' $chat).language | Should -Be 'en'
        (Send-ChatTurn 'C:\Data' $chat).language | Should -Be 'en'
        (Send-ChatTurn 'zeige die Dateien in C:\Data' $chat).language | Should -Be 'de'
        (Send-ChatTurn 'danke' $chat).language | Should -Be 'de'
        (Send-ChatTurn 'elimina los archivos .tmp en C:\Temp' $chat).language | Should -Be 'es'
        (Send-ChatTurn 'C:\Temp' $chat).language | Should -Be 'es'
    }

    It 'answers a sentence that mixes languages in the language of its frame' {
        $chat = [guid]::NewGuid().ToString()
        $result = Send-ChatTurn 'delete les fichiers .bak dans C:\Temp' $chat
        $result.language | Should -Be 'fr'
        $result.status | Should -Be 'Ready'
    }

    It 'never counts a path as a word of a language' {
        InModuleScope Lambek { Get-LambekLanguageToken -Text 'list C:\Data\report.txt in "Mes Documents"' } | Should -Be @('list', 'in')
    }
}
