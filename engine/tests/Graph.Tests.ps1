BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
}

Describe 'Find-LambekCycle (Tarjan)' {

    It 'finds no cycle in a chain' {
        InModuleScope Lambek {
            $edges = @([pscustomobject]@{ From = 0; To = 1 }, [pscustomobject]@{ From = 1; To = 2 })
            (Find-LambekCycle -NodeCount 3 -Edges $edges).Count | Should -Be 0
        }
    }

    It 'finds a cycle of two nodes' {
        InModuleScope Lambek {
            $edges = @([pscustomobject]@{ From = 0; To = 1 }, [pscustomobject]@{ From = 1; To = 0 })
            $cycles = Find-LambekCycle -NodeCount 2 -Edges $edges
            $cycles.Count | Should -Be 1
            $cycles[0] | Should -Be @(0, 1)
        }
    }

    It 'finds a node that points to itself' {
        InModuleScope Lambek {
            $cycles = Find-LambekCycle -NodeCount 2 -Edges @([pscustomobject]@{ From = 1; To = 1 })
            $cycles.Count | Should -Be 1
            $cycles[0] | Should -Be @(1)
        }
    }

    It 'finds two separate cycles' {
        InModuleScope Lambek {
            $edges = @(
                [pscustomobject]@{ From = 0; To = 1 }, [pscustomobject]@{ From = 1; To = 2 }, [pscustomobject]@{ From = 2; To = 0 }
                [pscustomobject]@{ From = 3; To = 4 }, [pscustomobject]@{ From = 4; To = 3 }
                [pscustomobject]@{ From = 2; To = 3 }
            )
            $cycles = Find-LambekCycle -NodeCount 6 -Edges $edges
            $cycles.Count | Should -Be 2
        }
    }

    It 'handles a graph without edges' {
        InModuleScope Lambek {
            (Find-LambekCycle -NodeCount 3 -Edges @()).Count | Should -Be 0
        }
    }
}

Describe 'Get-LambekTopologicalOrder (Kahn)' {

    It 'orders a chain' {
        InModuleScope Lambek {
            $edges = @([pscustomobject]@{ From = 2; To = 0 }, [pscustomobject]@{ From = 0; To = 1 })
            $result = Get-LambekTopologicalOrder -NodeCount 3 -Edges $edges
            $result.IsComplete | Should -BeTrue
            $result.Order | Should -Be @(2, 0, 1)
        }
    }

    It 'groups independent nodes on the same level' {
        InModuleScope Lambek {
            $edges = @([pscustomobject]@{ From = 0; To = 2 }, [pscustomobject]@{ From = 1; To = 2 })
            $result = Get-LambekTopologicalOrder -NodeCount 3 -Edges $edges
            $result.Levels.Count | Should -Be 2
            $result.Levels[0] | Should -Be @(0, 1)
            $result.Levels[1] | Should -Be @(2)
        }
    }

    It 'keeps the original order when nothing depends on anything' {
        InModuleScope Lambek {
            (Get-LambekTopologicalOrder -NodeCount 4 -Edges @()).Order | Should -Be @(0, 1, 2, 3)
        }
    }

    It 'reports an incomplete order when there is a cycle' {
        InModuleScope Lambek {
            $edges = @([pscustomobject]@{ From = 0; To = 1 }, [pscustomobject]@{ From = 1; To = 0 })
            (Get-LambekTopologicalOrder -NodeCount 2 -Edges $edges).IsComplete | Should -BeFalse
        }
    }
}

Describe 'Test-LambekPathOverlap' {

    It 'returns <Expected> for <A> and <B>' -ForEach @(
        @{ A = 'C:\Temp'; B = 'C:\Temp'; Expected = $true }
        @{ A = 'C:\Temp'; B = 'c:\temp\'; Expected = $true }
        @{ A = 'C:\Temp'; B = 'C:\Temp\Logs'; Expected = $true }
        @{ A = 'C:\Temp\Logs'; B = 'C:\Temp'; Expected = $true }
        @{ A = 'C:\Temp'; B = 'C:\Temp2'; Expected = $false }
        @{ A = 'C:\Temp'; B = 'D:\Temp'; Expected = $false }
    ) {
        InModuleScope Lambek -Parameters $_ {
            Test-LambekPathOverlap -PathA $A -PathB $B | Should -Be $Expected
        }
    }
}

Describe 'Split-LambekClause' {

    It 'splits "<Text>" into <Count> clauses' -ForEach @(
        @{ Text = 'list the files'; Count = 1 }
        @{ Text = 'create the folder then move the files'; Count = 2 }
        @{ Text = 'a, then b and then c; d'; Count = 4 }
        @{ Text = 'cree le dossier puis deplace les fichiers ensuite supprime'; Count = 3 }
    ) {
        InModuleScope Lambek -Parameters $_ {
            @(Split-LambekClause -Text $Text).Count | Should -Be $Count
        }
    }

    It 'does not split inside quotes' {
        InModuleScope Lambek {
            $clauses = @(Split-LambekClause -Text 'rename a.txt to "x; then y"')
            $clauses.Count | Should -Be 1
            $clauses[0] | Should -Be 'rename a.txt to "x; then y"'
        }
    }
}
