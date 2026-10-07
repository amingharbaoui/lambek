BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
}

Describe 'Words read from PowerShell' {

    It 'reads the aliases of the command an action runs' {
        InModuleScope Lambek {
            $words = Get-LambekCommandWord -Language en
            $words['del'] | Should -Be 'delete'
            $words['ren'] | Should -Be 'rename'
            (Get-LambekCommandWord -Language fr)['del'] | Should -Be 'supprimer'
        }
    }

    It 'leaves out aliases that look like words of a language' {
        InModuleScope Lambek {
            (Get-LambekCommandWord -Language fr).ContainsKey('ni') | Should -BeFalse
        }
    }

    It 'reads a request written with an alias: <Text>' -ForEach @(
        @{ Text = 'del the .tmp files in C:\Temp'; Action = 'files.delete' }
        @{ Text = 'ren report.txt to old.txt'; Action = 'files.rename' }
    ) {
        $plan = New-LambekPlan $Text
        $plan.Status | Should -Be 'Ready'
        $plan.Steps[0].Action | Should -Be $Action
    }
}

Describe 'Folders read from the machine' {

    It 'names the special folders of the user by their spoken name' {
        InModuleScope Lambek {
            $folders = Get-LambekSystemFolder
            foreach ($name in $folders.Keys) {
                $name | Should -Match '^[a-z]+( [a-z]+)*$'
                $path = [Environment]::GetFolderPath($folders[$name], [Environment+SpecialFolderOption]::DoNotVerify)
                $path | Should -BeLike "$([Environment]::GetFolderPath('UserProfile'))*"
            }
        }
    }

    It 'adds the folder names of the packs' {
        InModuleScope Lambek {
            (Get-LambekKnownFolder)['bureau'] | Should -Be 'Desktop'
            (Get-LambekKnownFolder)['telechargements'] | Should -Be 'Downloads'
        }
    }

    It 'reads a folder name with or without accents' {
        (New-LambekPlan 'liste les fichiers dans téléchargements').Steps[0].Parameters.Path | Should -BeLike '*Downloads'
        (New-LambekPlan 'liste les fichiers dans telechargements').Steps[0].Parameters.Path | Should -BeLike '*Downloads'
    }
}

Describe 'Kinds of files read from the machine' {

    It 'gives every kind a list of extensions' {
        InModuleScope Lambek {
            foreach ($kind in 'image', 'video', 'audio', 'document', 'compressed') {
                $extensions = Get-LambekKindExtension -Kind $kind
                $extensions.Count | Should -BeGreaterThan 0
                $extensions | ForEach-Object { $_ | Should -Match '^\.[a-z0-9]+$' }
            }
            Get-LambekKindExtension -Kind 'image' | Should -Contain '.png'
        }
    }

    It 'keeps only the files of the kind named: <Text>' -ForEach @(
        @{ Text = 'delete the images in C:\A'; Kind = 'image' }
        @{ Text = 'déplace les photos de mes téléchargements dans mes images'; Kind = 'image' }
        @{ Text = 'copy the videos in C:\A to D:\B'; Kind = 'video' }
    ) {
        $step = (New-LambekPlan $Text).Steps[0]
        $step.Status | Should -Be 'Ready'
        $step.Parameters.Kind | Should -Be $Kind
        $step.Script | Should -BeLike "*Where-Object Extension -In @('.*"
        $step.Check.IsValid | Should -BeTrue
    }

    It 'keeps the standard list of the pack whatever the machine says' {
        InModuleScope Lambek {
            $saved = Get-LambekSystemVocabulary
            try {
                # A machine that knows .docx as a document, forgets .pdf, and calls .csv a document too
                $script:SystemVocabulary = [pscustomobject]@{ Folders = $saved.Folders; Kinds = @{ document = [string[]] @('.csv', '.docx', '.pages') }; Read = [datetime]::UtcNow }
                $extensions = Get-LambekKindExtension -Kind 'document'
                $extensions | Should -Contain '.pdf'
                $extensions | Should -Contain '.pages'
                $extensions | Should -Not -Contain '.csv'
            }
            finally { $script:SystemVocabulary = $saved }
        }
    }

    It 'reads the kinds of the Windows registry' -Skip:(-not $IsWindows) {
        InModuleScope Lambek {
            $kinds = (Get-LambekSystemVocabulary).Kinds
            foreach ($pair in @(@('image', '.jpg'), @('image', '.png'), @('audio', '.mp3'), @('video', '.mp4'), @('text', '.txt'), @('compressed', '.zip'))) {
                $kinds[$pair[0]] | Should -Contain $pair[1] -Because "the registry gives $($pair[1]) the PerceivedType $($pair[0])"
            }
            # With the pack, no extension is two kinds of media at once
            $seen = @{}
            foreach ($kind in 'image', 'video', 'audio', 'document') {
                foreach ($extension in Get-LambekKindExtension -Kind $kind) {
                    $seen.ContainsKey($extension) | Should -BeFalse -Because "$extension is both $($seen[$extension]) and $kind"
                    $seen[$extension] = $kind
                }
            }
        }
    }

    It 'says the kind in the answer' {
        ConvertTo-LambekAnswer -Plan (New-LambekPlan 'delete the images in C:\A') | Should -BeLike "*delete the images in C:\A*"
    }
}
