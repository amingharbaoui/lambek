#Requires -Version 7.6
<#
.SYNOPSIS
    Writes the proof of an answer as a theorem of Lean, so that Lean, which shares nothing with Lambek, can judge it.
.DESCRIPTION
    Dot-source this file, then call ConvertTo-LambekLean with a name, the facts a proof cites and what the answer
    concludes, in the shape Lambek keeps them (the shapes of tools/Test-LambekProof.ps1). It gives back two theorems
    for Lean 4, with no library:
      Theorem   the premises as hypotheses, the conclusion as the goal: Lean must prove it
      Opposite  the same premises, the opposite of the conclusion as the goal: Lean must not prove it (premises that
                prove both say nothing, since anything follows from them)
    How each fact is written, over things of some type T:
      category(all|chat|animal)        forall x, chat x -> animal x        (a kind of several words: chat x /\ soeur x)
      category(no|poisson|mammifere)   forall x, poisson x -> not mammifere x
      category(is|name:tom|chat)       chat tom          ("isnot": not chat tom)
      category(usual:all|oiseau|v:voler)
                                       forall x, oiseau x -> not ab x -> voler x, with ab the exceptions to that rule:
                                       what holds normalement is concluded of one only under the stated assumption
                                       that it is no exception ("usual:is"/"usual:isnot" in a conclusion); a rule about
                                       a narrower kind that says otherwise makes it one (forall x, pingouin x -> ab x),
                                       and two such rules about kinds neither narrower make each other's members one
      if(cond(X), then(Y))|            X -> Y, each thing told a proposition of its own
      X|                               X
    "some" and "not every" are not written: $null comes back, with the reason.
.EXAMPLE
    . ./tools/ConvertTo-LambekLean.ps1
    (ConvertTo-LambekLean -Name 'socrate' -Premises 'category(all|homme|mortel)|', 'category(is|name:socrate|homme)|' -Conclusions 'category(is|name:socrate|mortel)').Theorem
#>

function ConvertTo-LambekLean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Premises,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Conclusions
    )

    $none = { param($reason) [pscustomobject]@{ Theorem = $null; Opposite = $null; Reason = $reason } }
    if ($Conclusions.Count -eq 0) { return & $none 'no conclusion' }

    # Each fact read again here, with nothing shared with the engine or the other checker
    $read = {
        param([string] $text)
        $text = $text.Trim() -replace '\|[^()]*$', ''
        $match = [regex]::Match($text, '^category\((?<kind>[^|()]*)\|(?<who>[^|()]*)\|(?<what>[^|()]*)\)$')
        if ($match.Success) {
            $kind = $match.Groups['kind'].Value
            $usual = $kind.StartsWith('usual:')
            if ($usual) { $kind = $kind.Substring(6) }
            return [pscustomobject]@{
                Shape = 'category'; Kind = $kind; Usual = $usual; Who = $match.Groups['who'].Value
                Subject = [string[]] @($match.Groups['who'].Value -split '\+' | Where-Object { $_ })
                Atoms = [string[]] @($match.Groups['what'].Value -split '\+' | Where-Object { $_ })
            }
        }
        if ($text.StartsWith('if(cond(')) {
            $depth = 0; $end = -1
            for ($i = 'if(cond'.Length; $i -lt $text.Length; $i++) {
                if ($text[$i] -eq '(') { $depth++ } elseif ($text[$i] -eq ')') { $depth--; if ($depth -eq 0) { $end = $i; break } }
            }
            $rest = $(if ($end -ge 0) { [regex]::Match($text.Substring($end + 1), '^\s*,\s*then\((?<then>.*)\)\)$') })
            if (-not $rest -or -not $rest.Success) { return $null }
            return [pscustomobject]@{ Shape = 'if'; If = $text.Substring('if(cond('.Length, $end - 'if(cond('.Length).Trim(); Then = $rest.Groups['then'].Value.Trim() }
        }
        if ($text) { return [pscustomobject]@{ Shape = 'told'; Key = $text } }
        return $null
    }

    $facts = @(foreach ($premise in $Premises) { & $read $premise })
    if (@($facts | Where-Object { -not $_ }).Count -gt 0) { return & $none 'a premise has no shape this reads' }
    $goals = @(foreach ($conclusion in $Conclusions) { & $read $conclusion })
    if (@($goals | Where-Object { -not $_ }).Count -gt 0) { return & $none 'a conclusion has no shape this reads' }
    foreach ($fact in @($facts + $goals)) {
        if ($fact.Shape -eq 'category' -and $fact.Kind -notin 'all', 'no', 'is', 'isnot') { return & $none "not written: $($fact.Kind)" }
        if ($fact.Shape -eq 'if' -and -not $fact.If) { return & $none 'a rule with no condition' }
    }

    # Each thing, kind, exception and proposition gets a plain name of its own (c0, k0, ab0, p0); what it stands for
    # is said in a comment above the theorem
    $named = [ordered]@{}
    $id = {
        param([string] $prefix, [string] $text)
        $key = "$prefix|$text"
        if (-not $named.Contains($key)) { $named[$key] = "$prefix$(@($named.Keys | Where-Object { $_.StartsWith("$prefix|") }).Count)" }
        $named[$key]
    }
    $kind = { param($atom) & $id 'k' $atom }
    $one = { param($who) & $id 'c' $who }
    $prop = { param($key) & $id 'p' $key }
    $all = { param([string[]] $atoms, [string] $x) (@($atoms | ForEach-Object { "$(& $kind $_) $x" }) -join ' /\ ') }

    $categories = @($facts | Where-Object Shape -EQ 'category')
    $usual = @($categories | Where-Object { $_.Usual -and $_.Kind -in 'all', 'no' })
    $strict = @($categories | Where-Object { -not $_.Usual -and $_.Kind -in 'all', 'no' })
    $exception = @{}
    for ($i = 0; $i -lt $usual.Count; $i++) { $exception[$usual[$i]] = & $id 'ab' "$i" }

    # The kinds one of a kind is in, by the strict rules: which of two rules is about a narrower kind
    $closure = {
        param([string[]] $subject)
        $is = [System.Collections.Generic.HashSet[string]]::new($subject)
        do {
            $more = $false
            foreach ($rule in @($strict | Where-Object Kind -EQ 'all')) {
                if (@($rule.Subject | Where-Object { -not $is.Contains($_) }).Count -eq 0) { foreach ($atom in $rule.Atoms) { if ($is.Add($atom)) { $more = $true } } }
            }
        } while ($more)
        $is
    }
    $within = { param($narrow, $wide) $in = & $closure $narrow.Subject; @($wide.Subject | Where-Object { -not $in.Contains($_) }).Count -eq 0 }

    $hypotheses = [System.Collections.Generic.List[string]]::new()
    foreach ($fact in $facts) {
        switch ($fact.Shape) {
            'told' { $hypotheses.Add((& $prop $fact.Key)) }
            'if' { $hypotheses.Add("$(& $prop $fact.If) -> $(& $prop $fact.Then)") }
            'category' {
                $says = $(if ($fact.Kind -in 'all', 'is') { & $all $fact.Atoms 'x' } else { "Not ($(& $all $fact.Atoms 'x'))" })
                switch ($fact.Kind) {
                    { $_ -in 'all', 'no' } {
                        $unless = $(if ($fact.Usual) { "Not ($($exception[$fact]) x) -> " } else { '' })
                        $hypotheses.Add("forall x, $(& $all $fact.Subject 'x') -> $unless$says")
                    }
                    { $_ -in 'is', 'isnot' } { $hypotheses.Add(($says -replace '\bx\b', (& $one $fact.Who))) }
                }
            }
        }
    }
    # Exceptions: a rule about a narrower kind that says otherwise wins; two about kinds neither narrower block each other
    foreach ($rule in $usual) {
        foreach ($other in $usual) {
            if ($other -eq $rule -or $other.Kind -eq $rule.Kind -or ($other.Atoms -join '+') -ne ($rule.Atoms -join '+')) { continue }
            $narrower = (& $within $other $rule) -and -not (& $within $rule $other)
            $wider = (& $within $rule $other) -and -not (& $within $other $rule)
            if ($narrower) { $hypotheses.Add("forall x, $(& $all $other.Subject 'x') -> $($exception[$rule]) x") }
            elseif (-not $wider) { $hypotheses.Add("forall x, $(& $all $other.Subject 'x') /\ $(& $all $rule.Subject 'x') -> $($exception[$rule]) x") }
        }
    }

    # The goal, and what it assumes: one supposed is no exception to the rules that say what is concluded of it
    $wanted = [System.Collections.Generic.List[string]]::new()
    $opposite = [System.Collections.Generic.List[string]]::new()
    $assumed = [System.Collections.Generic.List[string]]::new()
    foreach ($goal in $goals) {
        if ($goal.Shape -eq 'told') { $wanted.Add((& $prop $goal.Key)); $opposite.Add("Not $(& $prop $goal.Key)"); continue }
        if ($goal.Shape -ne 'category') { return & $none 'a conclusion that is a rule' }
        $x = $(if ($goal.Kind -in 'is', 'isnot') { & $one $goal.Who } else { 'x' })
        $positive = & $all $goal.Atoms $x
        $says = $(if ($goal.Kind -in 'all', 'is') { $positive } else { "Not ($positive)" })
        $against = $(if ($goal.Kind -in 'all', 'is') { "Not ($positive)" } else { $positive })
        if ($goal.Kind -in 'all', 'no') {
            if ($goal.Usual) { return & $none 'a rule supposed as a conclusion' }
            $wanted.Add("forall x, $(& $all $goal.Subject 'x') -> $says")
            # (the opposite of a rule: some one of the kind is not so; T may be empty, so it is said of a new one)
            $opposite.Add("exists x, $(& $all $goal.Subject 'x') /\ $against")
            continue
        }
        $wanted.Add($says); $opposite.Add($against)
        if ($goal.Usual) {
            $direction = $(if ($goal.Kind -eq 'is') { 'all' } else { 'no' })
            foreach ($rule in @($usual | Where-Object { $_.Kind -eq $direction -and ($_.Atoms -join '+') -eq ($goal.Atoms -join '+') })) {
                $assumed.Add("Not ($($exception[$rule]) $x)")
            }
        }
    }

    # The things, kinds, exceptions and propositions named, each given its type
    $of = { param([string] $prefix) @($named.Keys | Where-Object { $_.StartsWith("$prefix|") } | ForEach-Object { $named[$_] }) }
    $binders = [System.Collections.Generic.List[string]]::new()
    $binders.Add('(T : Type)')
    $ones = & $of 'c'; if ($ones) { $binders.Add("($($ones -join ' ') : T)") }
    $kinds = @((& $of 'k') + (& $of 'ab')); if ($kinds) { $binders.Add("($($kinds -join ' ') : T -> Prop)") }
    $props = & $of 'p'; if ($props) { $binders.Add("($($props -join ' ') : Prop)") }
    $given = @($hypotheses + $assumed)
    for ($i = 0; $i -lt $given.Count; $i++) { $binders.Add("(h$i : $($given[$i]))") }

    $legend = @($named.Keys | Where-Object { -not $_.StartsWith('ab|') } | ForEach-Object { "-- $($named[$_]): $(($_ -split '\|', 2)[1] -replace '[\r\n]', ' ')" })
    $statement = {
        param([string] $label, [string[]] $goal)
        (@($legend) + "theorem $label $($binders -join ' ') :" + "    $(($goal | ForEach-Object { "($_)" }) -join ' /\ ') := by" + '  grind') -join "`n"
    }
    $safe = $Name -replace '[^A-Za-z0-9_]', '_'
    [pscustomobject]@{
        Theorem  = & $statement "proof_$safe" ([string[]] $wanted)
        Opposite = & $statement "opposite_$safe" ([string[]] @(if ($opposite.Count -eq 1) { $opposite[0] } else { 'Not (' + (@($wanted | ForEach-Object { "($_)" }) -join ' /\ ') + ')' }))
        Reason   = ''
    }
}
