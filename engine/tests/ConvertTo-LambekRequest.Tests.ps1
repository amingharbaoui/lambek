BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
}

Describe 'ConvertTo-LambekRequest' {

    Context 'Entities in English' {
        BeforeAll {
            $request = ConvertTo-LambekRequest 'Delete the files older than 30 days in C:\Temp larger than 5 GB'
        }

        It 'finds three entities' {
            $request.Entities.Count | Should -Be 3
        }

        It 'converts the size to bytes' {
            $size = $request.Entities | Where-Object Type -EQ 'size'
            $size.Value | Should -Be 5GB
        }

        It 'converts the duration to a timespan' {
            $duration = $request.Entities | Where-Object Type -EQ 'duration'
            $duration.Value | Should -Be ([timespan]::FromDays(30))
        }

        It 'keeps the path exactly as typed' {
            $path = $request.Entities | Where-Object Type -EQ 'path'
            $path.Value | Should -BeExactly 'C:\Temp'
        }

        It 'replaces entities with tags' {
            $request.Terms | Should -Contain '_size_'
            $request.Terms | Should -Contain '_duration_'
            $request.Terms | Should -Contain '_path_'
        }
    }

    Context 'Entities in French' {
        BeforeAll {
            $request = ConvertTo-LambekRequest 'supprime les fichiers .log de plus de 5 Go dans "D:\Mes Logs"'
        }

        It 'detects French' {
            $request.Language | Should -Be 'fr'
        }

        It 'uses base forms' {
            $request.Terms | Should -Contain 'supprimer'
            $request.Terms | Should -Contain 'fichier'
        }

        It 'reads a quoted path with spaces' {
            $quoted = $request.Entities | Where-Object Type -EQ 'quoted'
            $quoted.Value | Should -BeExactly 'D:\Mes Logs'
        }

        It 'reads a path without quotes: <Text>' -ForEach @(
            @{ Text = 'list the files in C:\Program Files\App\logs'; Path = 'C:\Program Files\App\logs' }
            @{ Text = 'move the .log files in C:\Temp to D:\Archive'; Path = 'C:\Temp' }
            @{ Text = 'list the files in C:\Temp.'; Path = 'C:\Temp' }
            @{ Text = 'list the files in /var/log/app'; Path = '/var/log/app' }
            @{ Text = 'delete the files in .\old'; Path = '.\old' }
            @{ Text = 'list the files in C:/Temp/logs'; Path = 'C:\Temp\logs' }
            @{ Text = 'delete the .log files older than 30 days in C:/Users/RUNNER~1/AppData/Local/Temp'; Path = 'C:\Users\RUNNER~1\AppData\Local\Temp' }
        ) {
            ((ConvertTo-LambekRequest $Text).Entities | Where-Object Type -EQ 'path')[0].Value | Should -Be $Path
        }

        It 'expands the home folder' {
            $home2 = [Environment]::GetFolderPath('UserProfile')
            ((ConvertTo-LambekRequest 'list the files in ~/Documents').Entities | Where-Object Type -EQ 'path').Value | Should -Be "$home2/Documents"
        }

        It 'does not read a word pair as a path' {
            (ConvertTo-LambekRequest 'copy and/or move').Entities | Should -BeNullOrEmpty
        }

        It 'reads a French size unit' {
            $size = $request.Entities | Where-Object Type -EQ 'size'
            $size.Value | Should -Be 5GB
        }

        It 'reads an extension' {
            $extension = $request.Entities | Where-Object Type -EQ 'extension'
            $extension.Value | Should -Be '.log'
        }
    }

    Context 'Universal entities' {
        It 'reads an email address' {
            $email = (ConvertTo-LambekRequest 'send the report to Sarah.Doe@Example.com').Entities | Where-Object Type -EQ 'email'
            $email.Value | Should -Be 'sarah.doe@example.com'
        }

        It 'reads a url' {
            $url = (ConvertTo-LambekRequest 'download https://example.com/data.csv').Entities | Where-Object Type -EQ 'url'
            $url.Value | Should -Be 'https://example.com/data.csv'
        }

        It 'reads a file name' {
            $file = (ConvertTo-LambekRequest 'delete report.txt').Entities | Where-Object Type -EQ 'filename'
            $file.Value | Should -Be 'report.txt'
        }

        It 'does not read a decimal size as a file name' {
            $request = ConvertTo-LambekRequest 'files larger than 5.5 GB'
            ($request.Entities | Where-Object Type -EQ 'size').Value | Should -Be ([long] (5.5 * 1GB))
            ($request.Entities | Where-Object Type -EQ 'filename') | Should -BeNullOrEmpty
        }
    }

    Context 'Unicode' {
        It 'removes accents' {
            $text = 'arr{0}te le processus' -f [char] 0x00EA
            (ConvertTo-LambekRequest $text).Normalized | Should -Be 'arrete le processus'
        }

        It 'splits words on apostrophes' {
            $request = ConvertTo-LambekRequest "supprime l'ancien fichier"
            $request.Terms | Should -Contain 'ancien'
        }

        It 'treats a curly apostrophe like a straight one' {
            $curly = ConvertTo-LambekRequest ('supprime l{0}ancien fichier' -f [char] 0x2019)
            $straight = ConvertTo-LambekRequest "supprime l'ancien fichier"
            $curly.Hash | Should -Be $straight.Hash
        }

        It 'reads French quotes' {
            $text = 'copie {0}rapport final{1} vers D:\Archive' -f [char] 0x00AB, [char] 0x00BB
            $quoted = (ConvertTo-LambekRequest $text).Entities | Where-Object Type -EQ 'quoted'
            $quoted.Value | Should -BeExactly 'rapport final'
        }

        It 'reads an accented duration unit' {
            $text = 'supprime les fichiers de plus de 2 ann{0}es' -f [char] 0x00E9
            $duration = (ConvertTo-LambekRequest $text).Entities | Where-Object Type -EQ 'duration'
            $duration.Value | Should -Be ([timespan]::FromDays(730))
        }
    }

    Context 'Determinism' {
        It 'gives the same hash for different case and spacing' {
            $first = ConvertTo-LambekRequest 'Delete   the OLD files'
            $second = ConvertTo-LambekRequest 'delete the old files'
            $first.Hash | Should -Be $second.Hash
        }

        It 'gives another hash for another request' {
            $first = ConvertTo-LambekRequest 'delete the old files'
            $second = ConvertTo-LambekRequest 'copy the old files'
            $first.Hash | Should -Not -Be $second.Hash
        }

        It 'gives the same hash on every run' {
            $hashes = 1..20 | ForEach-Object { (ConvertTo-LambekRequest 'stop the service').Hash }
            ($hashes | Select-Object -Unique).Count | Should -Be 1
        }
    }

    Context 'Folders of the user' {
        It 'turns <Text> into a folder of the user' -ForEach @(
            @{ Text = 'list the files in Documents'; Folder = 'MyDocuments' }
            @{ Text = 'cree un fichier nomme a.txt sur le bureau'; Folder = 'Desktop' }
            @{ Text = 'move the .log files to the desktop'; Folder = 'Desktop' }
        ) {
            $path = (ConvertTo-LambekRequest $Text).Entities | Where-Object Type -EQ 'path'
            $expected = [Environment]::GetFolderPath($Folder)
            if (-not $expected) { $expected = Join-Path ([Environment]::GetFolderPath('UserProfile')) $Folder.Replace('My', '') }
            $path.Value | Should -Be $expected
        }

        It 'finds the downloads folder in French' {
            $path = (ConvertTo-LambekRequest 'supprime les fichiers .tmp dans mes téléchargements').Entities | Where-Object Type -EQ 'path'
            $path.Value | Should -Be (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads')
        }

        It 'keeps entities in the order of the sentence' {
            $paths = @((ConvertTo-LambekRequest 'move the .log files in C:\Temp to Downloads').Entities | Where-Object Type -EQ 'path')
            $paths[0].Value | Should -Be 'C:\Temp'
            $paths[1].Value | Should -Be (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads')
        }

        It 'keeps the word as a word without a place before it' {
            $request = ConvertTo-LambekRequest 'list the documents'
            @($request.Entities | Where-Object Type -EQ 'path').Count | Should -Be 0
        }
    }

    Context 'Input' {
        It 'uses the PowerShell parser' {
            (ConvertTo-LambekRequest 'list the running processes').Tokenizer | Should -Be 'PowerShellParser'
        }

        It 'rejects an empty text' {
            { ConvertTo-LambekRequest '' } | Should -Throw
        }

        It 'rejects a text over 2000 characters' {
            { ConvertTo-LambekRequest ('a' * 2001) } | Should -Throw
        }

        It 'accepts pipeline input' {
            $requests = 'stop the service', 'arrete le service' | ConvertTo-LambekRequest
            $requests.Count | Should -Be 2
        }

        It 'returns terms as an array for a single word' {
            (ConvertTo-LambekRequest 'shutdown').Terms.Count | Should -Be 1
        }

        It 'rejects a language that is not available' {
            { ConvertTo-LambekRequest 'delete the file' -Language 'xx' } | Should -Throw
        }

        It 'keeps stop words in Words but not in Terms' {
            $request = ConvertTo-LambekRequest 'move the files in C:\Temp'
            $request.Words | Should -Contain 'in'
            $request.Terms | Should -Not -Contain 'in'
        }
    }
}
