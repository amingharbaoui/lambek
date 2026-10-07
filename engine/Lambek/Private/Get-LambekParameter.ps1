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

    # Exceptions: "sauf", "except" open a scope to the end of the clause; what is named there is left out.
    # A parameter that follows an exception word takes only what is in that scope, the others only what is before it.
    $lexicon = Get-LambekLexicon -Language $language
    $exceptAt = [int]::MaxValue
    for ($position = 0; $position -lt $Request.Words.Count; $position++) {
        if ($Request.Words[$position] -in $lexicon.Exclusions) { $exceptAt = $position; break }
    }
    $isExcept = @{}
    foreach ($parameter in $Action.Parameters) {
        $isExcept[$parameter.Name] = $parameter.ContainsKey('After') -and @($parameter.After | Where-Object { $_ -in $lexicon.Exclusions }).Count -gt 0
    }
    foreach ($parameter in $Action.Parameters) {
        if (-not $isExcept[$parameter.Name] -or -not $parameter.ContainsKey('Entities')) { continue }
        $found = @($occurrences | Where-Object { -not $_.Used -and $_.Position -gt $exceptAt -and $_.Type -in $parameter.Entities })
        if (-not ($parameter.ContainsKey('Many') -and $parameter.Many)) { $found = @($found | Select-Object -First 1) }
        if ($found.Count -eq 0) { continue }
        foreach ($occurrence in $found) { $occurrence.Used = $true }
        $values[$parameter.Name] = Get-LambekOneOrMany -Items @($found | ForEach-Object { $_.Value })
        $usedBy[$parameter.Name] = $found[0]
    }

    # Pass 1: entities after a specific word (in, to, than...), direct links first
    foreach ($field in 'Near', 'Context') {
        foreach ($parameter in $Action.Parameters) {
            if (-not $parameter.ContainsKey('Entities') -or -not $parameter.ContainsKey('After') -or $isExcept[$parameter.Name]) { continue }
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

    # Pass 2: remaining entities by type (all of them for a parameter that takes several: ".log and .tmp")
    foreach ($parameter in $Action.Parameters) {
        if (-not $parameter.ContainsKey('Entities') -or $values.Contains($parameter.Name) -or $isExcept[$parameter.Name]) { continue }

        $hasAfter = $parameter.ContainsKey('After')
        $canFallback = $parameter.ContainsKey('Fallback') -and $parameter.Fallback
        if ($hasAfter -and -not $canFallback) { continue }

        $found = @($occurrences | Where-Object { -not $_.Used -and $_.Type -in $parameter.Entities })
        if (-not ($parameter.ContainsKey('Many') -and $parameter.Many)) { $found = @($found | Select-Object -First 1) }
        if ($found.Count -eq 0) { continue }
        foreach ($occurrence in $found) { $occurrence.Used = $true }
        $values[$parameter.Name] = Get-LambekOneOrMany -Items @($found | ForEach-Object { $_.Value })
        $usedBy[$parameter.Name] = $found[0]
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

    # Word parameters (kind, language...), inside or outside the exception scope, one or several
    foreach ($parameter in $Action.Parameters) {
        if (-not $parameter.ContainsKey('Words')) { continue }

        $found = [System.Collections.Generic.List[object]]::new()
        for ($position = 0; $position -lt $Request.Words.Count; $position++) {
            $word = $Request.Words[$position]
            if (-not $parameter.Words.ContainsKey($word)) { continue }
            if ($isExcept[$parameter.Name] -ne ($position -gt $exceptAt)) { continue }
            if (-not $found.Contains($parameter.Words[$word])) { $found.Add($parameter.Words[$word]) }
            if (-not ($parameter.ContainsKey('Many') -and $parameter.Many)) { break }
        }
        if ($found.Count -gt 0) { $values[$parameter.Name] = Get-LambekOneOrMany -Items $found.ToArray() }

        if (-not $values.Contains($parameter.Name) -and $parameter.ContainsKey('Default')) {
            $values[$parameter.Name] = $parameter.Default
        }
    }

    # A number that goes with another value: "the newest file" is one file, "the 3 newest" three
    foreach ($parameter in $Action.Parameters) {
        if (-not $parameter.ContainsKey('RequiredWith') -or -not $parameter.ContainsKey('Singular')) { continue }
        if ($values.Contains($parameter.Name) -or -not $values.Contains($parameter.RequiredWith)) { continue }
        if ((Get-LambekGrammaticalNumber -Request $Request) -eq 'singular') { $values[$parameter.Name] = $parameter.Singular }
    }

    # One file, but which one? "move my image to the desktop" names one file of many without saying which
    $which = $false
    # ("all of them", "toutes" answers: every one)
    $every = $Action.ContainsKey('Which') -and @($Request.Tokens | Where-Object { $_ -in @($Action.Which.All) }).Count -gt 0
    if ($Action.ContainsKey('Which') -and -not $every -and @($Action.Which.By | Where-Object { $values.Contains($_) }).Count -eq 0) {
        $nouns = @($Action.Which.Nouns) + @($Action.Parameters | Where-Object { $_.Name -eq 'Kind' -and $_.ContainsKey('Words') } | ForEach-Object { $_.Words.Keys })
        # Asked only when the folder really holds more than one such file
        $which = (Get-LambekGrammaticalNumber -Request $Request -Only $nouns) -eq 'singular' -and (Get-LambekCandidateCount -Action $Action -Values $values) -ne 1
    }

    # Keep the order of the action definition
    $ordered = [ordered]@{}
    foreach ($parameter in $Action.Parameters) {
        if ($values.Contains($parameter.Name)) {
            $ordered[$parameter.Name] = $values[$parameter.Name]
        }
    }
    $check = Get-LambekMissingParameter -Action $Action -Parameters $ordered -Language $language
    $missing = @($check.Missing)
    $questions = @($check.Questions)
    if ($which) {
        $missing += @($Action.Which.By)[0]
        $text = $Action.Which.Question['en']
        if ($Action.Which.Question.ContainsKey($language)) { $text = $Action.Which.Question[$language] }
        $questions += $text
    }

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

function Get-LambekOneOrMany {
    param([object[]] $Items)

    # One value stays a value, several become a list
    if ($Items.Count -eq 1) { return $Items[0] }
    return , [object[]] $Items
}

function Get-LambekGrammaticalNumber {
    param(
        [pscustomobject] $Request,

        # Only these nouns count ("image", "file"), when given
        [string[]] $Only
    )

    # Singular or plural, from the nouns of the request ("file" or "files", "fichier" or "fichiers")
    $nouns = @(Get-LambekGrammarLexicon -Language $Request.Language).Words
    $number = 'unknown'
    # The words that open the set a file is chosen from, as the packs give them ("among", "parmi")
    $among = @(foreach ($pack in $script:Packs.Values) { foreach ($action in $pack.Actions) { if ($action.ContainsKey('Which') -and $action.Which.ContainsKey('Among')) { $action.Which.Among } } }) | Select-Object -Unique
    for ($i = 0; $i -lt $Request.Words.Count; $i++) {
        $word = $Request.Words[$i]
        if ($word -match '^_' -or -not $nouns.ContainsKey($word) -or @($nouns[$word]) -notcontains 'o') { continue }
        if ($Only -and $word -notin $Only) { continue }
        # "parmi les images", "among the images": the files it is chosen from, not the file itself
        $before = @($Request.Tokens[[math]::Max(0, $i - 2)..[math]::Max(0, $i - 1)])
        if ($i -gt 0 -and @($before | Where-Object { $_ -in $among }).Count -gt 0) { continue }
        # A word the repair chose ("fils" read as "file") says nothing sure about the number
        if ($Only -and $Request.Tokens[$i] -in @($Request.Corrections | ForEach-Object { $_.To })) { continue }
        if ($Request.Tokens[$i] -ne $word) { return 'plural' }
        $number = 'singular'
    }
    return $number
}

function Get-LambekCandidateCount {
    param(
        [hashtable] $Action,
        [System.Collections.IDictionary] $Values
    )

    # How many files the request could mean, read on the disk (0, 1 or 2 for "more"): -1 when it cannot tell
    $folder = $null
    foreach ($name in 'Source', 'Path') { if ($Values.Contains($name)) { $folder = [string] $Values[$name]; break } }
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) { return -1 }

    # As deep as the action looks, and only the kinds and extensions it keeps
    $options = [IO.EnumerationOptions]::new()
    $options.IgnoreInaccessible = $true
    $options.RecurseSubdirectories = @($Action.Template | Where-Object { $_ -match 'Get-ChildItem' -and $_ -match '-Recurse' }).Count -gt 0
    $extensions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Values.Contains('Extension')) { $extensions.UnionWith([string[]] @($Values.Extension)) }
    if ($Values.Contains('Kind')) { foreach ($kind in @($Values.Kind)) { $extensions.UnionWith([string[]] @(Get-LambekKindExtension -Kind $kind)) } }

    $count = 0
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($folder, '*', $options)) {
            if ($extensions.Count -gt 0 -and -not $extensions.Contains([IO.Path]::GetExtension($file))) { continue }
            $count++
            if ($count -gt 1) { break }
        }
    }
    catch {
        return -1
    }
    return $count
}
