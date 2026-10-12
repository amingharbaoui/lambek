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
        # Said again: it is the most recent thing said once more (who "she" is depends on it), and written once
        $again = @($told | Where-Object { $_.Form -ceq $step.Statement.Form })
        if ($again.Count -gt 0) { [void] $told.Remove($again[0]); $told.Add($again[0]); continue }
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
        Said         = $(if ($Fact.PSObject.Properties['Said']) { $Fact.Said } else { $null })
        Negated      = $(if ($Fact.PSObject.Properties['Negated']) { [bool] $Fact.Negated } else { $false })
        Core         = $(if ($Fact.PSObject.Properties['Core']) { $Fact.Core } else { $Fact.Form })
        ReasonFor    = $(if ($Fact.PSObject.Properties['ReasonFor']) { $Fact.ReasonFor } else { $null })
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
        [string] $Language,

        [string] $Register = 'vous'
    )

    # One thing told, said back. First as a sentence, the user's own turned to the other side ("you bought a car"),
    # kept only when reading it again gives the same thing told; otherwise in the user's own words, quoted:
    # what Lambek cannot say right is never said in a form ("Who: ... What: ..."), nor guessed
    $lexicon = Get-LambekLexicon -Language $Language
    $say = $lexicon.Dialogue.Say
    if ($Fact.PSObject.Properties['Text'] -and $Fact.Text -and $Fact.Language) {
        $words = "$($Fact.Text)"
        if ($Fact.PSObject.Properties['Said'] -and $Fact.Said) { $words = "$($Fact.Said)" }
        $sentence = ConvertTo-LambekOtherSide -Text $words -Language $Fact.Language -Register $Register
        if ($sentence -and (Test-LambekSaidBack -Fact $Fact -Sentence $sentence)) {
            # "yesterday" told another day is said with the day it was
            if ($Fact.PSObject.Properties['PreviousHash'] -and $Fact.Time -and $Fact.Day) { $sentence += " ($($Fact.Day))" }
            return $sentence
        }
        return $say['Quoted'] -f "$($Fact.Text)".Trim()
    }
    # Without the words it was told in (a line of an older journal): what it was about, then what
    if ($Fact.PSObject.Properties['What'] -and $Fact.What) { $what = $Fact.What }
    else { $what = Get-LambekStepSentence -Step ([pscustomobject]@{ Action = $Fact.Action; Parameters = $Fact.Parameters; Output = $null }) -Language $Language -Units $lexicon.Answer.Units -Unchecked }
    # (in the middle of a sentence: "about you: delete the files...", not "Delete the files....")
    $what = "$what".Trim().TrimEnd('.')
    if ($what -cmatch '^\p{Lu}\p{Ll}') { $what = $what.Substring(0, 1).ToLowerInvariant() + $what.Substring(1) }
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
        [string] $Language,

        [string] $Register = 'vous'
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
    # The question is a rule of the logic, and everything told its facts: the answers are what the logic proves
    $all = @($told) + @($before)
    $proved = @(Find-LambekTold -Asked $Asked -Facts $all)
    $found = @($proved | Where-Object { $told -contains $_.Fact })
    $older = @($proved | Where-Object { $told -notcontains $_.Fact })
    if ($found.Count + $older.Count -eq 0) { return "$($say[$(if ($anything) { 'NotKnown' } else { 'NotTold' })])$doubt" }
    $lines = [System.Collections.Generic.List[string]]::new()
    # Answers that say the opposite of each other: both are kept and it is said first
    $answered = @($proved | ForEach-Object { $_.Fact })
    $disagree = @($proved | Where-Object { @(Get-LambekContrary -Fact $_.Fact -Facts $answered).Count -gt 0 }).Count -gt 0
    if ($disagree) { $lines.Add($say['Contradicted']) }
    if ($found.Count -gt 0) {
        if (-not $disagree) { $lines.Add($say['Recalled']) }
        foreach ($answer in $found) {
            $lines.Add("- $(Format-LambekFact -Fact $answer.Fact -Language $Language -Register $Register)")
            # "why...": the reasons told with it, or that none was
            if ($Asked.PSObject.Properties['Wanted'] -and $Asked.Wanted -eq 'reason') {
                $reasons = @(Get-LambekReason -Fact $answer.Fact -Facts $all)
                foreach ($reason in $reasons) { $lines.Add("  $($say['BecauseOf'] -f (Format-LambekFact -Fact $reason -Language $Language -Register $Register))") }
                if ($reasons.Count -eq 0) { $lines.Add("  $($say['NoReason'])") }
            }
            foreach ($other in @(Get-LambekContrary -Fact $answer.Fact -Facts $all | Where-Object { $answered -notcontains $_ })) { $lines.Add("  $($say['ButAlso'] -f (Format-LambekFact -Fact $other -Language $Language -Register $Register))") }
            # What it was deduced with is said: the answer can be checked
            foreach ($reason in $answer.Because) { $lines.Add("  $($say['Because'] -f (Format-LambekFact -Fact $reason -Language $Language -Register $Register))") }
        }
    }
    if ($older.Count -gt 0) {
        $lines.Add($say['RecalledBefore'])
        foreach ($answer in $older) {
            $lines.Add("- $($say['OnDay'] -f $answer.Fact.Told, (Format-LambekFact -Fact $answer.Fact -Language $Language -Register $Register))")
            if ($Asked.PSObject.Properties['Wanted'] -and $Asked.Wanted -eq 'reason') {
                $reasons = @(Get-LambekReason -Fact $answer.Fact -Facts $all)
                foreach ($reason in $reasons) { $lines.Add("  $($say['BecauseOf'] -f (Format-LambekFact -Fact $reason -Language $Language -Register $Register))") }
                if ($reasons.Count -eq 0) { $lines.Add("  $($say['NoReason'])") }
            }
            foreach ($other in @(Get-LambekContrary -Fact $answer.Fact -Facts $all | Where-Object { $answered -notcontains $_ })) { $lines.Add("  $($say['ButAlso'] -f (Format-LambekFact -Fact $other -Language $Language -Register $Register))") }
            foreach ($reason in $answer.Because) { $lines.Add("  $($say['Because'] -f (Format-LambekFact -Fact $reason -Language $Language -Register $Register))") }
        }
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
    # A number as it was written ("two brothers", not "_number_ brothers"): the words of number one after the other;
    # with several numbers in the sentence, the value read
    $numbers = @()
    $known = $null
    if ($Request.PSObject.Properties['Language'] -and $Request.Language) { $known = (Get-LambekLexicon -Language $Request.Language).Numbers }
    $span = @()
    foreach ($match in @([regex]::Matches("$($Request.Original)", '[\p{L}\p{N}]+')) + @($null)) {
        $plain = if ($match) { ConvertTo-LambekNormalizedText -Text $match.Value } else { '' }
        if ($plain -match '^\d+$' -or ($known -and $plain -and $known.Contains($plain))) { $span += $match.Value; continue }
        if ($span.Count -gt 0) { $numbers += ($span -join ' '); $span = @() }
    }
    $values = @($Request.Entities | Where-Object { $_.Type -eq 'number' } | ForEach-Object { "$($_.Raw)" })
    $said = @(foreach ($word in $Words) {
            if ($word -eq '_number_') { if ($numbers.Count -eq 1) { $numbers[0] } elseif ($values.Count -gt 0) { $values[0] } else { $word } }
            elseif ($written.ContainsKey($word)) { $written[$word] }
            else { $word }
        })
    return ($said -join ' ')
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
    # What is said, with or without "not": two things told are contrary when only that differs, about the same day
    $inner = "$($Reading.Verb)($($roles -join ', '))"
    $day = Get-LambekSaidDay -Request $Request
    $negated = [bool] ($Reading.PSObject.Properties['Negated'] -and $Reading.Negated)
    $form = "told($inner"
    if ($negated) { $form = "told(not($inner)" }
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
        # The words said with the pronoun replaced by the one it stands for ("elle travaille" is "ma soeur travaille")
        Said       = $(if ($Reading.PSObject.Properties['Resolved'] -and $Reading.Resolved) { Get-LambekSaidFor -Text "$($Request.Original)" -Resolved $Reading.Resolved } else { $null })
        Language   = $Request.Language
        Hash       = $null
        Negated    = $negated
        Core       = "$inner|$day"
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

function Get-LambekSaidFor {
    param([string] $Text, [pscustomobject] $Resolved)

    # The sentence with the pronoun in the place of the one it stands for: the first time it is said, as it was written
    $pattern = '(?i)(?<![\p{L}])' + [regex]::Escape($Resolved.Pronoun) + '(?![\p{L}])'
    return ([regex] $pattern).Replace($Text, $Resolved.Antecedent.Replace('$', '$$'), 1)
}

function Get-LambekContrary {
    param([pscustomobject] $Fact, [object[]] $Facts)

    # The things told that say the opposite: the same verb, the same one, the same complements, the same day,
    # but one says "not". Both are kept, and both are said (four-valued logic of Belnap: a contradiction stays local)
    if (-not $Fact.PSObject.Properties['Core'] -or -not $Fact.Core) { return @() }
    $mine = [bool] ($Fact.PSObject.Properties['Negated'] -and $Fact.Negated)
    # (a thing of this conversation is also in the journal: it is said once)
    $seen = @{}
    return @($Facts | Where-Object { $key = "$($_.Form)|$($_.Told)"; -not $seen.ContainsKey($key) -and ($seen[$key] = $true) } | Where-Object {
            -not [object]::ReferenceEquals($_, $Fact) -and $_.PSObject.Properties['Core'] -and $_.Core -ceq $Fact.Core -and
            ([bool] ($_.PSObject.Properties['Negated'] -and $_.Negated)) -ne $mine
        })
}

function Get-LambekReason {
    param([pscustomobject] $Fact, [object[]] $Facts)

    # The things told as the reason of this one ("...because she works in Lyon"), once each
    if (-not $Fact.PSObject.Properties['Core'] -or -not $Fact.Core) { return @() }
    $seen = @{}
    return @($Facts | Where-Object { $_.PSObject.Properties['ReasonFor'] -and $_.ReasonFor -ceq $Fact.Core } | Where-Object { $key = "$($_.Form)"; -not $seen.ContainsKey($key) -and ($seen[$key] = $true) })
}
