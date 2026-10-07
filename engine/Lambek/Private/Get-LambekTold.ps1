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

    # The meanings read in the plan are kept, once each, and the oldest go when there are too many.
    # Each one is also written in the journal, with the day and the words it was told in
    $told = Get-LambekTold
    foreach ($step in @($Plan.Steps)) {
        if ($step.PSObject.Properties['Asked'] -and $step.Asked -and $step.Asked.PSObject.Properties['Forget'] -and $step.Asked.Forget) { Clear-LambekTold; return }
        if (-not $step.PSObject.Properties['Statement'] -or -not $step.Statement) { continue }
        if (@($told | Where-Object { $_.Form -ceq $step.Statement.Form }).Count -gt 0) { continue }
        $told.Add($step.Statement)
        Write-LambekToldJournal -Fact $step.Statement
    }
    while ($told.Count -gt 50) { $told.RemoveAt(0) }
}

function Get-LambekNow {
    # The time it is: tests set it, so that "yesterday" is the same day at every run
    if ($script:Now) { return [datetime] $script:Now }
    return [datetime]::Now
}

function Get-LambekSaidDay {
    param([pscustomobject] $Request)

    # The day, week, month or year the words of time point at, counted from today:
    # "yesterday" told on Tuesday and "yesterday" asked on Friday are not the same day
    $dialogue = (Get-LambekLexicon -Language $Request.Language).Dialogue
    if (-not $dialogue -or -not $dialogue['Times']) { return $null }
    $text = " $(@($Request.Tokens) -join ' ') "
    foreach ($phrase in @($dialogue['Times'].Keys) | Sort-Object { -$_.Length }, { $_ }) {
        if (-not $text.Contains(" $phrase ")) { continue }
        $unit, $offset = "$($dialogue['Times'][$phrase])" -split ':'
        $today = (Get-LambekNow).Date
        $invariant = [cultureinfo]::InvariantCulture
        switch ($unit) {
            'day' { return $today.AddDays([int] $offset).ToString('yyyy-MM-dd', $invariant) }
            'week' {
                $day = $today.AddDays(7 * [int] $offset)
                return '{0:0000}-W{1:00}' -f [System.Globalization.ISOWeek]::GetYear($day), [System.Globalization.ISOWeek]::GetWeekOfYear($day)
            }
            'month' { return $today.AddMonths([int] $offset).ToString('yyyy-MM', $invariant) }
            'year' { return $today.AddYears([int] $offset).ToString('yyyy', $invariant) }
        }
        return $null
    }
    return $null
}

function Write-LambekToldJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Fact
    )

    # One line per thing told, never changed afterwards: each line carries the hash of the line before,
    # so a line added, removed or edited by hand is seen when the journal is read. Nothing is written in an incognito chat
    $now = Get-LambekNow
    $Fact.Told = $now.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    if ($script:Incognito) { return }
    $folder = Split-Path -Path $script:ToldPath -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
    # The line follows the last one that can be trusted
    $journal = Get-LambekToldJournal
    $previousHash = ''
    if ($journal.Count -gt 0) { $previousHash = $journal[$journal.Count - 1].Hash }
    $lexicon = Get-LambekLexicon -Language $Fact.Language
    $values = [ordered]@{}
    foreach ($name in $Fact.Parameters.Keys) { $values[$name] = Format-LambekValue -Value $Fact.Parameters[$name] }
    $entry = [ordered]@{
        Told         = $Fact.Told
        Text         = $Fact.Text
        Language     = $Fact.Language
        Form         = $Fact.Form
        Action       = $Fact.Action
        Values       = $values
        What         = $(if ($Fact.PSObject.Properties['What'] -and $Fact.What) { $Fact.What } else { Get-LambekStepSentence -Step ([pscustomobject]@{ Action = $Fact.Action; Parameters = $Fact.Parameters; Output = $null }) -Language $Fact.Language -Units $lexicon.Answer.Units -Unchecked })
        Agent        = $Fact.Agent
        Name         = $Fact.Name
        Wish         = $Fact.Wish
        Time         = $Fact.Time
        Day          = $Fact.Day
        PreviousHash = $previousHash
    }
    $entry.Hash = Get-LambekHash -Text ($entry | ConvertTo-Json -Compress -Depth 4)
    $Fact.Hash = $entry.Hash
    Add-Content -LiteralPath $script:ToldPath -Value ($entry | ConvertTo-Json -Compress -Depth 4) -Encoding utf8
    $journal.Add([pscustomobject] $entry)
}

function Get-LambekToldJournal {
    # What was told in every conversation, oldest first, read once. A line whose hash is not the one of its content,
    # or that does not follow the last line trusted, was changed by hand: it is left out, and the answer says so
    if ($null -ne $script:ToldJournal) { return , $script:ToldJournal }
    $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
    $script:ToldDoubt = 0
    if (-not (Test-Path -LiteralPath $script:ToldPath -PathType Leaf)) { return , $script:ToldJournal }
    $previousHash = ''
    foreach ($line in Get-Content -LiteralPath $script:ToldPath -Encoding utf8) {
        if (-not $line.Trim()) { continue }
        try { $entry = $line | ConvertFrom-Json -AsHashtable } catch { $script:ToldDoubt++; continue }
        $hash = "$($entry['Hash'])"
        $entry.Remove('Hash')
        if ("$($entry['PreviousHash'])" -ne $previousHash -or (Get-LambekHash -Text ($entry | ConvertTo-Json -Compress -Depth 4)) -ne $hash) {
            $script:ToldDoubt++
            continue
        }
        $entry.Hash = $hash
        $previousHash = $hash
        $script:ToldJournal.Add([pscustomobject] $entry)
    }
    return , $script:ToldJournal
}

function Clear-LambekTold {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The user asked for it in words: "forget what I told you".')]
    [CmdletBinding()]
    param()

    # "forget what I told you": the conversation and the journal are emptied. It cannot be undone
    (Get-LambekTold).Clear()
    $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
    $script:ToldDoubt = 0
    if (Test-Path -LiteralPath $script:ToldPath -PathType Leaf) { Remove-Item -LiteralPath $script:ToldPath -Force }
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
    # A thing told in another conversation is said in the words of the day it was told
    if ($Fact.PSObject.Properties['What'] -and $Fact.What) { $what = $Fact.What }
    else { $what = Get-LambekStepSentence -Step ([pscustomobject]@{ Action = $Fact.Action; Parameters = $Fact.Parameters; Output = $null }) -Language $Language -Units $lexicon.Answer.Units -Unchecked }
    $who = $say['Speaker']
    if ($Fact.Agent -ne 'speaker') { $who = $Fact.Name }
    $when = ''
    if ($Fact.Time) { $when = $say['When'] -f $Fact.Time }
    # "yesterday" told another day is said as the day it was
    if ($Fact.PSObject.Properties['PreviousHash'] -and $Fact.Day) { $when = $say['When'] -f $Fact.Day }
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
    if ($Asked.PSObject.Properties['Forget'] -and $Asked.Forget) { return $say['Forgotten'] }
    $told = @((Get-LambekTold).ToArray())
    # What was told before this conversation comes from the journal; what is in both is said once
    $here = @($told | Where-Object { $_.PSObject.Properties['Hash'] -and $_.Hash } | ForEach-Object { $_.Hash })
    $before = @((Get-LambekToldJournal).ToArray() | Where-Object { $_.Hash -notin $here })
    # Lines of the journal changed outside Lambek are never used, and it is said
    $doubt = ''
    if ($script:ToldDoubt -gt 0) { $doubt = "`n$(Format-LambekPlural -Template $say['Doubt'] -Language $Language -Values @([int] $script:ToldDoubt))" }
    # A question about anything: what nobody told is not known, and it is said so
    $anything = -not $Asked.All -and @($Asked.Actions | Where-Object { "$_".StartsWith('verb:') }).Count -gt 0
    if ($told.Count + $before.Count -eq 0) { return "$($say[$(if ($anything) { 'NotKnown' } else { 'NothingTold' })])$doubt" }
    $agrees = {
        param($fact)
        if ($Asked.All) { return $true }
        if ($fact.Action -notin @($Asked.Actions)) { return $false }
        # "what is my name" asks for the other side of "my name is Amin", whichever side it was told on
        if ($Asked.PSObject.Properties['Either'] -and $Asked.Either -and $Asked.Wanted -eq 'agent' -and $Asked.Parameters.Contains('object')) {
            $side = ConvertTo-LambekNormalizedText -Text "$($Asked.Parameters['object'])"
            $other = $null
            if ($fact.PSObject.Properties['Values']) { $other = $fact.Values['object'] } elseif ($fact.Parameters.Contains('object')) { $other = $fact.Parameters['object'] }
            return ((ConvertTo-LambekNormalizedText -Text "$($fact.Name)") -eq $side -or (ConvertTo-LambekNormalizedText -Text "$other") -eq $side)
        }
        if ($Asked.Person -and $fact.Agent -ne $Asked.Person) { return $false }
        # "my sister" asked is "my sister" told: the same words, whatever their capitals and accents
        if ($Asked.PSObject.Properties['Name'] -and $Asked.Name -and (ConvertTo-LambekNormalizedText -Text "$($fact.Name)") -ne (ConvertTo-LambekNormalizedText -Text $Asked.Name)) { return $false }
        # "where...", "what...": the thing told must say it
        if ($Asked.PSObject.Properties['Wanted'] -and $Asked.Wanted) {
            $names = @(if ($fact.PSObject.Properties['Values']) { $fact.Values.Keys } else { $fact.Parameters.Keys })
            if ($Asked.Wanted -eq 'object' -and 'object' -notin $names) { return $false }
            if ($Asked.Wanted -eq 'place' -and @($names | Where-Object { $_ -ne 'object' }).Count -eq 0) { return $false }
        }
        # The same words of time mean the same day only when they were said the same day
        if ($Asked.Time -and (-not $fact.Day -or "$($fact.Day)" -ne "$($Asked.Day)")) { return $false }
        foreach ($name in $Asked.Parameters.Keys) {
            $value = $null
            if ($fact.PSObject.Properties['Values']) { $value = $fact.Values[$name] }
            elseif ($fact.Parameters.Contains($name)) { $value = Format-LambekValue -Value $fact.Parameters[$name] }
            if ((ConvertTo-LambekNormalizedText -Text "$value") -ne (ConvertTo-LambekNormalizedText -Text (Format-LambekValue -Value $Asked.Parameters[$name]))) { return $false }
        }
        return $true
    }
    $found = @($told | Where-Object { & $agrees $_ })
    $older = @($before | Where-Object { & $agrees $_ })
    if ($found.Count + $older.Count -eq 0) { return "$($say[$(if ($anything) { 'NotKnown' } else { 'NotTold' })])$doubt" }
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($found.Count -gt 0) {
        $lines.Add($say['Recalled'])
        foreach ($fact in $found) { $lines.Add("- $(Format-LambekFact -Fact $fact -Language $Language)") }
    }
    if ($older.Count -gt 0) {
        $lines.Add($say['RecalledBefore'])
        foreach ($fact in $older) { $lines.Add("- $($say['OnDay'] -f $fact.Told, (Format-LambekFact -Fact $fact -Language $Language))") }
    }
    return "$($lines -join "`n")$doubt"
}

function Get-LambekSaidTime {
    param([pscustomobject] $Request)

    # When: the longest words of time in the sentence, as the user wrote them
    $dialogue = (Get-LambekLexicon -Language $Request.Language).Dialogue
    $text = " $(@($Request.Tokens) -join ' ') "
    if (-not $dialogue['Times']) { return $null }
    foreach ($phrase in @($dialogue['Times'].Keys) | Sort-Object { -$_.Length }, { $_ }) {
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
    if ($Act.Rule -eq 'forget') { return [pscustomobject]@{ Forget = $true } }
    if ($Act.Rule -eq 'told') { return [pscustomobject]@{ All = $true; Actions = @(); Parameters = [ordered]@{}; Person = $null; Time = $null; Day = $null } }
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
        Day        = Get-LambekSaidDay -Request $Request
    }
}

function ConvertTo-LambekGeneralFact {
    [CmdletBinding()]
    param(
        # The sentence read with the words of the dictionary: who, the verb, what, where
        [Parameter(Mandatory)]
        [pscustomobject] $Reading,

        [Parameter(Mandatory)]
        [pscustomobject] $Request
    )

    # A thing told about anything, in the same shape as a thing told about an action of a pack:
    # the verb stands where the action stood, and what goes with it where the values stood
    $when = Get-LambekSaidTime -Request $Request
    $who = 'agent(speaker)'
    if ($Reading.Agent -ne 'speaker') { $who = "agent(""$($Reading.Name)"")" }
    $roles = @($who) + @(foreach ($key in $Reading.Roles.Keys) { "$key(""$($Reading.Roles[$key])"")" })
    $form = "told($($Reading.Verb)($($roles -join ', '))"
    if ($when) { $form += ", time(""$when"")" }
    [pscustomobject]@{
        Action     = "verb:$($Reading.Verb)"
        Parameters = $Reading.Roles
        What       = $Reading.What
        Agent      = $Reading.Agent
        Name       = $Reading.Name
        Wish       = $false
        Time       = $when
        Day        = Get-LambekSaidDay -Request $Request
        Told       = $null
        Text       = "$($Request.Original)"
        Language   = $Request.Language
        Hash       = $null
        Form       = "$form)"
    }
}

function ConvertTo-LambekGeneralAsked {
    param([pscustomobject] $Reading, [pscustomobject] $Request)

    # A question about anything: what was told with that verb, about that one, and that says what is asked
    [pscustomobject]@{
        All        = $false
        Actions    = @("verb:$($Reading.Verb)")
        Parameters = $Reading.Roles
        Person     = $Reading.Agent
        Name       = $Reading.Name
        Wanted     = $Reading.Asked
        # "what is my name": with "be", the two sides can be told either way round
        Either     = [bool] $Reading.Helper
        Time       = Get-LambekSaidTime -Request $Request
        Day        = Get-LambekSaidDay -Request $Request
    }
}
