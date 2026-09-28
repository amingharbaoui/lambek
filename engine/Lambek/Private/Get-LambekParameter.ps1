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
    $usedBy = @{}

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
                Type     = $type
                Value    = $entity.Value
                Near     = @(Get-LambekEntityContext -Position $position -Grammar $Grammar -Depth 1)
                Context  = @(Get-LambekEntityContext -Position $position -Grammar $Grammar -Depth 2)
                Position = $position
                Used     = $false
            })
    }

    # Pass 1: entities after a specific word (in, to, than...), direct links first
    foreach ($field in 'Near', 'Context') {
        foreach ($parameter in $Action.Parameters) {
            if (-not $parameter.ContainsKey('Entities') -or -not $parameter.ContainsKey('After')) { continue }
            if ($values.Contains($parameter.Name)) { continue }

            foreach ($occurrence in $occurrences) {
                if ($occurrence.Used -or $occurrence.Type -notin $parameter.Entities) { continue }

                $matchesContext = @($occurrence.$field | Where-Object { $_ -in $parameter.After }).Count -gt 0
                if ($matchesContext) {
                    $values[$parameter.Name] = $occurrence.Value
                    $occurrence.Used = $true
                    $usedBy[$parameter.Name] = $occurrence
                    break
                }
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
                $usedBy[$parameter.Name] = $occurrence
                break
            }
        }
    }

    # Pass 3: a place that follows another ("de X dans Y", "my downloads on the desktop"):
    # with no word for it, the first of the two is the source and the next one the destination
    foreach ($parameter in $Action.Parameters) {
        if (-not $parameter.ContainsKey('Follows') -or $values.Contains($parameter.Name)) { continue }
        $leader = $parameter.Follows
        if (-not $usedBy.ContainsKey($leader)) { continue }

        $places = @(@($usedBy[$leader]) + @($occurrences | Where-Object { -not $_.Used -and $_.Type -in $parameter.Entities }) | Sort-Object Position)
        if ($places.Count -ne 2) { continue }
        $values[$leader] = $places[0].Value
        $values[$parameter.Name] = $places[1].Value
        foreach ($place in $places) { $place.Used = $true }
    }

    # Free text: words the grammar does not know fill a text parameter ("search notes for budget")
    $freeParameters = @($Action.Parameters | Where-Object { $_.ContainsKey('Free') -and $_.Free -and -not $values.Contains($_.Name) })
    if ($freeParameters.Count -gt 0) {
        $lexicon = Get-LambekLexicon -Language $language
        $tokens = @($Request.Tokens)
        $taken = [System.Collections.Generic.HashSet[int]]::new()
        $anchorless = $true

        foreach ($parameter in $freeParameters) {
            # After the word of the parameter when there is one ("query budget"), otherwise anywhere once
            $start = -1
            for ($i = 0; $i -lt $tokens.Count; $i++) {
                if ($tokens[$i] -in $parameter.After) { $start = $i + 1; break }
            }
            if ($start -lt 0 -and -not $anchorless) { continue }

            # After an anchor, small words stay inside the text ("groceries for sunday")
            $loose = [System.Collections.Generic.List[int]]::new()
            for ($i = [math]::Max($start, 0); $i -lt $tokens.Count; $i++) {
                $token = $tokens[$i]
                $isStop = $lexicon.StopWords.Contains($token)
                $isKnown = $token -match '^_[a-z]+_$' -or $lexicon.Vocabulary.Contains($token) -or $taken.Contains($i)
                if ($isKnown -or ($isStop -and $start -lt 0)) {
                    if ($start -ge 0 -and $loose.Count -gt 0) { break }
                    continue
                }
                if ($isStop -and $loose.Count -eq 0) { continue }
                $loose.Add($i)
            }
            while ($loose.Count -gt 0 -and $lexicon.StopWords.Contains($tokens[$loose[$loose.Count - 1]])) { $loose.RemoveAt($loose.Count - 1) }
            if ($loose.Count -eq 0) { continue }

            foreach ($index in $loose) { [void] $taken.Add($index) }
            if ($start -lt 0) { $anchorless = $false }
            $values[$parameter.Name] = Get-LambekOriginalText -Text $Request.Original -Words @($loose | ForEach-Object { $tokens[$_] })
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
    foreach ($parameter in $Action.Parameters) {
        if ($values.Contains($parameter.Name)) {
            $ordered[$parameter.Name] = $values[$parameter.Name]
        }
    }
    $check = Get-LambekMissingParameter -Action $Action -Parameters $ordered -Language $language
    $missing = $check.Missing
    $questions = $check.Questions

    # Entities that no parameter used
    $unused = @($occurrences | Where-Object { -not $_.Used } | ForEach-Object { Format-LambekValue -Value $_.Value })

    return [pscustomobject]@{
        Unused    = $unused
        Values    = $ordered
        Missing   = @($missing)
        Questions = @($questions)
    }
}

function Get-LambekOriginalText {
    param(
        [string] $Text,
        [string[]] $Words
    )

    # The words as the user typed them, with their case
    $pattern = ($Words | ForEach-Object { [regex]::Escape($_) }) -join '\W+'
    $found = [regex]::Match($Text, $pattern, 'IgnoreCase')
    if ($found.Success) { return $found.Value }
    return $Words -join ' '
}
