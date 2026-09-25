@{
    RootModule           = 'Lambek.psm1'
    ModuleVersion        = '0.7.0'
    GUID                 = 'eea3f7ac-dd0b-43aa-ae2b-a37522b5ea12'
    Author               = 'Amin Gharbaoui'
    CompanyName          = 'Amin Gharbaoui'
    Copyright            = '(c) 2026 Amin Gharbaoui'
    Description          = 'Deterministic intent compiler: plain language in, verified execution out.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Approve-LambekPlan'
        'ConvertTo-LambekAnswer'
        'ConvertTo-LambekRequest'
        'Get-LambekPack'
        'Import-LambekPack'
        'Invoke-LambekBenchmark'
        'Invoke-LambekPlan'
        'Measure-LambekSimilarity'
        'New-LambekPlan'
        'Optimize-LambekScoring'
        'Resolve-LambekGrammar'
        'Resolve-LambekIntent'
        'Start-LambekHost'
        'Test-LambekAudit'
        'Test-LambekScript'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('NLP', 'Automation', 'Deterministic', 'DSL', 'AST')
            ProjectUri = 'https://github.com/amingharbaoui/lambek'
        }
    }
}
