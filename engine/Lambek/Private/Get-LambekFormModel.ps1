function Get-LambekFormModel {
    # The learned forms model of a language (Data/Forms/<language>.forms.gz, with the words of <language>.learned.gz), loaded once; nothing when there is none
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    if ($null -eq $script:FormModels) { $script:FormModels = @{} }
    if ($script:FormModels.ContainsKey($Language)) { return $script:FormModels[$Language] }
    $path = Join-Path $PSScriptRoot "../Data/Forms/$Language.forms.gz"
    $model = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $model = [LambekForms]::Load([IO.Path]::GetFullPath($path))
        # What Lambek learned on its own from plain text (tools/Learn-LambekWords.ps1), when it was written down
        $learned = Join-Path $PSScriptRoot "../Data/Forms/$Language.learned.gz"
        if (Test-Path -LiteralPath $learned -PathType Leaf) { $model.AddLearned([LambekSelfReader]::Load([IO.Path]::GetFullPath($learned))) }
    }
    $script:FormModels[$Language] = $model
    return $model
}
