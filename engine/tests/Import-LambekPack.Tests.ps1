BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    $packs = "$PSScriptRoot/../../dsl"

    function New-TestPack {
        param([hashtable] $Content)

        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $folder -ItemType Directory | Out-Null
        $Content | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $folder 'pack.json')
        return $folder
    }
}

Describe 'Import-LambekPack' {

    BeforeEach {
        Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    }

    Context 'Valid packs' {
        It 'loads the files pack' {
            $pack = Import-LambekPack -Path "$packs/files"
            $pack.Name | Should -Be 'files'
            $pack.Entities | Should -Contain 'path'
        }

        It 'lists the actions of a pack' {
            $pack = Import-LambekPack -Path "$packs/files"
            $pack.Actions | Should -Contain 'files.delete'
        }

        It 'loads the code pack' {
            $pack = Import-LambekPack -Path "$packs/code"
            $pack.Name | Should -Be 'code'
            $pack.Types | Should -Contain 'a'
        }

        It 'lists every loaded pack' {
            Import-LambekPack -Path "$packs/files" | Out-Null
            Import-LambekPack -Path "$packs/code" | Out-Null
            (Get-LambekPack).Name | Should -Be @('files', 'code')
        }

        It 'replaces a pack loaded twice' {
            Import-LambekPack -Path "$packs/files" | Out-Null
            Import-LambekPack -Path "$packs/files" | Out-Null
            @(Get-LambekPack).Count | Should -Be 1
        }

        It 'adds its entities to requests' {
            (ConvertTo-LambekRequest 'delete C:\Temp').Entities.Type | Should -Not -Contain 'path'
            Import-LambekPack -Path "$packs/files" | Out-Null
            (ConvertTo-LambekRequest 'delete C:\Temp').Entities.Type | Should -Contain 'path'
        }

        It 'adds its vocabulary to requests' {
            (ConvertTo-LambekRequest 'supprime le fichier').Words | Should -Not -Contain 'supprimer'
            Import-LambekPack -Path "$packs/files" | Out-Null
            (ConvertTo-LambekRequest 'supprime le fichier').Words | Should -Contain 'supprimer'
        }
    }

    Context 'Invalid packs' {
        It 'rejects a missing file' {
            { Import-LambekPack -Path (Join-Path $TestDrive 'nothing') } | Should -Throw '*not found*'
        }

        It 'rejects invalid JSON' {
            $folder = Join-Path $TestDrive 'broken'
            New-Item -Path $folder -ItemType Directory | Out-Null
            Set-Content -Path (Join-Path $folder 'pack.json') -Value '{ not json'
            { Import-LambekPack -Path $folder } | Should -Throw '*not valid JSON*'
        }

        It 'rejects a pack without Words' {
            $folder = New-TestPack @{ Name = 'test'; Version = '1.0.0'; Types = @{} }
            { Import-LambekPack -Path $folder } | Should -Throw '*Words*'
        }

        It 'rejects an unknown type' {
            $folder = New-TestPack @{
                Name = 'test'; Version = '1.0.0'; Types = @{}
                Words = @{ en = @{ stop = @('s x^l') } }
            }
            { Import-LambekPack -Path $folder } | Should -Throw '*unknown type*'
        }

        It 'rejects the reserved type s' {
            $folder = New-TestPack @{
                Name = 'test'; Version = '1.0.0'; Types = @{ s = @{ en = 'x' } }
                Words = @{}
            }
            { Import-LambekPack -Path $folder } | Should -Throw '*invalid type name*'
        }

        It 'rejects an invalid entity pattern' {
            $folder = New-TestPack @{
                Name = 'test'; Version = '1.0.0'; Types = @{}; Words = @{}
                Entities = @(@{ Name = 'bad'; Kind = 'text'; Priority = 1; Pattern = '(' })
            }
            { Import-LambekPack -Path $folder } | Should -Throw '*invalid pattern*'
        }

        It 'rejects a unit entity without units' {
            $folder = New-TestPack @{
                Name = 'test'; Version = '1.0.0'; Types = @{}; Words = @{}
                Entities = @(@{ Name = 'weight'; Kind = 'unit'; Priority = 1; Pattern = '\d+' })
            }
            { Import-LambekPack -Path $folder } | Should -Throw '*needs Units*'
        }

        It 'rejects an action id from another pack' {
            $folder = New-TestPack @{
                Name = 'test'; Version = '1.0.0'; Types = @{}; Words = @{}
                Actions = @(@{
                        Id = 'other.run'; Risk = 'low'; Title = @{ en = 'Run' }; Verbs = @('run')
                        Examples = @{ en = @('run it') }; Parameters = @()
                    })
            }
            { Import-LambekPack -Path $folder } | Should -Throw '*must start with*'
        }

        It 'rejects an unknown risk' {
            $folder = New-TestPack @{
                Name = 'test'; Version = '1.0.0'; Types = @{}; Words = @{}
                Actions = @(@{
                        Id = 'test.run'; Risk = 'extreme'; Title = @{ en = 'Run' }; Verbs = @('run')
                        Examples = @{ en = @('run it') }; Parameters = @()
                    })
            }
            { Import-LambekPack -Path $folder } | Should -Throw '*unknown risk*'
        }

        It 'rejects an invalid pack name' {
            $folder = New-TestPack @{ Name = 'My Pack'; Version = '1.0.0'; Types = @{}; Words = @{} }
            { Import-LambekPack -Path $folder } | Should -Throw '*pack name*'
        }
    }
}
