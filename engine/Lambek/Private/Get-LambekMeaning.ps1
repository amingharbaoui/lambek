function Get-LambekMeaning {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Grammar,

        [Parameter(Mandatory)]
        [string] $Language
    )

    # The actions the sentence can mean, by contracting the words' tensors along the reduction (DisCoCat in relations).
    # Only a whole sentence has a meaning
    if (-not $Grammar.IsSentence -or -not $Grammar.PSObject.Properties['Linkage'] -or $Grammar.Linkage.Output -lt 0) { return , [string[]] @() }
    $model = Get-LambekMeaningModel -Language $Language
    $linkage = $Grammar.Linkage

    $words = [System.Collections.Generic.List[string]]::new()
    $types = [System.Collections.Generic.List[string]]::new()
    $bases = [System.Collections.Generic.List[string[]]]::new()
    for ($w = 0; $w -lt @($Grammar.Assignment).Count; $w++) {
        $item = @($Grammar.Assignment)[$w]
        $words.Add($item.Word)
        $types.Add($item.Type)
        $mine = [System.Collections.Generic.List[string]]::new()
        for ($k = 0; $k -lt $linkage.Owners.Count; $k++) { if ($linkage.Owners[$k] -eq $w) { $mine.Add($linkage.Bases[$k]) } }
        $bases.Add($mine.ToArray())
    }
    $pairs = [int[][]] @($linkage.Pairs)
    return , [string[]] $model.Contract($words.ToArray(), $types.ToArray(), $bases.ToArray(), $pairs, $linkage.Output)
}

function Get-LambekMeaningModel {
    param([string] $Language)

    # Cache: the tensors change only with the packs
    $key = "meaning|$Language"
    if ($script:ActionIndexCache.ContainsKey($key)) { return $script:ActionIndexCache[$key] }

    $model = [LambekMeaning]::new()
    $actions = [System.Collections.Generic.List[string]]::new()
    foreach ($pack in $script:Packs.Values) { foreach ($action in $pack.Actions) { $actions.Add($action.Id) } }
    $model.Space('s', [string[]] $actions.ToArray())

    # The kinds of object each base can name, from the packs ("o": file, folder)
    $sorts = @{}
    foreach ($pack in $script:Packs.Values) {
        if (-not $pack.PSObject.Properties['Sorts'] -or -not $pack.Sorts) { continue }
        foreach ($base in $pack.Sorts.Keys) {
            if (-not $sorts.ContainsKey($base)) { $sorts[$base] = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal) }
            foreach ($sort in $pack.Sorts[$base].Keys) { [void] $sorts[$base].Add($sort) }
        }
    }
    foreach ($base in $sorts.Keys) { $model.Space($base, [string[]] @($sorts[$base])) }

    foreach ($pack in $script:Packs.Values) {
        # Every language: a word keeps its tensor whatever the language around it (a verb borrowed from another language)
        foreach ($scope in @('*', $Language) + @($pack.Words.Keys | Where-Object { $_ -notin '*', $Language } | Sort-Object)) {
            if (-not $pack.Words.ContainsKey($scope)) { continue }
            foreach ($word in $pack.Words[$scope].Keys) {
                foreach ($type in @($pack.Words[$scope][$word])) {
                    $simple = @(ConvertFrom-LambekType -Type $type)
                    $tensor = Get-LambekWordTensor -Model $model -Pack $pack -Word $word -Simple $simple
                    if ($tensor) { $model.Word($word, $type, [int[][]] $tensor) }
                }
            }
        }
    }
    $script:ActionIndexCache[$key] = $model
    return $model
}

function Get-LambekWordTensor {
    param([LambekMeaning] $Model, [pscustomobject] $Pack, [string] $Word, [object[]] $Simple)

    # A verb: its s is each action it names, each object slot the kinds that action takes. The s may stand anywhere
    # in the type: first for an imperative (s o^l), last for a verb at the end of the sentence (o^r s, Dutch, German)
    $sentence = -1
    for ($k = 0; $k -lt $Simple.Count; $k++) { if ($Simple[$k].Base -eq 's' -and $Simple[$k].Order -eq 0) { $sentence = $k; break } }
    if ($sentence -ge 0) {
        $actions = @($Pack.Actions | Where-Object { $Word -in $_.Verbs })
        if ($actions.Count -eq 0) { return $null }
        $rows = [System.Collections.Generic.List[int[]]]::new()
        foreach ($action in $actions) {
            $partial = [System.Collections.Generic.List[int[]]]::new()
            $partial.Add([int[]] @())
            for ($k = 0; $k -lt $Simple.Count; $k++) {
                $base = $Simple[$k].Base
                if ($k -eq $sentence) { $allowed = @($Model.Index('s', $action.Id)) }
                else {
                    $allowed = @(0..($Model.Size($base) - 1))
                    if ($action.ContainsKey('Objects') -and $action.Objects.ContainsKey($base)) {
                        $allowed = @($action.Objects[$base] | ForEach-Object { $Model.Index($base, $_) } | Where-Object { $_ -ge 0 })
                    }
                }
                $next = [System.Collections.Generic.List[int[]]]::new()
                foreach ($row in $partial) { foreach ($value in $allowed) { $next.Add([int[]] (@($row) + $value)) } }
                $partial = $next
            }
            foreach ($row in $partial) { $rows.Add($row) }
        }
        return , $rows.ToArray()
    }

    # A noun of a known kind: only that kind on its object slot
    if ($Simple.Count -eq 1 -and $Pack.PSObject.Properties['Sorts'] -and $Pack.Sorts -and $Pack.Sorts.ContainsKey($Simple[0].Base)) {
        $base = $Simple[0].Base
        $kinds = @($Pack.Sorts[$base].Keys | Where-Object { $Word -in @($Pack.Sorts[$base][$_]) })
        if ($kinds.Count -eq 0) { return $null }
        return , [int[][]] @($kinds | ForEach-Object { , [int[]] @($Model.Index($base, $_)) })
    }
    return $null
}
