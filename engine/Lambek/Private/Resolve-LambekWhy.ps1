function Resolve-LambekWhy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # "pourquoi la route est mouillee ?": what explains a thing told. First what it follows from (a rule told with "si",
    # or a rule about every one, and what makes it hold); else the explanations it could have, each a thing that would
    # make it follow and that nothing told goes against (abduction), the one that would explain the most of what was
    # told first; then the question that would tell them apart. Never a cause that was not told as one
    if ($Text -notmatch '\?\s*$') { return $null }
    $language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text)
    $dialogue = (Get-LambekLexicon -Language $language).Dialogue
    if (-not $dialogue -or -not $dialogue['Abduction']) { return $null }
    $words = $dialogue['Abduction']
    $plain = (($Text.Trim() -replace '\?\s*$', '') -replace '\s+', ' ').Trim()
    $rest = $null
    foreach ($word in @($words['Words']) | Sort-Object { -"$_".Length }) {
        if ($plain.StartsWith("$word", [System.StringComparison]::OrdinalIgnoreCase)) { $rest = $plain.Substring("$word".Length).Trim(); break }
    }
    if (-not $rest) { return $null }

    $observed = @(Get-LambekWhyStatement -Rest $rest -Language $language)
    if ($observed.Count -eq 0) { return $null }
    foreach ($statement in $observed) {
        # (a rule told with "si" says what causes what: it goes before a rule about every one)
        $answer = Get-LambekWhyRule -Statement $statement -Language $language
        if (-not $answer) { $answer = Get-LambekWhyCategory -Statement $statement -Language $language }
        if ($answer) { return [pscustomobject]@{ Language = $language; Reply = $answer } }
    }
    return $null
}

function Get-LambekWhyStatement {
    param([string] $Rest, [string] $Language)

    # What "pourquoi ..." asks about, as the sentence that says it: "Minou est-il noir" is "Minou est noir",
    # "suis-je mortel" is "je suis mortel"; "is the road wet" is "the road is wet", tried at every cut
    $words = (Get-LambekLexicon -Language $Language).Dialogue['Abduction']
    $said = [System.Collections.Generic.List[string]]::new()
    $inverted = @($words['Inverted'])
    if ($inverted.Count -gt 0) {
        $alt = ($inverted | ForEach-Object { [regex]::Escape("$_") }) -join '|'
        $straight = [regex]::Replace($Rest, "(?i)(\S+?)(?:-t)?-(?:$alt)(?![\p{L}])", '$1')
        $me = [regex]::Match($straight, '(?i)^(\S+?)-je(?![\p{L}])\s*(.*)$')
        if ($me.Success) { $straight = "je $($me.Groups[1].Value) $($me.Groups[2].Value)".Trim() }
        $said.Add($straight)
    }
    else { $said.Add($Rest) }
    $tokens = @($Rest -split ' ')
    $first = $tokens[0].ToLowerInvariant()
    if ($tokens.Count -ge 3 -and ($first -in @($words['Auxiliaries']) -or $first -in @($words['Do']))) {
        for ($cut = 2; $cut -lt $tokens.Count; $cut++) {
            $who = ($tokens[1..($cut - 1)] -join ' ')
            $what = ($tokens[$cut..($tokens.Count - 1)] -join ' ')
            if ($first -in @($words['Auxiliaries'])) { $said.Add("$who $($tokens[0]) $what") } else { $said.Add("$who $($tokens[0]) $what"); $said.Add("$who $what") }
        }
    }
    return @($said | Select-Object -Unique)
}

function Get-LambekWhyHeld {
    # Everything told, here and before, once each
    $told = @((Get-LambekTold).ToArray())
    $here = @($told | Where-Object { $_.PSObject.Properties['Hash'] -and $_.Hash } | ForEach-Object { $_.Hash })
    return @(@((Get-LambekToldJournal).ToArray() | Where-Object { $_.Hash -notin $here }) + @($told))
}

function Get-LambekWhyCategory {
    param([string] $Statement, [string] $Language)

    # "pourquoi Minou est noir ?" with rules about every one: what it follows from, else what Minou would have to be
    $read = Read-LambekCategorySentence -Sentence $Statement -Language $Language
    if (-not $read -or $read.Kind -notin 'is', 'does' -or -not $read.Individual) { return $null }
    $quantified = 'all', 'no', 'some', 'somenot'
    $known = @(Get-LambekCategoryKnown -Language $Language)
    if (@($known | Where-Object { $_.Item.Kind -in $quantified -and -not ($_.Item.PSObject.Properties['Default'] -and $_.Item.Default) }).Count -eq 0) { return $null }
    $abduction = (Get-LambekLexicon -Language $Language).Dialogue['Abduction']
    # (what was told of it in so many words is not why it is so)
    $itself = Get-LambekCategorySignature -Item $read
    $premises = @($known | Where-Object { (Get-LambekCategorySignature -Item $_.Item) -cne $itself })
    $atoms = @{}
    $statements = [LambekCategoryStatement[]] @($premises | ForEach-Object { ConvertTo-LambekCategoryStatement -Item $_.Item -Atoms $atoms })
    if (-not [LambekCategories]::Satisfiable($statements)) { return $null }
    $ask = [pscustomobject]@{ Kind = $(if ($read.Kind -eq 'does') { 'askdoes' } else { 'askis' }); Quantifier = ''; Subject = $null; Individual = $read.Individual; Predicate = $read.Predicate; Verb = $read.Verb; Member = $read.Member; Written = $read.Written }
    $opposite = Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $read.Individual.Key
    $listed = { param([int[]] $indices) @(foreach ($i in $indices) { "- $(Format-LambekFact -Fact $premises[$i].Fact -Language $Language -Register 'vous' -Bare)" }) }
    $lines = [System.Collections.Generic.List[string]]::new()
    $support = [LambekCategories]::Smallest($statements, $opposite)
    if ($null -ne $support) {
        $lines.Add($abduction['Deduced'])
        foreach ($line in & $listed $support) { $lines.Add($line) }
        Set-LambekLastProof -Facts @($support | ForEach-Object { $premises[$_].Fact })
        return ($lines -join "`n")
    }
    # What it would have to be, for what was told to give it: each kind a rule about every one starts from
    $forms = Get-LambekCategoryForm -Items (@($premises | ForEach-Object { $_.Item }) + @($ask)) -Language $Language
    $found = [System.Collections.Generic.List[object]]::new()
    $ruledOut = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in @(Get-LambekCategoryCandidate -Ask $ask -Forms $forms -Language $Language)) {
        if ((($candidate.Yes.Predicate.Atoms) -join '+') -eq (($read.Predicate.Atoms) -join '+')) { continue }
        $yes = ConvertTo-LambekCategoryStatement -Item $candidate.Yes -Atoms $atoms
        $with = [LambekCategoryStatement[]] (@($statements) + @($yes))
        if (-not [LambekCategories]::Follows($with, $opposite)) { continue }
        $rule = [LambekCategories]::Smallest($with, $opposite)
        if (-not [LambekCategories]::Satisfiable($with)) { $ruledOut.Add($candidate); continue }
        $found.Add([pscustomobject]@{ Candidate = $candidate; Rules = @($rule | Where-Object { $_ -lt $premises.Count }) })
    }
    if ($found.Count -eq 0) { return $null }
    $lines.Add(($abduction[$(if ($found.Count -eq 1) { 'PossibleOne' } else { 'PossibleMany' })] -f $found.Count))
    foreach ($entry in $found) {
        $because = Get-LambekCategorySentence -Item $entry.Candidate.Yes -Shape 'is' -Language $Language
        $rules = @($entry.Rules | ForEach-Object { (Format-LambekFact -Fact $premises[$_].Fact -Language $Language -Register 'vous' -Bare).TrimEnd('.') }) -join ' ; '
        $lines.Add((Get-LambekWhyElided -Text ($abduction['Maybe'] -f $because, $rules) -Language $Language))
    }
    foreach ($candidate in $ruledOut) {
        $because = Get-LambekCategorySentence -Item $candidate.Yes -Shape 'is' -Language $Language
        $lines.Add((Get-LambekWhyElided -Text ($abduction['Not'] -f $because) -Language $Language))
    }
    Set-LambekLastProof
    return ($lines -join "`n")
}

function Get-LambekWhyRule {
    param([string] $Statement, [string] $Language)

    # "pourquoi la route est mouillee ?" with rules told with "si": the rules that give it, each with its condition
    # held (then it is why), told false (then it is not why), or not told (then it may be why)
    try { $request = ConvertTo-LambekRequest -Text $Statement -Language $Language } catch { return $null }
    $reading = Get-LambekGeneralReading -Request $request
    if (-not $reading -or $reading.Kind -ne 'statement') { return $null }
    $observed = ConvertTo-LambekGeneralFact -Reading $reading -Request $request
    $held = @(Get-LambekWhyHeld)
    $rules = @($held | Where-Object { $_.PSObject.Properties['Condition'] -and $_.Condition })
    # (a sentence kept as a rule about every one, "les toits sont mouilles", is also the thing it says: read so here)
    $facts = @($held | Where-Object { -not ($_.PSObject.Properties['Condition'] -and $_.Condition) } | ForEach-Object { Get-LambekWhyFact -Fact $_ })
    # (only a thing told is explained here: what was deduced is said with what it was deduced from, elsewhere)
    if (@($facts | Where-Object { Test-LambekHold -Fact $_ -Condition $observed }).Count -eq 0) { return $null }
    $then = { param($rule) [pscustomobject]@{ Core = "$($rule.Then)"; Negated = [bool] ($rule.PSObject.Properties['Negated'] -and $rule.Negated) } }
    $giving = @($rules | Where-Object { Test-LambekHold -Fact $observed -Condition (& $then $_) })
    if ($giving.Count -eq 0) { return $null }
    $abduction = (Get-LambekLexicon -Language $Language).Dialogue['Abduction']
    $flip = { param($fact) [pscustomobject]@{ Core = "$($fact.Core)"; Negated = -not [bool] ($fact.PSObject.Properties['Negated'] -and $fact.Negated) } }
    $lines = [System.Collections.Generic.List[string]]::new()

    # Its condition held: that is why (said with the rule and the thing that made it hold)
    foreach ($rule in $giving) {
        $because = @($facts | Where-Object { Test-LambekHold -Fact $_ -Condition $rule.Condition } | Select-Object -First 1)
        if ($because.Count -eq 0) { continue }
        $lines.Add($abduction['Deduced'])
        $lines.Add("- $(Format-LambekFact -Fact $rule -Language $Language -Register 'vous' -Bare)")
        $lines.Add("- $(Format-LambekFact -Fact $because[0] -Language $Language -Register 'vous' -Bare)")
        Set-LambekLastProof -Facts @($rule, $because[0])
        return ($lines -join "`n")
    }

    # Else what may be why: each condition nothing told goes against, the one that would explain the most first
    $candidates = [System.Collections.Generic.List[object]]::new()
    $ruledOut = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $giving) {
        if (@($facts | Where-Object { Test-LambekHold -Fact $_ -Condition (& $flip $rule.Condition) }).Count -gt 0) { $ruledOut.Add($rule); continue }
        # (what else told it would explain: the things told that a rule from the same condition gives)
        $same = @($rules | Where-Object { [LambekBoard]::Canonical((Get-LambekCoreTermOf -Core "$($_.Condition.Core)")) -ceq [LambekBoard]::Canonical((Get-LambekCoreTermOf -Core "$($rule.Condition.Core)")) })
        $explains = @($facts | Where-Object { $fact = $_; -not (Test-LambekHold -Fact $fact -Condition $observed) -and @($same | Where-Object { Test-LambekHold -Fact $fact -Condition (& $then $_) }).Count -gt 0 })
        $candidates.Add([pscustomobject]@{ Rule = $rule; Explains = $explains; Order = $candidates.Count })
    }
    if ($candidates.Count -eq 0 -and $ruledOut.Count -eq 0) { return $null }
    $ranked = @($candidates | Sort-Object -Stable { - $_.Explains.Count }, { $_.Order })
    $sentence = {
        param($fact)
        $said = Get-LambekFactSentence -Fact $fact -Register 'vous'
        if ($said) { return (Format-LambekInline -Text $said -Language $Language) }
        return ((Get-LambekLexicon -Language $Language).Dialogue.Say['Quote'] -f "$($fact.Text)".Trim())
    }
    if ($ranked.Count -gt 0) { $lines.Add(($abduction[$(if ($ranked.Count -eq 1) { 'PossibleOne' } else { 'PossibleMany' })] -f $ranked.Count)) }
    foreach ($candidate in $ranked) {
        $lines.Add((Get-LambekWhyElided -Text ($abduction['Maybe'] -f (& $sentence $candidate.Rule.Condition), (Format-LambekFact -Fact $candidate.Rule -Language $Language -Register 'vous' -Bare).TrimEnd('.')) -Language $Language))
        foreach ($other in $candidate.Explains) { $lines.Add(($abduction['AlsoExplains'] -f (& $sentence $other))) }
    }
    foreach ($rule in $ruledOut) { $lines.Add((Get-LambekWhyElided -Text ($abduction['Not'] -f (& $sentence $rule.Condition)) -Language $Language)) }

    # The question that would tell them apart: something a rule gives from one of them, that was not told either way
    if ($ranked.Count -gt 0) {
        $best = $null
        foreach ($candidate in $ranked) {
            $from = Get-LambekCoreTermOf -Core "$($candidate.Rule.Condition.Core)"
            foreach ($rule in $rules) {
                if ([LambekBoard]::Canonical((Get-LambekCoreTermOf -Core "$($rule.Condition.Core)")) -cne [LambekBoard]::Canonical($from)) { continue }
                $consequence = & $then $rule
                if (Test-LambekHold -Fact $observed -Condition $consequence) { continue }
                if (@($facts | Where-Object { (Test-LambekHold -Fact $_ -Condition $consequence) -or (Test-LambekHold -Fact $_ -Condition (& $flip $consequence)) }).Count -gt 0) { continue }
                # (one the others do not give tells them apart; with one explanation, it checks it)
                $shared = @($ranked | Where-Object { $_ -ne $candidate } | Where-Object {
                        $other = Get-LambekCoreTermOf -Core "$($_.Rule.Condition.Core)"
                        @($rules | Where-Object { [LambekBoard]::Canonical((Get-LambekCoreTermOf -Core "$($_.Condition.Core)")) -ceq [LambekBoard]::Canonical($other) -and "$($_.Then)" -ceq "$($rule.Then)" }).Count -gt 0
                    }).Count
                if ($shared -eq 0) { $best = [pscustomobject]@{ Rule = $rule; Candidate = $candidate }; break }
            }
            if ($best) { break }
        }
        if ($best) {
            $asked = Get-LambekWhyElided -Text ($abduction['Ask'] -f (& $sentence $best.Rule)) -Language $Language
            $lines.Add(($abduction[$(if ($ranked.Count -gt 1) { 'Decide' } else { 'Check' })] -f $asked))
            $lines.Add((Get-LambekWhyElided -Text ($abduction['IfNo'] -f (& $sentence $best.Candidate.Rule.Condition)) -Language $Language))
        }
    }
    Set-LambekLastProof -Facts @($giving)
    return ($lines -join "`n")
}

function Get-LambekWhyFact {
    param([pscustomobject] $Fact)

    # A thing told as it is read by the grammar: a general rule told is read again as a sentence about something
    if ("$($Fact.Action)" -ne 'verb:category' -or -not $Fact.Text) { return $Fact }
    $sentence = ("$($Fact.Text)".Trim() -replace '[.!;]+\s*$', '')
    try { $request = ConvertTo-LambekRequest -Text $sentence -Language "$($Fact.Language)" } catch { return $Fact }
    $reading = Get-LambekGeneralReading -Request $request
    if (-not $reading -or $reading.Kind -ne 'statement') { return $Fact }
    return (ConvertTo-LambekGeneralFact -Reading $reading -Request $request)
}

function Get-LambekWhyElided {
    param([string] $Text, [string] $Language)

    # "parce que il pleut" is said "parce qu'il pleut"
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    if ($general -and $general['Elide']) { foreach ($pair in $general['Elide'].GetEnumerator()) { $Text = [regex]::Replace($Text, "(?<!\p{L})$([regex]::Escape($pair.Key))(?!\p{L})", $pair.Value) } }
    return $Text
}
