#Requires -Version 7.4
Set-StrictMode -Version Latest

# Load functions
$privateFiles = @(Get-ChildItem -Path "$PSScriptRoot/Private" -Filter '*.ps1')
$publicFiles = @(Get-ChildItem -Path "$PSScriptRoot/Public" -Filter '*.ps1')

foreach ($file in $privateFiles + $publicFiles) {
    . $file.FullName
}

# Module state
$script:Packs = [ordered]@{}
$script:LexiconCache = @{}
$script:ActionIndexCache = @{}
$script:AuditPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Lambek/audit.jsonl'
$script:HostState = @{ Plans = [ordered]@{}; Simulations = @{}; Approvals = @{} }
$script:ProgressHandler = $null
$script:HostRequestId = $null
$script:HostWriter = $null
$script:LanguageHint = $null
$script:Incognito = $false
$script:TextExtensions = @('txt', 'md', 'csv', 'tsv', 'log', 'json', 'xml', 'yml', 'yaml', 'ini', 'cfg', 'conf', 'toml', 'ps1', 'psm1', 'psd1', 'js', 'jsx', 'ts', 'tsx', 'py', 'cs', 'rs', 'java', 'html', 'css', 'sql', 'sh', 'bat', 'cmd')

# MCP client: modern protocol first, legacy handshake as a fallback
$dataFolder = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Lambek'
$script:Mcp = @{
    Servers    = [ordered]@{}
    ConfigPath = Join-Path $dataFolder 'mcp.json'
    CachePath  = Join-Path $dataFolder 'mcp-tools.json'
}
$script:McpVersion = '2026-07-28'
$script:McpLegacyVersion = '2025-11-25'
$manifest = Import-PowerShellDataFile -LiteralPath "$PSScriptRoot/Lambek.psd1"
$script:McpClientInfo = [ordered]@{ name = 'Lambek'; version = $manifest.ModuleVersion }

# Exports
Export-ModuleMember -Function $publicFiles.BaseName
