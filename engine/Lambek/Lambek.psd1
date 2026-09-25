@{
    RootModule           = 'Lambek.psm1'
    ModuleVersion        = '0.2.0'
    GUID                 = 'eea3f7ac-dd0b-43aa-ae2b-a37522b5ea12'
    Author               = 'Amin Gharbaoui'
    CompanyName          = 'Amin Gharbaoui'
    Copyright            = '(c) 2026 Amin Gharbaoui'
    Description          = 'Deterministic intent compiler: plain language in, verified execution out.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'ConvertTo-LambekRequest'
        'Get-LambekPack'
        'Import-LambekPack'
        'Measure-LambekSimilarity'
        'Resolve-LambekGrammar'
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
