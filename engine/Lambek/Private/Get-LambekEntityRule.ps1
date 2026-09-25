function Get-LambekEntityRule {
    [CmdletBinding()]
    param()

    $rules = [System.Collections.Generic.List[object]]::new()

    # Universal rules
    $path = Join-Path $PSScriptRoot '../Data/entities.json'
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    foreach ($rule in $data.Entities) {
        $rules.Add($rule)
    }

    # Pack rules
    foreach ($pack in $script:Packs.Values) {
        foreach ($rule in $pack.Entities) {
            $rules.Add($rule)
        }
    }

    return @($rules | Sort-Object { $_.Priority }, { $_.Name })
}
