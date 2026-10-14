function Resolve-LambekImagine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # "et si Tweety etait un pingouin ?": a world of its own, made of what was told and of what is imagined, where
    # Lambek reasons as everywhere else. What contradicts what is imagined is set aside, as little as can be (what was
    # said of one before rules about every one), and said. Then what would change is said in the conditional, or the
    # question asked with it is answered there ("..., est-ce qu'il volerait ?"). Nothing told is ever changed: the
    # world is only imagined, it is kept nowhere
    if ($Text -notmatch '\?\s*$') { return $null }
    $language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text)
    $words = Get-LambekCategoryVocabulary -Language $language
    if (-not $words -or -not $words.Data['Imagine']) { return $null }
    $imagine = $words.Data['Imagine']
    $plain = (($Text.Trim() -replace '\?\s*$', '') -replace '\s+', ' ').Trim()
    $rest = $null
    $bare = $false
    foreach ($word in @($imagine['Words']) | Sort-Object { -"$_".Length }) {
        if ($plain.StartsWith("$word", [System.StringComparison]::OrdinalIgnoreCase)) {
            $rest = $plain.Substring("$word".Length).Trim()
            # (a plain "si" may start a rule as well: only what reads as a world of rules about every one is taken then)
            $bare = "$word" -in @($imagine['Bare'])
            break
        }
    }
    if (-not $rest) { return $null }
    $comma = $rest.IndexOf(',')
    $supposed = $(if ($comma -ge 0) { $rest.Substring(0, $comma).Trim() } else { $rest })
    $asked = $(if ($comma -ge 0) { $rest.Substring($comma + 1).Trim() } else { '' })
    if ($supposed -notmatch "^[\p{L}'\u2019 -]+$") { return $null }

    $item = Read-LambekCategorySentence -Sentence $supposed -Language $language -Imagined
    if ($item -and -not "$($item.Kind)".StartsWith('ask')) {
        $reply = Resolve-LambekImagineCategory -Item $item -Supposed $supposed -Asked $asked -Language $language
        if ($reply) { return [pscustomobject]@{ Language = $language; Reply = $reply } }
    }
    if ($bare) { return $null }
    $reply = Resolve-LambekImagineRule -Supposed $supposed -Language $language
    if ($reply) { return [pscustomobject]@{ Language = $language; Reply = $reply } }
    return $null
}

function Get-LambekImagineSentence {
    param([pscustomobject] $Item, [string] $Shape, [string] $Language)

    # A sentence of the imagined world, in the conditional: "Tweety ne volerait pas", "vous seriez mortel"
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $said = $Item.PSObject.Copy()
    $said.Written = $Item.Written.PSObject.Copy()
    if ($Item.Verb) {
        $lemma = (($Item.Predicate.Atoms[0] -replace '^v:', '') -replace '>.*$', '')
        $person = $(if ($Item.Individual -and $Item.Individual.Key -eq 'speaker') { 'speaker' } else { 'one' })
        $tag = "$($data['Imagine']['VerbForms'][$person])"
        $form = $lemma
        if ($tag) {
            $dictionary = Get-LambekDictionary -Language $Language
            $found = @($dictionary.Forms($lemma, $Language, 'v', $tag))
            if ($found.Count -eq 0) { return $null }
            $form = "$($found[0])"
        }
        $said.Written.Predicate = $form
    }
    return Get-LambekCategorySentence -Item $said -Shape $Shape -Language $Language -Shapes 'Imagine'
}

function Resolve-LambekImagineCategory {
    param([pscustomobject] $Item, [string] $Supposed, [string] $Asked, [string] $Language)

    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $imagine = $data['Imagine']
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    $known = @(Get-LambekCategoryKnown -Language $Language)
    $general = @($known | Where-Object { $_.Item.Kind -in 'all', 'no', 'some', 'somenot' })
    if ($general.Count -eq 0 -and $Item.Kind -notin 'all', 'no') { return $null }
    $atoms = @{}
    $premises = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $known) { $premises.Add($entry) }
    $statements = [System.Collections.Generic.List[LambekCategoryStatement]]::new()
    foreach ($entry in $premises) { $statements.Add((ConvertTo-LambekCategoryStatement -Item $entry.Item -Atoms $atoms)) }
    $hypothesis = ConvertTo-LambekCategoryStatement -Item $Item -Atoms $atoms

    # What contradicts what is imagined is set aside, a sentence at a time: one about someone before a rule
    $world = [System.Collections.Generic.List[LambekCategoryStatement]]::new($statements)
    $aside = [System.Collections.Generic.List[int]]::new()
    for ($round = 0; $round -le $premises.Count -and -not [LambekCategories]::Satisfiable([LambekCategoryStatement[]] (@($world) + @($hypothesis))); $round++) {
        $conflict = @([LambekCategories]::Smallest([LambekCategoryStatement[]] $world, $hypothesis))
        if ($conflict.Count -eq 0) { return $null }
        $about = @($conflict | Where-Object { $premises[$_].Item.Kind -in 'is', 'isnot', 'does', 'doesnot' })
        $pick = $(if ($about.Count -gt 0) { $about[-1] } else { $conflict[-1] })
        $world[$pick] = [LambekCategoryStatement]::new()
        $aside.Add($pick)
    }
    $imagined = [pscustomobject]@{ Fact = $null; Item = $Item }
    $worldPremises = @(for ($i = 0; $i -lt $premises.Count; $i++) { if ($i -notin $aside) { $premises[$i] } }) + @($imagined)
    $worldStatements = [LambekCategoryStatement[]] (@(for ($i = 0; $i -lt $premises.Count; $i++) { if ($i -notin $aside) { $statements[$i] } }) + @($hypothesis))
    $status = {
        param([object[]] $with, [LambekCategoryStatement[]] $clauses, $ask)
        $one = $ask.Individual.Key
        if ([LambekCategories]::Follows($clauses, (Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $one))) { return 'yes' }
        if ([LambekCategories]::Follows($clauses, (Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $one -No))) { return 'no' }
        $usual = Resolve-LambekCategoryUsual -Ask $ask -Premises $with -Statements $clauses -Atoms $atoms -Language $Language -Outcome
        if ($usual -in 'yes', 'no') { return "usual-$usual" }
        return 'unknown'
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(($imagine['Header'] -f $Supposed))
    if ($aside.Count -gt 0) {
        $lines.Add($imagine['SetAside'])
        foreach ($i in $aside) { $lines.Add("- $(Format-LambekFact -Fact $premises[$i].Fact -Language $Language -Register 'vous' -Bare)") }
    }

    if ($Asked) {
        # The question asked in that world: "est-ce qu'il volerait ?" is about the one imagined
        $question = Get-LambekImagineQuestion -Asked $Asked -Item $Item -Language $Language
        if (-not $question) { return $null }
        $state = & $status $worldPremises $worldStatements $question
        $sentence = { param($shape) Get-LambekImagineSentence -Item $question -Shape $shape -Language $Language }
        switch ($state) {
            'yes' { $lines.Add(($data['Yes'] -f (& $sentence 'is'))) }
            'no' { $lines.Add(($data['No'] -f (& $sentence 'isnot'))) }
            'usual-yes' { $lines.Add(($data['NormallyYes'] -f (& $sentence 'is'))) }
            'usual-no' { $lines.Add(($data['NormallyNo'] -f (& $sentence 'isnot'))) }
            default { $lines.Add(($imagine['Unknown'] -f ($say['Quote'] -f (& $sentence 'is')))) }
        }
        if ($state -in 'yes', 'no') {
            $opposite = Get-LambekCategoryOpposite -Item $question -Atoms $atoms -Individual $question.Individual.Key -No:($state -eq 'no')
            $support = @([LambekCategories]::Smallest($worldStatements, $opposite))
            $lines.Add($data['Because'])
            foreach ($i in $support) {
                if ($worldPremises[$i].Fact) { $lines.Add("- $(Format-LambekFact -Fact $worldPremises[$i].Fact -Language $Language -Register 'vous' -Bare)") }
                else { $lines.Add("- $Supposed $($imagine['Mark'])") }
            }
        }
        $lines.Add($imagine['Kept'])
        Set-LambekLastProof
        return ($lines -join "`n")
    }

    # What would change: for the one imagined (or everyone named, for a rule), each thing said of anyone
    $people = [System.Collections.Generic.List[object]]::new()
    if ($Item.Individual) { $people.Add($Item.Individual) }
    else { foreach ($entry in $premises) { $one = $entry.Item.Individual; if ($one -and @($people | Where-Object { $_.Key -eq $one.Key }).Count -eq 0) { $people.Add($one) } } }
    $changes = [System.Collections.Generic.List[string]]::new()
    $forms = Get-LambekCategoryForm -Items (@($premises | ForEach-Object { $_.Item }) + @($Item)) -Language $Language
    foreach ($person in $people) {
        $probe = [pscustomobject]@{ Kind = 'askis'; Quantifier = ''; Subject = $null; Individual = $person; Predicate = [pscustomobject]@{ Atoms = @() }; Verb = $false; Member = $false; Written = [pscustomobject]@{ Subject = $person.Written; Predicate = ''; Object = '' } }
        foreach ($candidate in @(Get-LambekCategoryCandidate -Ask $probe -Forms $forms -Language $Language)) {
            $ask = $candidate.Yes.PSObject.Copy()
            $ask.Kind = $(if ($ask.Verb) { 'askdoes' } else { 'askis' })
            if ($Item.Individual -and $person.Key -eq $Item.Individual.Key -and (($ask.Predicate.Atoms) -join '+') -eq (($Item.Predicate.Atoms) -join '+')) { continue }
            $before = & $status @($premises) ([LambekCategoryStatement[]] $statements) $ask
            $after = & $status $worldPremises $worldStatements $ask
            if ($before -eq $after) { continue }
            if ($after -eq 'unknown') {
                $now = Get-LambekCategorySentence -Item $ask -Shape 'is' -Language $Language
                $changes.Add((Get-LambekWhyElided -Text ($imagine['Lost'] -f $now) -Language $Language) + '.')
                continue
            }
            $shape = $(if ($after -in 'yes', 'usual-yes') { 'is' } else { 'isnot' })
            $said = Get-LambekImagineSentence -Item $ask -Shape $shape -Language $Language
            if (-not $said) { continue }
            if ($after.StartsWith('usual')) { $said = "$($imagine['Usual'])$said" }
            $changes.Add("- $said.")
        }
    }
    foreach ($line in $changes) { $lines.Add($line) }
    if ($changes.Count -eq 0) { $lines.Add($imagine['Nothing']) }
    $lines.Add($imagine['Kept'])
    Set-LambekLastProof
    return ($lines -join "`n")
}

function Get-LambekImagineQuestion {
    param([string] $Asked, [pscustomobject] $Item, [string] $Language)

    # "est-ce qu'il volerait", "volerait-il", "would he fly": the question about the one imagined, read as a question
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $pronouns = @($data['Imagine']['Pronouns'])
    $question = $Asked.Trim()
    if ($Item.Individual -and $pronouns.Count -gt 0) {
        $name = $Item.Individual.Written
        $alt = ($pronouns | ForEach-Object { [regex]::Escape("$_") }) -join '|'
        $inverted = [regex]::Match($question, "(?i)^(\S+?)-(?:t-)?(?:$alt)(?![\p{L}])(.*)$")
        if ($inverted.Success) { $question = "$($data['Imagine']['AskPrefix'])$name $($inverted.Groups[1].Value)$($inverted.Groups[2].Value)" }
        $question = [regex]::Replace($question, "(?i)(?<![\p{L}])qu['\u2019](?:$alt)(?![\p{L}])", "que $name")
        $question = [regex]::Replace($question, "(?i)(?<![\p{L}])(?:$alt)(?![\p{L}])", $name)
    }
    $question = (($question -replace ',', ' ') -replace '\s+', ' ').Trim()
    $read = Read-LambekCategorySentence -Sentence $question -Language $Language -Question -Imagined
    if (-not $read -or $read.Kind -notin 'askis', 'askdoes') { return $null }
    return $read
}

function Resolve-LambekImagineRule {
    param([string] $Supposed, [string] $Language)

    # "et s'il pleuvait ?" with rules told with "si": what the rules would give from it, and what it would set aside
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $imagine = $data['Imagine']
    try { $request = ConvertTo-LambekRequest -Text $Supposed -Language $Language } catch { return $null }
    $reading = Get-LambekGeneralReading -Request $request
    if (-not $reading -or $reading.Kind -ne 'statement') { return $null }
    $fact = ConvertTo-LambekGeneralFact -Reading $reading -Request $request
    $held = @(Get-LambekWhyHeld)
    $rules = @($held | Where-Object { $_.PSObject.Properties['Condition'] -and $_.Condition })
    if ($rules.Count -eq 0) { return $null }
    $facts = @($held | Where-Object { -not ($_.PSObject.Properties['Condition'] -and $_.Condition) })
    $opposite = [pscustomobject]@{ Core = "$($fact.Core)"; Negated = -not [bool] $fact.Negated }
    $aside = @($facts | Where-Object { Test-LambekHold -Fact $_ -Condition $opposite })
    $world = @($rules) + @($facts | Where-Object { $aside -notcontains $_ }) + @($fact)
    $before = @(Get-LambekDeduced -Facts $held | Where-Object { $_.PSObject.Properties['Deduced'] -and $_.Deduced } | ForEach-Object { [LambekBoard]::Canonical("$($_.Core)") })
    $after = @(Get-LambekDeduced -Facts $world | Where-Object { $_.PSObject.Properties['Deduced'] -and $_.Deduced })
    $new = @($after | Where-Object { [LambekBoard]::Canonical("$($_.Core)") -notin $before -and (Get-LambekProofLeaf -Fact $_) -contains $fact })
    # (the board keeps only what follows from what was told)
    [void] (Get-LambekDeduced -Facts $held)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(($imagine['Header'] -f $Supposed))
    if ($aside.Count -gt 0) {
        $lines.Add($imagine['SetAside'])
        foreach ($other in $aside) { $lines.Add("- $(Format-LambekFact -Fact $other -Language $Language -Register 'vous' -Bare)") }
    }
    if ($new.Count -gt 0) {
        $lines.Add($imagine['Follows'])
        foreach ($consequence in $new) { $lines.Add("- $(Format-LambekFact -Fact $consequence -Language $Language -Register 'vous' -Bare)") }
    }
    else { $lines.Add($imagine['Nothing']) }
    $lines.Add($imagine['Kept'])
    Set-LambekLastProof
    return ($lines -join "`n")
}
