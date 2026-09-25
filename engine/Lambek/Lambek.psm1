#Requires -Version 7.4
Set-StrictMode -Version Latest

# Load functions
$privateFiles = @(Get-ChildItem -Path "$PSScriptRoot/Private" -Filter '*.ps1')
$publicFiles = @(Get-ChildItem -Path "$PSScriptRoot/Public" -Filter '*.ps1')

foreach ($file in $privateFiles + $publicFiles) {
    . $file.FullName
}

# Module state
$script:LexiconCache = @{}

# Exports
Export-ModuleMember -Function $publicFiles.BaseName
