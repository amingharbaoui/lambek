function Get-LambekParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Action,

        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        [Parameter(Mandatory)]
        [pscustomobject] $Grammar
    )

    $language = $Request.Language
    $values = [ordered]@{}

    # Entity occurrences in text order
    $occurrences = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    for ($position = 0; $position -lt $Request.Words.Count; $position++) {
        if ($Request.Words[$position] -notmatch '^_(?<type>[a-z]+)_$') { continue }

        $type = $Matches['type']
        if (-not $seen.ContainsKey($type)) { $seen[$type] = 0 }
        $sameType = @($Request.Entities | Where-Object Type -EQ $type)
        $entity = $sameType[$seen[$type]]
        $seen[$type]++

        $occurrences.Add([pscustomobject]@{
                Type    = $type
                Value   = $entity.Value
                Context = @(Get-LambekEntityContext -Position $position -Grammar $Grammar)
                Used    = $false
            })
    }

    # Pass 1: entities after a specific word (in, to, than...)
    foreach ($parameter in $Action.Parameters) {
        if (-not $parameter.ContainsKey('Entities') -or -not $parameter.ContainsKey('After')) { continue }

        foreach ($occurrence in $occurrences) {
            if ($occurrence.Used -or $occurrence.Type -notin $parameter.Entities) { continue }

            $matchesContext = @($occurrence.Context | Where-Object { $_ -in $parameter.After }).Count -gt 0
            if ($matchesContext) {
                $values[$parameter.Name] = $occurrence.Value
                $occurrence.Used = $true
                break
            }
        }
    }

    # Pass 2: remaining entities by type
    foreach ($parameter in $Action.Parameters) {
        if (-not $parameter.ContainsKey('Entities') -or $values.Contains($parameter.Name)) { continue }

        $hasAfter = $parameter.ContainsKey('After')
        $canFallback = $parameter.ContainsKey('Fallback') -and $parameter.Fallback
        if ($hasAfter -and -not $canFallback) { continue }

        foreach ($occurrence in $occurrences) {
            if (-not $occurrence.Used -and $occurrence.Type -in $parameter.Entities) {
                $values[$parameter.Name] = $occurrence.Value
                $occurrence.Used = $true
                break
            }
        }
    }

    # Word parameters (kind, language...)
    foreach ($parameter in $Action.Parameters) {
        if (-not $parameter.ContainsKey('Words')) { continue }

        foreach ($word in $Request.Words) {
            if ($parameter.Words.ContainsKey($word)) {
                $values[$parameter.Name] = $parameter.Words[$word]
                break
            }
        }

        if (-not $values.Contains($parameter.Name) -and $parameter.ContainsKey('Default')) {
            $values[$parameter.Name] = $parameter.Default
        }
    }

    # Keep the order of the action definition
    $ordered = [ordered]@{}
    $missing = [System.Collections.Generic.List[string]]::new()
    $questions = [System.Collections.Generic.List[string]]::new()

    foreach ($parameter in $Action.Parameters) {
        if ($values.Contains($parameter.Name)) {
            $ordered[$parameter.Name] = $values[$parameter.Name]
        }
        elseif ($parameter.ContainsKey('Required') -and $parameter.Required) {
            $missing.Add($parameter.Name)

            $question = "Missing: $($parameter.Name)"
            if ($parameter.ContainsKey('Question')) {
                if ($parameter.Question.ContainsKey($language)) {
                    $question = $parameter.Question[$language]
                }
                elseif ($parameter.Question.ContainsKey('en')) {
                    $question = $parameter.Question['en']
                }
            }
            $questions.Add($question)
        }
    }

    # Entities that no parameter used
    $unused = @($occurrences | Where-Object { -not $_.Used } | ForEach-Object { Format-LambekValue -Value $_.Value })

    return [pscustomobject]@{
        Unused    = $unused
        Values    = $ordered
        Missing   = $missing.ToArray()
        Questions = $questions.ToArray()
    }
}
