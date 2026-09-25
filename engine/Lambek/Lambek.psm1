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

# Exports
Export-ModuleMember -Function $publicFiles.BaseName
