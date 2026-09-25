function Get-LambekAvailableLanguage {
    [CmdletBinding()]
    param()

    $folder = Join-Path $PSScriptRoot '../Data/Languages'
    $files = Get-ChildItem -Path $folder -Filter '*.json' | Sort-Object Name

    return @($files.BaseName)
}
