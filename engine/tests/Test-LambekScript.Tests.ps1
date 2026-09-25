BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
}

Describe 'Test-LambekScript' {

    Context 'Accepted scripts' {
        It 'accepts an allowed command' {
            (Test-LambekScript -Script "Get-ChildItem -LiteralPath 'C:\Temp'" -AllowedCommand 'Get-ChildItem').IsValid | Should -BeTrue
        }

        It 'accepts a pipeline of allowed commands' {
            $script = "`$items = Get-ChildItem -File`n`$items | Where-Object Length -GT 10 | Remove-Item"
            (Test-LambekScript -Script $script -AllowedCommand 'Get-ChildItem', 'Where-Object', 'Remove-Item').IsValid | Should -BeTrue
        }

        It 'accepts timespan literals' {
            $script = "Get-Date | Where-Object { `$_ -lt ((Get-Date) - [timespan]::FromSeconds(60)) }"
            (Test-LambekScript -Script $script -AllowedCommand 'Get-Date', 'Where-Object').IsValid | Should -BeTrue
        }

        It 'accepts a generated function' {
            $script = "function Get-Report {`n    [CmdletBinding()]`n    param()`n}"
            (Test-LambekScript -Script $script).IsValid | Should -BeTrue
        }
    }

    Context 'Blocked scripts' {
        It 'blocks <Rule> in: <Script>' -ForEach @(
            @{ Script = 'Invoke-Expression "dir"'; Rule = 'CommandNotAllowed' }
            @{ Script = 'Get-ChildItem; Stop-Computer'; Rule = 'CommandNotAllowed' }
            @{ Script = '& $command'; Rule = 'InvocationOperator' }
            @{ Script = '. ./other.ps1'; Rule = 'InvocationOperator' }
            @{ Script = '[System.IO.File]::Delete("C:\a.txt")'; Rule = 'MethodCall' }
            @{ Script = '$x = "a"; $x.Remove(0)'; Rule = 'MethodCall' }
            @{ Script = '[Environment]::UserName'; Rule = 'StaticMember' }
            @{ Script = '$env:PATH'; Rule = 'ScopedVariable' }
            @{ Script = '$global:x = 1'; Rule = 'ScopedVariable' }
            @{ Script = '$ExecutionContext'; Rule = 'VariableNotAllowed' }
            @{ Script = 'Get-ChildItem > C:\out.txt'; Rule = 'FileRedirection' }
            @{ Script = '[System.Net.WebClient]'; Rule = 'TypeNotAllowed' }
            @{ Script = 'Get-ChildItem -Path ('; Rule = 'ParseError' }
        ) {
            $result = Test-LambekScript -Script $Script -AllowedCommand 'Get-ChildItem'
            $result.IsValid | Should -BeFalse
            $result.Violations.Rule | Should -Contain $Rule
        }

        It 'reports the line of each violation' {
            $result = Test-LambekScript -Script "Get-ChildItem`nInvoke-Expression 'x'" -AllowedCommand 'Get-ChildItem'
            $result.Violations[0].Line | Should -Be 2
        }

        It 'never runs the script it checks' {
            $marker = Join-Path $TestDrive 'marker.txt'
            Test-LambekScript -Script "New-Item -Path '$marker'" | Out-Null
            Test-Path $marker | Should -BeFalse
        }
    }
}

Describe 'Safe rendering' {

    It 'escapes quotes so text stays text' {
        InModuleScope Lambek {
            ConvertTo-LambekLiteral -Value "x'; Remove-Item C:\ -Recurse; '" | Should -Be "'x''; Remove-Item C:\ -Recurse; '''"
        }
    }

    It 'keeps an injection attempt inside one string literal' {
        InModuleScope Lambek {
            $script = ConvertTo-LambekScript -Template @('Rename-Item -LiteralPath {{Name}} -NewName {{NewName}}') `
                -Parameters ([ordered]@{ Name = 'a.txt'; NewName = "x'; Remove-Item C:\ -Recurse; '" })

            $check = Test-LambekScript -Script $script -AllowedCommand 'Rename-Item'
            $check.IsValid | Should -BeTrue
        }
    }

    It 'writes numbers and timespans as literals' {
        InModuleScope Lambek {
            ConvertTo-LambekLiteral -Value 5368709120L | Should -Be '5368709120'
            ConvertTo-LambekLiteral -Value ([timespan]::FromDays(1)) | Should -Be '[timespan]::FromSeconds(86400)'
        }
    }

    It 'keeps optional lines only when the parameter is set' {
        InModuleScope Lambek {
            $template = @('?Name A {{Name}}', '!Name B')
            ConvertTo-LambekScript -Template $template -Parameters ([ordered]@{ Name = 'x' }) | Should -Be "A 'x'"
            ConvertTo-LambekScript -Template $template -Parameters ([ordered]@{}) | Should -Be 'B'
        }
    }

    It 'rejects an invalid raw name' {
        InModuleScope Lambek {
            { ConvertTo-LambekScript -Template @('function {{Name!}} {}') -Parameters ([ordered]@{ Name = 'a; b' }) } | Should -Throw
        }
    }

    It 'rejects a missing parameter' {
        InModuleScope Lambek {
            { ConvertTo-LambekScript -Template @('Remove-Item {{Path}}') -Parameters ([ordered]@{}) } | Should -Throw '*needs the parameter*'
        }
    }
}
