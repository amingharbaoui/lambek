function Resolve-LambekCategoryBelief {
    param([object[]] $Items, [object[]] $Known, [string] $Language)

    # "Alice croit-elle que Tom est noir ?": answered from what Alice was told to believe, and to know, alone; never
    # from what is so, nor from what anyone else believes ("Alice croit que tous les chats sont noirs", "Alice croit que
    # Tom est un chat": yes; "Tom est un chat" told as so: Alice may not know it). Yes when what she believes cannot be
    # true without it, no when it cannot be true with it, else it cannot be concluded; what she believes cannot all be
    # true together, nothing is concluded from it either. Told that she does not believe it ("Alice ne croit pas que Tom
    # est noir"): no; told both that she believes it and that she does not, the four values: both, said as what was told
    # that cannot be true together
    $asked = @($Items | Where-Object { $_.Item.Kind -eq 'askbelieve' })
    if ($asked.Count -ne 1) { return $null }
    $ask = $asked[0].Item
    $holder = $ask.Holder.Individual.Key
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say

    # What is told with the question is kept as told
    $facts = @(foreach ($entry in $Items) { if (-not "$($entry.Item.Kind)".StartsWith('ask')) { ConvertTo-LambekCategoryFact -Sentence $entry.Sentence -Item $entry.Item -Language $Language } })
    $told = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Known) { $told.Add($entry) }
    $k = 0
    foreach ($entry in $Items) { if (-not "$($entry.Item.Kind)".StartsWith('ask')) { $told.Add([pscustomobject]@{ Fact = $facts[$k]; Item = $entry.Item }); $k++ } }
    $held = { param($item) $item.PSObject.Properties['Holder'] -and $item.Holder -and $item.Holder.Individual -and $item.Holder.Individual.Key -eq $holder }
    $beliefs = @($told | Where-Object { $_.Fact -and (& $held $_.Item) -and ($_.Item.Kind -eq 'believe' -or ($_.Item.PSObject.Properties['Attitude'] -and $_.Item.Attitude -eq 'know')) })
    $content = { param($item) if ($item.Kind -eq 'believe') { $item.Content } else { $item } }
    $inner = { param($item) "$((Get-LambekCategorySignature -Item $item) -replace '\|', '~')" }
    $believed = { param($item) "category(believe|$holder|$(& $inner $item))" }

    $atoms = @{}
    $statements = [LambekCategoryStatement[]] @($beliefs | ForEach-Object { ConvertTo-LambekCategoryStatement -Item (& $content $_.Item) -Atoms $atoms })
    $keys = [string[]] @($beliefs | ForEach-Object { Get-LambekCategorySignature -Item (& $content $_.Item) })
    $said = $ask.Content
    $asking = @{ is = 'askis'; does = 'askdoes'; all = 'askall'; no = 'askno'; some = 'asksome'; somenot = 'asksomenot'; isnot = 'askis'; doesnot = 'askdoes' }
    $flip = $said.Kind -in 'isnot', 'doesnot'
    $question = $said.PSObject.Copy()
    $question.Kind = $asking[$said.Kind]
    $who = $(if ($said.Individual) { $said.Individual.Key } else { '' })
    $answer = 'unknown'
    $found = $null
    if ($statements.Count -gt 0 -and [LambekCategories]::Satisfiable($statements)) {
        $yes = Get-LambekCategoryOpposite -Item $question -Atoms $atoms -Individual $who -No:$flip
        $found = [LambekCategories]::Shortest($statements, $yes, $keys, [LambekCategories]::DefaultBudget)
        if ($found) { $answer = 'yes' }
        else {
            $no = Get-LambekCategoryOpposite -Item $question -Atoms $atoms -Individual $who -No:(-not $flip)
            $found = [LambekCategories]::Shortest($statements, $no, $keys, [LambekCategories]::DefaultBudget)
            if ($found) { $answer = 'no' }
        }
    }

    # (what she was told not to believe, the very sentence asked)
    $askedSign = "$(& $inner $said)"
    $denied = @($told | Where-Object { $_.Fact -and $_.Item.Kind -eq 'notbelieve' -and (& $held $_.Item) -and (& $inner $_.Item.Content) -eq $askedSign })
    $verdict = Get-LambekVerdict -For ($answer -eq 'yes') -Against ($answer -eq 'no' -or $denied.Count -gt 0)

    $lines = [System.Collections.Generic.List[string]]::new()
    if ($verdict -eq 'both' -and $denied.Count -gt 0) {
        $lines.Add($data['Contradiction'])
        $used = @(@($found.Indices | ForEach-Object { $beliefs[$_] }) + @($denied[0]))
        foreach ($entry in $used) { $lines.Add("- $(Format-LambekFact -Fact $entry.Fact -Language $Language -Register 'vous' -Bare)") }
        Set-LambekLastProof -Facts @($used | ForEach-Object { $_.Fact }) -Verdict 'both'
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }
    if ($answer -eq 'unknown' -and $denied.Count -gt 0) {
        $lines.Add($data['NoShort'])
        if ($data['Because']) { $lines.Add($data['Because']) }
        $lines.Add("- $(Format-LambekFact -Fact $denied[0].Fact -Language $Language -Register 'vous' -Bare)")
        Set-LambekLastProof -Facts @($denied[0].Fact) -Verdict 'false'
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }
    # The answer said as it was told of the one who believes, with the words asked: "Alice croit que Tom est noir"
    $lead = $null
    foreach ($belief in @($told | Where-Object { $_.Fact -and (& $held $_.Item) -and $_.Item.Kind -eq 'believe' -and $_.Item.Holder.Verb -eq $ask.Holder.Verb })) {
        $at = [regex]::Match("$($belief.Fact.Text)", "(?i)^(?<lead>.*?[\s,]+$([regex]::Escape("$($belief.Item.Holder.Said)")))\s")
        if ($at.Success) { $lead = $at.Groups['lead'].Value; break }
    }
    $sentence = $(if ($lead) { "$lead $($ask.Inner)" } else { $null })
    if ($answer -eq 'unknown') {
        Set-LambekLastProof
        # (else as it was asked)
        if (-not $sentence) { $sentence = "$($asked[0].Sentence.Text)".Trim().TrimEnd('?').Trim() }
        $lines.Add(($data['Unknown'] -f ($say['Quote'] -f $sentence)))
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }
    $used = @($found.Indices | ForEach-Object { $beliefs[$_] })
    $lines.Add($(if ($answer -eq 'yes' -and $sentence -and $data['Yes']) { $data['Yes'] -f $sentence } elseif ($answer -eq 'yes') { $data['YesShort'] } else { $data['NoShort'] }))
    if ($data['Because']) { $lines.Add($data['Because']) }
    foreach ($entry in $used) { $lines.Add("- $(Format-LambekFact -Fact $entry.Fact -Language $Language -Register 'vous' -Bare)") }
    # What the answer rests on, for a "pourquoi ?" and the checker: each belief as what Alice believes, and what she
    # believes or not as the conclusion
    $opposite = @{ is = 'isnot'; isnot = 'is'; does = 'doesnot'; doesnot = 'does'; all = 'somenot'; somenot = 'all'; no = 'some'; some = 'no' }
    $concluded = $said.PSObject.Copy()
    if ($answer -eq 'no') { $concluded.Kind = $opposite[$said.Kind] }
    Set-LambekLastProof -Facts @($used | ForEach-Object { $_.Fact }) -Conclusion @(& $believed $concluded) `
        -Forms @($used | ForEach-Object { & $believed (& $content $_.Item) }) -Least $found -Verdict $verdict
    return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
}
