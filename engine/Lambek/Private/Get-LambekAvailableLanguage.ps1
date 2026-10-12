function Get-LambekAvailableLanguage {
    [CmdletBinding()]
    param()

    # Listed once: every request asks for them several times
    if ($null -eq $script:AvailableLanguages) {
        $folder = Join-Path $PSScriptRoot '../Data/Languages'
        $files = Get-ChildItem -Path $folder -Filter '*.json' | Sort-Object Name
        $script:AvailableLanguages = [string[]] @($files.BaseName)
    }

    return @($script:AvailableLanguages)
}
