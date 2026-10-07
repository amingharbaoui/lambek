BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
}

Describe 'One file, but which one' {

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        'a' | Set-Content -LiteralPath (Join-Path $root 'a.jpg')
        'n' | Set-Content -LiteralPath (Join-Path $root 'notes.txt')
    }

    It 'goes ahead when the folder holds only one such file' {
        $plan = New-LambekPlan "deplace mon image qui est dans ""$root"" vers C:\Out"
        $plan.Status | Should -Be 'Ready'
    }

    It 'asks which one when the folder holds several: <Text>' -ForEach @(
        @{ Text = 'deplace mon image qui est dans "{0}" vers C:\Out'; Question = 'Quel fichier exactement ? Donnez son nom, ou dites le plus récent, ancien, gros ou petit.' }
        @{ Text = 'delete the picture in "{0}"'; Question = 'Which file exactly? Give its name, or say the newest, oldest, largest or smallest.' }
    ) {
        'b' | Set-Content -LiteralPath (Join-Path $root 'b.png')
        $plan = New-LambekPlan ($Text -f $root)
        $plan.Status | Should -Be 'NeedsInput'
        $plan.Steps[0].Questions | Should -Contain $Question
    }

    It 'does not ask with a plural, an order, a name or "all": <Text>' -ForEach @(
        @{ Text = 'deplace les images de "{0}" vers C:\Out' }
        @{ Text = 'deplace l image la plus récente de "{0}" vers C:\Out' }
        @{ Text = 'deplace le fichier a.jpg de "{0}" vers C:\Out' }
        @{ Text = 'deplace toutes mes images de "{0}" vers C:\Out' }
    ) {
        'b' | Set-Content -LiteralPath (Join-Path $root 'b.png')
        (New-LambekPlan ($Text -f $root)).Status | Should -Be 'Ready'
    }

    It 'reads the reply: <Reply>' -ForEach @(
        @{ Reply = 'la plus récente'; Name = 'Count'; Value = 1 }
        @{ Reply = 'the newest'; Name = 'Order'; Value = 'newest' }
        @{ Reply = 'b.png'; Name = 'Name'; Value = 'b.png' }
        @{ Reply = 'les 2 plus grosses'; Name = 'Count'; Value = 2 }
        @{ Reply = 'toutes'; Name = 'Kind'; Value = 'image' }
    ) {
        'b' | Set-Content -LiteralPath (Join-Path $root 'b.png')
        $plan = New-LambekPlan "deplace mon image qui est dans ""$root"" vers C:\Out"
        $reply = Resolve-LambekFollowUp -Plan $plan -Text $Reply
        $reply.Kind | Should -Be 'edit'
        $reply.Plan.Status | Should -Be 'Ready'
        $reply.Plan.Steps[0].Parameters[$Name] | Should -Be $Value
    }

    It 'says one file among the kind' {
        $plan = New-LambekPlan "deplace l image la plus récente de ""$root"" vers C:\Out"
        (ConvertTo-LambekAnswer -Plan $plan).Split("`n")[0] | Should -Be "Je vais déplacer le fichier le plus récent parmi les images de $root vers C:\Out."
    }
}

Describe 'Files left from an older version' {

    It 'refuses to load when a function is in two files' {
        $copy = Join-Path $TestDrive 'Lambek'
        Copy-Item -Path "$PSScriptRoot/../Lambek" -Destination $copy -Recurse
        'function ConvertFrom-LambekLogic { }' | Set-Content -LiteralPath (Join-Path $copy 'Private/LambekLogic.ps1')
        { Import-Module (Join-Path $copy 'Lambek.psd1') -Force -ErrorAction Stop } | Should -Throw '*ConvertFrom-LambekLogic*older version*'
        Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    }
}
