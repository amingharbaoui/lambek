function Get-LambekEntityRule {
    [CmdletBinding()]
    param()

    # Built once, again when a pack comes or the folders of the machine are read again
    $null = Get-LambekSystemVocabulary
    if ($script:EntityRules) { return $script:EntityRules }

    $rules = [System.Collections.Generic.List[object]]::new()

    # Universal rules
    $path = Join-Path $PSScriptRoot '../Data/entities.json'
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    foreach ($rule in $data.Entities) {
        $rules.Add($rule)
    }

    # Pack rules: {folders} stands for every folder name known by the packs and the machine, {kinds} for every kind of file
    $folders = $null
    $kinds = $null
    foreach ($pack in $script:Packs.Values) {
        foreach ($rule in $pack.Entities) {
            if ($rule.Pattern.Contains('{folders}') -or $rule.Pattern.Contains('{kinds}')) {
                if ($null -eq $folders) { $folders = Get-LambekFolderPattern }
                if ($null -eq $kinds) { $kinds = Get-LambekKindPattern }
                $rule = $rule.Clone()
                $rule.Pattern = $rule.Pattern.Replace('{folders}', $folders).Replace('{kinds}', $kinds)
            }
            $rules.Add($rule)
        }
    }

    # Units and orders the languages of the packs add ("dagen", "Tage", "nieuwste"): the rule is rebuilt from its whole table
    $units = @{}
    $orders = @{}
    foreach ($pack in $script:Packs.Values) {
        if (-not $pack.PSObject.Properties['Extras'] -or -not $pack.Extras) { continue }
        foreach ($name in $pack.Extras.Units.Keys) {
            if (-not $units.ContainsKey($name)) { $units[$name] = @{} }
            foreach ($unit in $pack.Extras.Units[$name].Keys) { $units[$name][$unit] = $pack.Extras.Units[$name][$unit] }
        }
        foreach ($said in $pack.Extras.Orders.Keys) { $orders[$said] = $pack.Extras.Orders[$said] }
    }
    for ($k = 0; $k -lt $rules.Count; $k++) {
        $rule = $rules[$k]
        if ($rule.ContainsKey('Units') -and $units.ContainsKey($rule.Name)) {
            $rule = $rule.Clone()
            $table = @{}
            foreach ($unit in $rule.Units.Keys) { $table[$unit] = $rule.Units[$unit] }
            foreach ($unit in $units[$rule.Name].Keys) { if (-not $table.ContainsKey($unit)) { $table[$unit] = $units[$rule.Name][$unit] } }
            $rule.Units = $table
            $rule.Pattern = Edit-LambekPatternGroup -Pattern $rule.Pattern -Group 'u' -Inner (ConvertTo-LambekWordPattern -Names @($table.Keys))
            $rules[$k] = $rule
        }
        elseif ($rule.ContainsKey('Orders') -and $orders.Count -gt 0) {
            $rule = $rule.Clone()
            $table = @{}
            foreach ($said in $rule.Orders.Keys) { $table[$said] = $rule.Orders[$said] }
            $added = @($orders.Keys | Where-Object { -not $table.ContainsKey($_) })
            foreach ($said in $added) { $table[$said] = $orders[$said] }
            $rule.Orders = $table
            if ($added.Count -gt 0) { $rule.Pattern = $rule.Pattern.Replace('(?<v>', "(?<v>$(ConvertTo-LambekWordPattern -Names $added)|") }
            $rules[$k] = $rule
        }
    }

    $script:EntityRules = @($rules | Sort-Object { $_.Priority }, { $_.Name })
    return $script:EntityRules
}

function Edit-LambekPatternGroup {
    param([string] $Pattern, [string] $Group, [string] $Inner)

    # Replaces what a named group of a pattern matches, its parentheses counted (escaped ones and classes skipped)
    $start = $Pattern.IndexOf("(?<$Group>")
    if ($start -lt 0) { return $Pattern }
    $open = $start + "(?<$Group>".Length
    $depth = 1
    $inClass = $false
    for ($at = $open; $at -lt $Pattern.Length; $at++) {
        $character = $Pattern[$at]
        if ($character -eq '\') { $at++; continue }
        if ($inClass) { if ($character -eq ']') { $inClass = $false }; continue }
        if ($character -eq '[') { $inClass = $true; continue }
        if ($character -eq '(') { $depth++ }
        elseif ($character -eq ')') {
            $depth--
            if ($depth -eq 0) { return $Pattern.Substring(0, $open) + $Inner + $Pattern.Substring($at) }
        }
    }
    return $Pattern
}
