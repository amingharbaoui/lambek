function Get-LambekCoreTermOf {
    param([string] $Core)

    # What a key says, without the day it is about: "pleuvoir(agent("il"))|2026-10-06" is "pleuvoir(agent("il"))"
    $bar = $Core.LastIndexOf('|')
    if ($bar -lt 0) { return $Core }
    return $Core.Substring(0, $bar)
}

function Get-LambekCoreDayOf {
    param([string] $Core)

    $bar = $Core.LastIndexOf('|')
    if ($bar -lt 0) { return '' }
    return $Core.Substring($bar + 1)
}

function Set-LambekCondition {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes an object in memory only.')]
    [CmdletBinding()]
    param(
        # What holds when the condition does: "je prends le bus"
        [Parameter(Mandatory)]
        [pscustomobject] $Statement,

        # The condition: "il pleut"
        [Parameter(Mandatory)]
        [pscustomobject] $Condition
    )

    # "s'il pleut, je prends le bus" is one thing told: a rule. It keeps what it says when it holds (Then), and its key
    # is the condition and that together: if(cond(...), then(...)). It is never a thing told on its own
    $key = { param($fact) if ($fact.PSObject.Properties['Core'] -and $fact.Core) { "$($fact.Core)" } else { "$($fact.Form)|" } }
    $then = & $key $Statement
    $if = Get-LambekCoreTermOf -Core (& $key $Condition)
    if ($Condition.PSObject.Properties['Negated'] -and $Condition.Negated) { $if = "not($if)" }
    $Statement | Add-Member -NotePropertyName Condition -NotePropertyValue $Condition -Force
    $Statement | Add-Member -NotePropertyName Then -NotePropertyValue $then -Force
    $Statement | Add-Member -NotePropertyName ThenForm -NotePropertyValue "$($Statement.Form)" -Force
    $Statement | Add-Member -NotePropertyName Core -NotePropertyValue "if(cond($if), then($(Get-LambekCoreTermOf -Core $then)))|$(Get-LambekCoreDayOf -Core $then)" -Force
    $Statement.Form = "if($($Condition.Form), $($Statement.Form))"
}

function Test-LambekHold {
    param([pscustomobject] $Fact, [pscustomobject] $Condition)

    # A thing held says what the condition says: the same verb, the same one, the same complements in any order,
    # the same sign; and the same day when the condition names one
    if ($Fact.PSObject.Properties['Condition'] -and $Fact.Condition) { return $false }
    if (-not $Fact.PSObject.Properties['Core'] -or -not $Fact.Core -or -not $Condition.PSObject.Properties['Core'] -or -not $Condition.Core) { return $false }
    if ([bool] ($Fact.PSObject.Properties['Negated'] -and $Fact.Negated) -ne [bool] ($Condition.PSObject.Properties['Negated'] -and $Condition.Negated)) { return $false }
    $plain = { param($core) ConvertTo-LambekNormalizedText -Text ([LambekBoard]::Canonical((Get-LambekCoreTermOf -Core "$core"))) }
    if ((& $plain $Fact.Core) -cne (& $plain $Condition.Core)) { return $false }
    $day = Get-LambekCoreDayOf -Core "$($Condition.Core)"
    return (-not $day -or $day -eq (Get-LambekCoreDayOf -Core "$($Fact.Core)"))
}

function Get-LambekDeduced {
    [CmdletBinding()]
    param(
        # Everything held: things told, and rules told ("s'il pleut, je prends le bus")
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Facts
    )

    # What follows from what was told, by the rules told: a rule whose condition is held gives what it says, deduced,
    # resting on the rule and on the thing that made it hold (modus ponens, again and again until nothing new comes).
    # Everything deduced goes on the blackboard as deduced, with what it rests on; nothing deduced is ever told
    $rules = @($Facts | Where-Object { $_.PSObject.Properties['Condition'] -and $_.Condition })
    if ($rules.Count -eq 0) { return @($Facts) }
    $board = Get-LambekBoard
    $board.Drop('logic')
    $known = [System.Collections.Generic.List[object]]::new()
    foreach ($fact in $Facts) { if (-not ($fact.PSObject.Properties['Condition'] -and $fact.Condition)) { $known.Add($fact) } }
    $made = [System.Collections.Generic.HashSet[string]]::new()
    $hash = { param($item) [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($item) }
    for ($round = 0; $round -lt 8; $round++) {
        $more = $false
        foreach ($rule in $rules) {
            foreach ($fact in @($known.ToArray())) {
                $entry = $board.Entry($fact)
                if ($entry -and $entry.Status -eq 'imagined') { continue }
                if (-not (Test-LambekHold -Fact $fact -Condition $rule.Condition)) { continue }
                if (-not $made.Add("$(& $hash $rule)|$(& $hash $fact)")) { continue }
                # The same thing deduced in another way is kept once
                if (@($known | Where-Object { $_.PSObject.Properties['Core'] -and "$($_.Core)" -ceq "$($rule.Then)" -and [bool] ($_.PSObject.Properties['Negated'] -and $_.Negated) -eq [bool] ($rule.PSObject.Properties['Negated'] -and $rule.Negated) }).Count -gt 0) { continue }
                $deduced = $rule.PSObject.Copy()
                foreach ($name in 'Condition', 'Then', 'ThenForm', 'Hash', 'PreviousHash', 'ReasonFor') { $deduced.PSObject.Properties.Remove($name) }
                $deduced | Add-Member -NotePropertyName Core -NotePropertyValue "$($rule.Then)" -Force
                $deduced | Add-Member -NotePropertyName Form -NotePropertyValue "$($rule.ThenForm)" -Force
                $deduced | Add-Member -NotePropertyName Deduced -NotePropertyValue $true -Force
                $deduced | Add-Member -NotePropertyName Basis -NotePropertyValue @($rule, $fact) -Force
                $ids = [int[]] @(@($rule, $fact) | ForEach-Object { $board.Entry($_) } | Where-Object { $_ } | ForEach-Object { $_.Id })
                $day = $null
                if ($deduced.PSObject.Properties['Told'] -and $deduced.Told) { $day = "$($deduced.Told)" }
                [void] $board.Put($deduced, 'deduced', 'logic', $day, "$($deduced.Core)", [bool] ($deduced.PSObject.Properties['Negated'] -and $deduced.Negated), $null, "$($deduced.Form)", $ids)
                $known.Add($deduced)
                $more = $true
            }
        }
        if (-not $more) { break }
    }
    return @(@($rules) + @($known))
}

function Get-LambekProofLeaf {
    param([pscustomobject] $Fact)

    # What a thing deduced rests on in the end: the things and rules told, each once
    $leaves = [System.Collections.Generic.List[object]]::new()
    $walk = {
        param($item)
        if ($item.PSObject.Properties['Deduced'] -and $item.Deduced) { foreach ($basis in @($item.Basis)) { & $walk $basis } }
        elseif (-not $leaves.Contains($item)) { $leaves.Add($item) }
    }
    & $walk $Fact
    # (said in the order they were told)
    $board = Get-LambekBoard
    return @($leaves.ToArray() | Sort-Object -Stable { $entry = $board.Entry($_); if ($entry) { $entry.Id } else { [int]::MaxValue } })
}

function Get-LambekLastProof {
    # What the last answer of this conversation rested on, for "pourquoi ?" (each chat has its own conversation)
    if ($null -eq $script:LastProofs) { $script:LastProofs = [System.Collections.Generic.Dictionary[object, object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance) }
    $here = Get-LambekTold
    if ($script:LastProofs.ContainsKey($here)) { return $script:LastProofs[$here] }
    return $null
}

function Set-LambekLastProof {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Keeps a value in memory only.')]
    # (Read: what was read, not told, with where it was read and the day: a fact of Wikidata)
    param([object[]] $Facts = @(), [string] $Calculation = '', [string[]] $Said = @(), [object[]] $Read = @())

    if ($null -eq $script:LastProofs) { $script:LastProofs = [System.Collections.Generic.Dictionary[object, object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance) }
    $here = Get-LambekTold
    if (@($Facts).Count -eq 0 -and @($Said).Count -eq 0 -and @($Read).Count -eq 0) { [void] $script:LastProofs.Remove($here); return }
    $script:LastProofs[$here] = [pscustomobject]@{ Facts = @($Facts); Calculation = $Calculation; Said = @($Said); Read = @($Read) }
}

function Format-LambekInline {
    param([string] $Text, [string] $Language)

    # A sentence said inside another one: without its full stop, and without its capital when it starts with a small word
    # ("Il pleut." in "s'il pleut, ..."); a name keeps its capital
    $Text = "$Text".Trim().TrimEnd('.')
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $small = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($key in 'Speakers', 'Addressee', 'Pronouns', 'Determiners', 'Owners') { foreach ($word in @($general[$key])) { if ($word) { [void] $small.Add("$word") } } }
    if ($general['OtherSide']) {
        foreach ($word in @($general['OtherSide']['Second'])) { if ($word) { [void] $small.Add("$word") } }
        foreach ($word in @($general['OtherSide']['Words'].Values)) { if ($word) { [void] $small.Add("$word") } }
    }
    [void] $small.Remove('i')
    $first = [regex]::Match($Text, '^[\p{L}]+')
    if ($first.Success -and $small.Contains((ConvertTo-LambekNormalizedText -Text $first.Value))) { $Text = $Text.Substring(0, 1).ToLowerInvariant() + $Text.Substring(1) }
    return $Text
}

function Get-LambekOnlyIf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Asked,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Facts,

        [Parameter(Mandatory)]
        [string] $Language,

        [string] $Register = 'vous'
    )

    # Nothing held answers the question, but a rule told would if its condition held: "s'il pleut, je prends le bus"
    # answers "est-ce que je prends le bus ?" only if it rains. It is said so, with the rule, and what was not told
    $rules = @($Facts | Where-Object { $_.PSObject.Properties['Condition'] -and $_.Condition })
    if ($rules.Count -eq 0) { return $null }
    $held = @($Facts | Where-Object { -not ($_.PSObject.Properties['Condition'] -and $_.Condition) })
    $supposed = foreach ($rule in $rules) {
        $then = $rule.PSObject.Copy()
        foreach ($name in 'Condition', 'Then', 'ThenForm', 'Hash', 'PreviousHash', 'ReasonFor') { $then.PSObject.Properties.Remove($name) }
        $then | Add-Member -NotePropertyName Core -NotePropertyValue "$($rule.Then)" -Force
        $then | Add-Member -NotePropertyName Form -NotePropertyValue "$($rule.ThenForm)" -Force
        $then | Add-Member -NotePropertyName Deduced -NotePropertyValue $true -Force
        $then | Add-Member -NotePropertyName Basis -NotePropertyValue @($rule) -Force
        $then | Add-Member -NotePropertyName Supposed -NotePropertyValue $true -Force
        $then
    }
    $supposed = @($supposed)
    $answers = @(Find-LambekTold -Asked $Asked -Facts (@($held) + $supposed) | Where-Object { $supposed -contains $_.Fact })
    if ($answers.Count -eq 0) { return $null }
    $lexicon = Get-LambekLexicon -Language $Language
    $say = $lexicon.Dialogue.Say
    $general = $lexicon.Dialogue['General']
    $lines = [System.Collections.Generic.List[string]]::new()
    $used = [System.Collections.Generic.List[object]]::new()
    foreach ($answer in $answers) {
        $rule = @($answer.Fact.Basis)[0]
        if ($used.Contains($rule)) { continue }
        $used.Add($rule)
        $if = Get-LambekFactSentence -Fact $rule.Condition -Register $Register
        $then = Get-LambekFactSentence -Fact $rule -Register $Register
        if ($if) { $if = Format-LambekInline -Text $if -Language $Language } else { $if = $say['Quote'] -f "$($rule.Condition.Text)".Trim() }
        # (a rule that cannot be said back is quoted as it was told)
        if ($if -and $then -and $say['OnlyIf']) { $line = $say['OnlyIf'] -f (Format-LambekFact -Fact $rule -Language $Language -Register $Register), $if }
        else { $line = $say['OnlyIfQuoted'] -f ($say['IfThen'] -f "$($rule.Condition.Text)".Trim(), "$($rule.Text)".Trim()), $if }
        if ($general -and $general['Elide']) { foreach ($pair in $general['Elide'].GetEnumerator()) { $line = [regex]::Replace($line, "(?<!\p{L})$([regex]::Escape($pair.Key))(?!\p{L})", $pair.Value) } }
        $lines.Add($line)
    }
    Set-LambekLastProof -Facts $used.ToArray()
    return ($lines -join "`n")
}
