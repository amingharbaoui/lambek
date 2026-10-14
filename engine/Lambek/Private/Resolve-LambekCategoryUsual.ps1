function Get-LambekCategoryUsual {
    param([string] $Sentence, [string] $Language)

    # A sentence that says what holds "normalement": the same sentence without that word ("les oiseaux volent"), and
    # with the article the language puts before a kind when the word took its place ("birds fly" is "all birds fly").
    # Nothing when the sentence has no such word
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $usual = $data['Usually']
    if (-not $usual) { return }
    foreach ($rule in @($usual['Most'])) {
        if (-not $rule) { continue }
        if ([regex]::IsMatch($Sentence, "(?i)$($rule[0])")) { return [regex]::Replace($Sentence, "(?i)$($rule[0])", "$($rule[1])").Trim() }
    }
    foreach ($word in @($usual['Words']) | Sort-Object { -"$_".Length }) {
        $phrase = [regex]::Escape("$word") -replace "['\u2019]", "['\u2019]"
        $pattern = "(?i)\s*,?\s*(?<![\p{L}])$phrase(?![\p{L}])\s*,?\s*"
        if (-not [regex]::IsMatch($Sentence, $pattern)) { continue }
        $rest = ([regex]::Replace($Sentence, $pattern, ' ') -replace '\s+', ' ').Trim(' ', ',')
        if (-not $rest) { return }
        $found = @($rest)
        if ($usual['Prefix'] -and -not $rest.StartsWith("$($usual['Prefix'])", [System.StringComparison]::OrdinalIgnoreCase)) { $found += "$($usual['Prefix'])$rest" }
        return $found
    }
}

function Resolve-LambekCategoryUsual {
    [CmdletBinding()]
    param(
        # A question about one ("Tweety vole-t-il ?") that nothing told answers for sure
        [Parameter(Mandatory)]
        [pscustomobject] $Ask,

        [Parameter(Mandatory)]
        [object[]] $Premises,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [LambekCategoryStatement[]] $Statements,

        [Parameter(Mandatory)]
        [hashtable] $Atoms,

        [Parameter(Mandatory)]
        [string] $Language,

        # Only what it gives: yes, no, conflict, or nothing
        [switch] $Outcome
    )

    # What the rules that hold "normalement" let Lambek suppose about one (a default logic: Reiter's, with normal
    # defaults). A rule is used for that one when what it starts from follows, and what it says can still be true
    # with what was told and the rules already used; the ways of using them as far as they go are all followed.
    # Where two rules say the opposite, the one about a narrower kind goes first: "les pingouins ne volent pas"
    # before "les oiseaux volent" when every penguin is a bird. What is supposed is what every way gives; when the
    # ways disagree, it is said that the rules contradict each other. Nothing is ever supposed against what was told
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $defaults = @(for ($i = 0; $i -lt $Premises.Count; $i++) {
            $item = $Premises[$i].Item
            if ($item.PSObject.Properties['Default'] -and $item.Default) { [pscustomobject]@{ Index = $i; Item = $item } }
        })
    if ($defaults.Count -eq 0 -or -not $Ask.Individual) { return $null }
    $who = $Ask.Individual
    $one = $who.Key
    $base = @($Statements)
    $clause = @{}
    foreach ($default in $defaults) {
        $kind = $(if ($default.Item.Kind -eq 'no') { 'isnot' } else { 'is' })
        $said = [pscustomobject]@{ Kind = $kind; Subject = $null; Individual = $who; Predicate = $default.Item.Predicate }
        $clause[$default.Index] = ConvertTo-LambekCategoryStatement -Item $said -Atoms $Atoms
    }
    # (the same rule as a condition, for what an answer rests on: "if Pingu is a penguin, Pingu does not fly")
    $condition = @{}
    foreach ($default in $defaults) {
        $number = { param($atom) if (-not $Atoms.ContainsKey($atom)) { $Atoms[$atom] = $Atoms.Count + 1 }; [int] $Atoms[$atom] }
        $notS = @($default.Item.Subject.Atoms | ForEach-Object { - (& $number $_) })
        $p = @($default.Item.Predicate.Atoms | ForEach-Object { & $number $_ })
        $statement = [LambekCategoryStatement]::new()
        if ($default.Item.Kind -eq 'no') { $statement.AddNamed($one, [int[]] (@($notS) + @($p | ForEach-Object { - $_ }))) }
        else { foreach ($atom in $p) { $statement.AddNamed($one, [int[]] (@($notS) + @($atom))) } }
        $condition[$default.Index] = $statement
    }
    $with = { param([int[]] $used, [object[]] $more = @()) [LambekCategoryStatement[]] (@($base) + @($used | ForEach-Object { $clause[$_] }) + @($more)) }
    $isA = {
        param($default)
        [pscustomobject]@{ Kind = 'askis'; Subject = $null; Individual = $who; Predicate = $default.Item.Subject }
    }
    $starts = { param([int[]] $used, $default) [LambekCategories]::Follows((& $with $used), (Get-LambekCategoryOpposite -Item (& $isA $default) -Atoms $Atoms -Individual $one)) }
    $everyIs = {
        param($narrow, $wide)
        $all = [pscustomobject]@{ Kind = 'askall'; Subject = $narrow.Item.Subject; Predicate = $wide.Item.Subject; Individual = $null }
        [LambekCategories]::Follows([LambekCategoryStatement[]] $base, (Get-LambekCategoryOpposite -Item $all -Atoms $Atoms -Individual ''))
    }
    # Which rule is about a narrower kind than which
    $narrower = @{}
    foreach ($a in $defaults) {
        foreach ($b in $defaults) {
            if ($a.Index -eq $b.Index) { continue }
            $narrower["$($a.Index)>$($b.Index)"] = (& $everyIs $a $b) -and -not (& $everyIs $b $a)
        }
    }

    # Every way of using the rules, as far as they go
    $ways = [System.Collections.Generic.List[int[]]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $walk = $null
    $walk = {
        param([int[]] $used)
        $key = (@($used | Sort-Object) -join ',')
        if (-not $seen.Add($key)) { return }
        $open = @($defaults | Where-Object {
                $_.Index -notin $used -and (& $starts $used $_) -and [LambekCategories]::Satisfiable((& $with $used @($clause[$_.Index])))
            })
        if ($open.Count -eq 0) { $ways.Add([int[]] @($used | Sort-Object)); return }
        $first = @($open | Where-Object {
                $rule = $_
                @($open | Where-Object {
                        $_.Index -ne $rule.Index -and $narrower["$($_.Index)>$($rule.Index)"] -and
                        -not [LambekCategories]::Satisfiable((& $with $used @($clause[$_.Index], $clause[$rule.Index])))
                    }).Count -eq 0
            })
        foreach ($rule in $first) { & $walk ([int[]] (@($used) + @($rule.Index))) }
    }
    & $walk ([int[]] @())

    # What each way gives
    $yesOpposite = Get-LambekCategoryOpposite -Item $Ask -Atoms $Atoms -Individual $one
    $noOpposite = Get-LambekCategoryOpposite -Item $Ask -Atoms $Atoms -Individual $one -No
    $results = @(foreach ($way in $ways) {
            $all = & $with $way
            $result = 'unknown'
            if ([LambekCategories]::Follows($all, $yesOpposite)) { $result = 'yes' }
            elseif ([LambekCategories]::Follows($all, $noOpposite)) { $result = 'no' }
            [pscustomobject]@{ Way = $way; Result = $result }
        })
    $kinds = @($results | ForEach-Object { $_.Result } | Sort-Object -Unique)
    if ($Outcome) {
        if ($kinds -contains 'yes' -and $kinds -contains 'no') { return 'conflict' }
        if ($kinds.Count -eq 1 -and $kinds[0] -ne 'unknown') { return $kinds[0] }
        return $null
    }
    $reason = {
        param([int[]] $way, $opposite)
        $list = [LambekCategoryStatement[]] @(for ($i = 0; $i -lt $Premises.Count; $i++) {
                if ($clause.ContainsKey($i)) { if ($i -in $way) { $condition[$i] } else { [LambekCategoryStatement]::new() } }
                else { $Statements[$i] }
            })
        @([LambekCategories]::Smallest($list, $opposite))
    }
    $listed = { param([int[]] $indices) @(foreach ($i in $indices) { "- $(Format-LambekFact -Fact $Premises[$i].Fact -Language $Language -Register 'vous' -Bare)" }) }
    $lines = [System.Collections.Generic.List[string]]::new()

    if ($kinds -contains 'yes' -and $kinds -contains 'no') {
        $used = [System.Collections.Generic.SortedSet[int]]::new()
        foreach ($result in 'yes', 'no') {
            $way = @($results | Where-Object { $_.Result -eq $result })[0].Way
            foreach ($i in & $reason $way $(if ($result -eq 'yes') { $yesOpposite } else { $noOpposite })) { [void] $used.Add($i) }
        }
        $shown = Get-LambekProblemShown -Holder ([pscustomobject]@{ Key = $(if ($one -eq 'speaker') { 'speaker' } else { "other:$one" }); Written = $who.Written }) -Language $Language
        $lines.Add(($data['Conflict'] -f $shown))
        foreach ($line in & $listed ([int[]] @($used))) { $lines.Add($line) }
        return [pscustomobject]@{ Lines = $lines.ToArray(); Facts = @($used | ForEach-Object { $Premises[$_].Fact }) }
    }
    if ($kinds.Count -ne 1 -or $kinds[0] -eq 'unknown') { return $null }

    $result = $kinds[0]
    $support = & $reason $results[0].Way $(if ($result -eq 'yes') { $yesOpposite } else { $noOpposite })
    $sentence = Get-LambekCategorySentence -Item $Ask -Shape $(if ($result -eq 'yes') { 'is' } else { 'isnot' }) -Language $Language
    # Said in a sentence of its own, read back by a second Lambek; else in lines
    $spoken = $null
    if ($sentence) { $spoken = ConvertTo-LambekSpeech -Verdict "usual$result" -Conclusion $sentence -Premises @($support | ForEach-Object { $Premises[$_] }) -Language $Language }
    if ($spoken) { $lines.Add($spoken.Text) }
    else {
        $lines.Add(($data[$(if ($result -eq 'yes') { 'NormallyYes' } else { 'NormallyNo' })] -f $sentence))
        $lines.Add($data['Assume'])
        foreach ($line in & $listed ([int[]] $support)) { $lines.Add($line) }
    }
    # (what is supposed falls as soon as one says it is an exception)
    $template = $data['ExceptionIs']
    if ($one -eq 'speaker' -and $data.Contains("ExceptionIs|$(@($data['Speaker'])[0])")) { $template = $data["ExceptionIs|$(@($data['Speaker'])[0])"] }
    $built = $template -f $who.Written
    $turned = ConvertTo-LambekOtherSide -Text $built -Language $Language -Register 'vous'
    if ($turned) {
        $turned = $turned.TrimEnd('.')
        if ($built -cmatch '^\p{Ll}') { $turned = $turned.Substring(0, 1).ToLowerInvariant() + $turned.Substring(1) }
        $built = $turned
    }
    $lines.Add(($data['Exception'] -f $built))
    return [pscustomobject]@{ Lines = $lines.ToArray(); Facts = @($support | ForEach-Object { $Premises[$_].Fact }) }
}
