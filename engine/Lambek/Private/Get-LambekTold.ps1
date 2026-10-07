function Get-LambekTold {
    # What the user told in this conversation, oldest first. The app gives each chat its own list;
    # without it, the session is the conversation. Nothing here is written to disk
    if ($null -eq $script:Told) { $script:Told = [System.Collections.Generic.List[object]]::new() }
    return , $script:Told
}

function Add-LambekTold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    # The meanings read in the plan are kept, once each, and the oldest go when there are too many
    $told = Get-LambekTold
    foreach ($step in @($Plan.Steps)) {
        if (-not $step.PSObject.Properties['Statement'] -or -not $step.Statement) { continue }
        if (@($told | Where-Object { $_.Form -ceq $step.Statement.Form }).Count -gt 0) { continue }
        $told.Add($step.Statement)
    }
    while ($told.Count -gt 50) { $told.RemoveAt(0) }
}

function Format-LambekFact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Fact,

        [Parameter(Mandatory)]
        [string] $Language
    )

    # One thing told, said back: who, what, when
    $lexicon = Get-LambekLexicon -Language $Language
    $say = $lexicon.Dialogue.Say
    $what = Get-LambekStepSentence -Step ([pscustomobject]@{ Action = $Fact.Action; Parameters = $Fact.Parameters; Output = $null }) -Language $Language -Units $lexicon.Answer.Units -Unchecked
    $who = $say['Speaker']
    if ($Fact.Agent -ne 'speaker') { $who = $Fact.Name }
    $when = ''
    if ($Fact.Time) { $when = $say['When'] -f $Fact.Time }
    $shape = 'Fact'
    if ($Fact.Wish) { $shape = 'FactWished' }
    return $say[$shape] -f $who, $what, $when
}

function Get-LambekToldAnswer {
    [CmdletBinding()]
    param(
        # What is asked: the actions the verb names, the values given, who, when
        [Parameter(Mandatory)]
        [pscustomobject] $Asked,

        [Parameter(Mandatory)]
        [string] $Language
    )

    # The answer to a question about what was told: the things told that agree with every word of the question.
    # It never says more than the user said, and says so when nothing was told
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    $told = @((Get-LambekTold).ToArray())
    if ($told.Count -eq 0) { return $say['NothingTold'] }
    $found = @(foreach ($fact in $told) {
            if ($Asked.All) { $fact; continue }
            if ($fact.Action -notin @($Asked.Actions)) { continue }
            if ($Asked.Person -and $fact.Agent -ne $Asked.Person) { continue }
            if ($Asked.Time -and "$($fact.Time)" -ne $Asked.Time) { continue }
            $same = $true
            foreach ($name in $Asked.Parameters.Keys) {
                if (-not $fact.Parameters.Contains($name) -or (Format-LambekValue -Value $fact.Parameters[$name]) -ne (Format-LambekValue -Value $Asked.Parameters[$name])) { $same = $false; break }
            }
            if ($same) { $fact }
        })
    if ($found.Count -eq 0) { return $say['NotTold'] }
    $lines = @($say['Recalled']) + @($found | ForEach-Object { "- $(Format-LambekFact -Fact $_ -Language $Language)" })
    return $lines -join "`n"
}

function Get-LambekSaidTime {
    param([pscustomobject] $Request)

    # When: the longest words of time in the sentence, as the user wrote them
    $dialogue = (Get-LambekLexicon -Language $Request.Language).Dialogue
    $text = " $(@($Request.Tokens) -join ' ') "
    foreach ($phrase in @($dialogue['Times']) | Sort-Object { -$_.Length }, { $_ }) {
        if ($text.Contains(" $phrase ")) { return Get-LambekWritten -Request $Request -Words @($phrase -split ' ') }
    }
    return $null
}

function Get-LambekWritten {
    param([pscustomobject] $Request, [string[]] $Words)

    # The words as the user wrote them, with their accents and capitals
    $written = @{}
    foreach ($match in [regex]::Matches("$($Request.Original)", '[\p{L}\p{N}]+')) {
        $plain = ConvertTo-LambekNormalizedText -Text $match.Value
        if (-not $written.ContainsKey($plain)) { $written[$plain] = $match.Value }
    }
    return (@($Words | ForEach-Object { if ($written.ContainsKey($_)) { $written[$_] } else { $_ } }) -join ' ')
}

function Get-LambekAsked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        [Parameter(Mandatory)]
        [pscustomobject] $Grammar,

        [Parameter(Mandatory)]
        [pscustomobject] $Act,

        # The actions the words of the sentence may name
        [object[]] $Candidates = @()
    )

    # What a question about the past asks for: "what did I delete yesterday" asks for what was told
    # with that verb, by that person, at that time, and with every value the question names
    if ($Act.Rule -eq 'told') { return [pscustomobject]@{ All = $true; Actions = @(); Parameters = [ordered]@{}; Person = $null; Time = $null } }
    if ($Act.Rule -ne 'recall' -or -not $Act.Subject) { return $null }
    $verb = @($Request.Words)[$Act.Subject.Verb]
    $actions = @($Candidates | ForEach-Object { $_.Action } | Where-Object { $verb -in $_.Verbs })
    if ($actions.Count -eq 0) { return $null }
    $values = [ordered]@{}
    if (@($Request.Entities | Where-Object { $_.Type -ne 'number' }).Count -gt 0) {
        $values = (Get-LambekParameter -Action $actions[0] -Request $Request -Grammar $Grammar).Values
    }
    [pscustomobject]@{
        All        = $false
        Actions    = @($actions | ForEach-Object { $_.Id })
        Parameters = $values
        Person     = $Act.Subject.Person
        Time       = Get-LambekSaidTime -Request $Request
    }
}
