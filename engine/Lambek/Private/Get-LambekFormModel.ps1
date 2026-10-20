function Get-LambekFormModel {
    # The learned forms model of a language (Data/Forms/<language>.forms.gz), loaded once; nothing when there is none
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    if ($null -eq $script:FormModels) { $script:FormModels = @{} }
    if ($script:FormModels.ContainsKey($Language)) { return $script:FormModels[$Language] }
    $path = Join-Path $PSScriptRoot "../Data/Forms/$Language.forms.gz"
    $model = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) { $model = [LambekForms]::Load([IO.Path]::GetFullPath($path)) }
    $script:FormModels[$Language] = $model
    return $model
}
