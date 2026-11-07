BeforeAll {
    # Every place of the engine that makes a plan of words, approves one or runs one, as "command <- function"
    function Get-PlanCall {
        $root = Join-Path $PSScriptRoot '../Lambek'
        foreach ($file in Get-ChildItem -Path $root -Recurse -Filter *.ps1) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $null)
            $calls = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -in 'New-LambekPlan', 'Approve-LambekPlan', 'Invoke-LambekPlan'
                }, $true)
            foreach ($call in $calls) {
                $owner = $call.Parent
                while ($owner -and $owner -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $owner = $owner.Parent }
                $simulated = @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Simulate' }).Count -gt 0
                [pscustomobject]@{
                    Command   = $call.GetCommandName()
                    Owner     = $(if ($owner) { $owner.Name } else { $file.Name })
                    Simulated = $simulated
                }
            }
        }
    }
}

Describe 'Only the words of the user act' {

    # A sentence Lambek reads (a file, the result of a tool, a page, a text it learns from) is never an order: only the
    # message the user writes makes a plan, and only the user approves and runs one. A new way for words to become a
    # plan fails here until it is looked at and added, with why it holds only the user's own words.
    It 'makes plans of words only where the words are the user''s own' {
        $allowed = @(
            'New-LambekPlan <- Invoke-LambekHostRequest'      # the message the user sends from the app
            'New-LambekPlan <- New-LambekPlan'                # the same message, read again bare or as said
            'New-LambekPlan <- Resolve-LambekTurn'            # the user's next message, or what the user said yes to
            'New-LambekPlan <- Resolve-LambekRecall'          # a message the user wrote before ("comme la derniere fois")
            'New-LambekPlan <- Resolve-LambekCodeRequest'     # a task the user asks written as a program, never run
            'New-LambekPlan <- Invoke-LambekWarmUpPiece'      # an example of an installed action, its answer thrown away
            'New-LambekPlan <- Optimize-LambekSpeech'         # the cases of a bench, never run
        )
        $made = @(Get-PlanCall | Where-Object Command -EQ 'New-LambekPlan' | ForEach-Object { "$($_.Command) <- $($_.Owner)" } | Sort-Object -Unique)
        $made | Where-Object { $_ -notin $allowed } | Should -BeNullOrEmpty
    }

    It 'approves and runs a plan only when the user asks it, from the app' {
        $acting = @(Get-PlanCall | Where-Object { $_.Command -ne 'New-LambekPlan' -and -not $_.Simulated } | ForEach-Object { "$($_.Command) <- $($_.Owner)" } | Sort-Object -Unique)
        $acting | Should -Be @('Approve-LambekPlan <- Invoke-LambekHostRequest', 'Invoke-LambekPlan <- Invoke-LambekHostRequest')
    }
}
