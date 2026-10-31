@{
    RootModule           = 'Lambek.psm1'
    ModuleVersion        = '0.13.0'
    GUID                 = 'eea3f7ac-dd0b-43aa-ae2b-a37522b5ea12'
    Author               = 'Amin Gharbaoui'
    CompanyName          = 'Amin Gharbaoui'
    Copyright            = '(c) 2026 Amin Gharbaoui'
    Description          = 'Deterministic intent compiler: plain language in, verified execution out.'
    PowerShellVersion    = '7.6'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Add-LambekWord'
        'Approve-LambekPlan'
        'Clear-LambekHistory'
        'Clear-LambekTrash'
        'ConvertTo-LambekAnswer'
        'ConvertTo-LambekCode'
        'ConvertTo-LambekLearnedRule'
        'ConvertTo-LambekRequest'
        'Connect-LambekMcp'
        'Disconnect-LambekMcp'
        'Find-LambekConcept'
        'Find-LambekRenameRule'
        'Find-LambekWord'
        'Get-LambekAdaptation'
        'Get-LambekMcpServer'
        'Get-LambekMemory'
        'Get-LambekPack'
        'Get-LambekWord'
        'Get-LambekWordForm'
        'Import-LambekPack'
        'Invoke-LambekActBenchmark'
        'Invoke-LambekBenchmark'
        'Invoke-LambekFormBenchmark'
        'Invoke-LambekMessageBenchmark'
        'Invoke-LambekPlan'
        'Invoke-LambekQuery'
        'Measure-LambekSignal'
        'Measure-LambekSimilarity'
        'New-LambekPlan'
        'Optimize-LambekFusion'
        'Optimize-LambekProposer'
        'Optimize-LambekScoring'
        'Optimize-LambekSpeech'
        'Remove-LambekWord'
        'Resolve-LambekFollowUp'
        'Resolve-LambekGrammar'
        'Resolve-LambekIntent'
        'Set-LambekPlanParameter'
        'Start-LambekHost'
        'Test-LambekAudit'
        'Test-LambekCodeSyntax'
        'Test-LambekScript'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('NLP', 'Automation', 'Deterministic', 'DSL', 'AST', 'MCP')
            ProjectUri = 'https://github.com/amingharbaoui/lambek'
        }
    }
}
