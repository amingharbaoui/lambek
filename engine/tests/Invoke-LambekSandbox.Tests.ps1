BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
}

Describe 'Invoke-LambekSandbox' {

    BeforeEach {
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $folder -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path $folder 'a.log') -Value 'a'
        Set-Content -Path (Join-Path $folder 'b.tmp') -Value 'b'
        $script = "`$items = Get-ChildItem -LiteralPath '$folder' -File`n`$items = `$items | Where-Object Extension -EQ '.log'`n`$items | Remove-Item"
        $commands = @('Get-ChildItem', 'Where-Object', 'Remove-Item')
    }

    It 'changes nothing in simulation' {
        InModuleScope Lambek -Parameters @{ Script = $script; Commands = $commands } {
            $result = Invoke-LambekSandbox -Script $Script -Commands $Commands -Simulate
            $result.Succeeded | Should -BeTrue -Because $result.Error
            $result.Items.Count | Should -Be 1
        }
        Test-Path (Join-Path $folder 'a.log') | Should -BeTrue
    }

    It 'runs the script for real' {
        InModuleScope Lambek -Parameters @{ Script = $script; Commands = $commands } {
            $result = Invoke-LambekSandbox -Script $Script -Commands $Commands
            $result.Succeeded | Should -BeTrue -Because $result.Error
        }
        Test-Path (Join-Path $folder 'a.log') | Should -BeFalse
        Test-Path (Join-Path $folder 'b.tmp') | Should -BeTrue
    }

    It 'does not know commands outside the list' {
        InModuleScope Lambek {
            $result = Invoke-LambekSandbox -Script 'Stop-Process -Id 1' -Commands @('Get-ChildItem')
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -BeLike "*Stop-Process*not recognized*"
        }
    }

    It 'cannot start an external program' {
        InModuleScope Lambek {
            $program = 'hostname'
            if ($IsWindows) { $program = 'whoami' }
            $result = Invoke-LambekSandbox -Script $program -Commands @('Get-ChildItem')
            $result.Succeeded | Should -BeFalse
        }
    }

    It 'hides built-in commands that are not in the list' {
        InModuleScope Lambek {
            $result = Invoke-LambekSandbox -Script 'Get-Process' -Commands @('Get-ChildItem')
            $result.Succeeded | Should -BeFalse
        }
    }

    It 'blocks .NET calls with the constrained language mode' {
        InModuleScope Lambek {
            $result = Invoke-LambekSandbox -Script '[System.IO.Directory]::GetFiles("/")' -Commands @('Get-ChildItem')
            $result.Succeeded | Should -BeFalse
        }
    }

    It 'reports a clear error' {
        InModuleScope Lambek {
            $result = Invoke-LambekSandbox -Script "Get-ChildItem -LiteralPath '/does/not/exist'" -Commands @('Get-ChildItem')
            $result.Succeeded | Should -BeFalse
            $result.Error | Should -BeLike 'Cannot find path*'
        }
    }
}
