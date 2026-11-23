#Requires -Version 7.6
<#
.SYNOPSIS
    A checker of proofs that shares no code with Lambek: from the facts a proof cites, in the shape Lambek keeps them,
    it works out again whether what the answer says follows, with a handful of rules written here and nothing else.
.DESCRIPTION
    The module loads this file on its own and calls it before an answer is said; it calls nothing of the engine, so a
    fault in the engine's reasoning is not repeated here. Dot-source it to use it alone (the benches and its tests do).
    Call Test-LambekProof with the facts a proof cites and what the answer concludes.
    It knows three kinds of facts:
      category(all|chat|animal)        every cat is an animal ("no", and "usual:all"/"usual:no" for what holds
      category(no|poisson|mammifere)   "normalement"); a kind of several words is written chat+soeur
      category(is|name:tom|chat)       Tom is a cat ("isnot": Tom is not; "does"/"doesnot" for a verb, v:voler)
      compare(more|grand|name:rex|name:max)  Rex is more grand than Max ("notmore" in a conclusion: is not); of what
                                             is done, compare(more|time:before:arriver|...): Rex arrived before Max
      date(time:arriver|name:rex|2026-10-18) Rex arrived on that day
      if(cond(X), then(Y))|            a rule told with if: when X was told, Y follows
      category(if|is~name:rex~chien|does~name:rex~v:aboyer)  if Rex is a dog, Rex barks (of one named, or two)
      category(or|is~name:rex~chien|is~name:max~chat)        Rex is a dog or Max is a cat
      category(believe|name:alice|is~name:tom~chat)          Alice believes that Tom is a cat
      X|                               a thing told, as it is held (what follows the last bar is its day)
    and what an answer may conclude: one of those facts, or "usual:is"/"usual:isnot" about someone, for what is only
    supposed. The rules it uses:
      - one is every kind its kinds are in (Tom is a cat, every cat is an animal: Tom is an animal)
      - one is not what no one of its kinds is (Nemo is a fish, no fish is a mammal: Nemo is not a mammal)
      - one is not of a kind when being of it too would make it what it is not (every cat is black, I am not black: I
        am not a cat)
      - every one of a kind is what a wider kind is (every cat is a mammal, every mammal is an animal)
      - what holds normalement is supposed of one when nothing told and no rule about a narrower kind says otherwise
      - modus ponens on the rules told with if; on those about named ones, modus tollens too (Rex does not bark: Rex
        is not a dog)
      - what one believes follows from what that one believes alone, by the same rules
      - what is more than one that is more than a third is more than the third, and what is more than another is not
        less than it (no one is more than itself); one done on an earlier day than another is done before it, and
        the other after it
      - one more so than one that is so is so; one less so than one that is not so is not (more grand than one grand)
      - at least so many of a kind being something are at least as many of a wider kind being something wider; at
        most so many, at most as many of a narrower kind being something narrower (count(least|3|chat|noir))
      - what holds in each of several kinds one is one of holds ("or:chat;chien": Rex is a dog or a cat, Rex is not a
        cat: Rex is a dog; every dog and every cat is an animal: Rex is an animal)
      - what holds in each of two things told with or holds; a case that cannot be with the rest is no case (Rex is a
        dog or Max is a cat, Rex is not a dog: Max is a cat)
    A conclusion it cannot work out is refused; "some" and "not every" are not checked (it says so).
    Test-LambekCalculation works out again a sum an answer shows ("2 + 3 = 5").
.EXAMPLE
    . ./engine/Lambek/Checker/Test-LambekProof.ps1
    Test-LambekProof -Premises 'category(all|homme|mortel)', 'category(is|name:socrate|homme)' -Conclusions 'category(is|name:socrate|mortel)'
#>

function Test-LambekProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Premises,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Conclusions,

        # Also say, for each premise, whether the conclusions still follow without it
        [switch] $Each
    )

    $verdict = Test-LambekProofOnce -Premises $Premises -Conclusions $Conclusions
    $unneeded = [System.Collections.Generic.List[string]]::new()
    if ($Each -and $verdict.Holds -eq $true) {
        for ($i = 0; $i -lt $Premises.Count; $i++) {
            $rest = @(for ($j = 0; $j -lt $Premises.Count; $j++) { if ($j -ne $i) { $Premises[$j] } })
            if ((Test-LambekProofOnce -Premises $rest -Conclusions $Conclusions).Holds -eq $true) { $unneeded.Add($Premises[$i]) }
        }
    }
    [pscustomobject]@{ Holds = $verdict.Holds; Reason = $verdict.Reason; Unneeded = $unneeded.ToArray() }
}

function ConvertFrom-LambekProofFact {
    param([string] $Text)

    # One fact as the checker reads it; $null for a shape it does not know
    $text = $Text.Trim()
    # (the day a thing was told on follows its last bar; a rule or a category has none after its parentheses)
    $text = $text -replace '\|[^()]*$', ''
    $category = [regex]::Match($text, '^category\((?<kind>[^|()]*)\|(?<who>[^|()]*)\|(?<what>[^|()]*)\)$')
    if ($category.Success) {
        $kind = $category.Groups['kind'].Value
        # A rule told with if about named ones, each part as kind~who~what: "if|is~name:rex~chien|does~name:rex~v:aboyer"
        $part = {
            param([string] $s)
            $bits = @($s -split '~')
            if ($bits.Count -ne 3) { return $null }
            [pscustomobject]@{ Kind = (@{ does = 'is'; doesnot = 'isnot' }[$bits[0]] ?? $bits[0]); Who = $bits[1]; Atoms = [string[]] @($bits[2] -split '\+' | Where-Object { $_ }) }
        }
        if ($kind -eq 'if') {
            $if = & $part $category.Groups['who'].Value
            $then = & $part $category.Groups['what'].Value
            if (-not $if -or -not $then -or $if.Kind -notin 'is', 'isnot' -or $then.Kind -notin 'is', 'isnot') { return $null }
            return [pscustomobject]@{ Shape = 'ruleif'; If = $if; Then = $then }
        }
        # One of two things told of named ones, each as kind~who~what: "or|is~name:rex~chien|is~name:max~chat"; each
        # part kept as the fact it says
        if ($kind -eq 'or') {
            $sides = @($category.Groups['who'].Value, $category.Groups['what'].Value)
            if (@($sides | Where-Object { $p = & $part $_; -not $p -or $p.Kind -notin 'is', 'isnot' }).Count -gt 0) { return $null }
            return [pscustomobject]@{ Shape = 'ruleor'; Parts = [string[]] @($sides | ForEach-Object { "category($($_ -replace '~', '|'))" }) }
        }
        # What one believes, the fact believed as kind~who~what: "believe|name:alice|is~name:rex~chat"
        if ($kind -eq 'believe') {
            return [pscustomobject]@{ Shape = 'belief'; Who = $category.Groups['who'].Value; Inner = "category($($category.Groups['what'].Value -replace '~', '|'))" }
        }
        $usual = $kind.StartsWith('usual:')
        if ($usual) { $kind = $kind.Substring(6) }
        # (what one does is said like what one is: its verb is among its kinds, "v:voler")
        $kind = @{ does = 'is'; doesnot = 'isnot' }[$kind] ?? $kind
        $set = { param($s) [string[]] @($s -split '\+' | Where-Object { $_ }) }
        return [pscustomobject]@{ Shape = 'category'; Kind = $kind; Usual = $usual; Who = $category.Groups['who'].Value; Atoms = (& $set $category.Groups['what'].Value); Subject = (& $set $category.Groups['who'].Value) }
    }
    $count = [regex]::Match($text, '^count\((?<way>least|most|exactly|notleast|notmost)\|(?<n>\d+)\|(?<s>[^|()]*)\|(?<p>[^|()]*)\)$')
    if ($count.Success) {
        return [pscustomobject]@{
            Shape = 'count'; Way = $count.Groups['way'].Value; N = [long] $count.Groups['n'].Value
            Subject = [string[]] @($count.Groups['s'].Value -split '\+' | Where-Object { $_ }); Atoms = [string[]] @($count.Groups['p'].Value -split '\+' | Where-Object { $_ })
        }
    }
    # One done on a day: date(time:arriver|name:rex|2026-10-18)
    $date = [regex]::Match($text, '^date\((?<of>[^|()]+)\|(?<who>[^|()]+)\|(?<day>\d{4}-\d{2}-\d{2})\)$')
    if ($date.Success) { return [pscustomobject]@{ Shape = 'date'; Of = $date.Groups['of'].Value; Who = $date.Groups['who'].Value; Day = $date.Groups['day'].Value } }
    $compare = [regex]::Match($text, '^compare\((?<kind>more|notmore)\|(?<of>[^|()]+)\|(?<a>[^|()]+)\|(?<b>[^|()]+)\)$')
    if ($compare.Success) {
        return [pscustomobject]@{ Shape = 'compare'; Kind = $compare.Groups['kind'].Value; Of = $compare.Groups['of'].Value; A = $compare.Groups['a'].Value; B = $compare.Groups['b'].Value }
    }
    if ($text.StartsWith('if(cond(')) {
        # if(cond(X), then(Y)): X and Y found by their parentheses
        $close = { param($s, $from) $depth = 0; for ($i = $from; $i -lt $s.Length; $i++) { if ($s[$i] -eq '(') { $depth++ } elseif ($s[$i] -eq ')') { $depth--; if ($depth -eq 0) { return $i } } }; return -1 }
        $open = 'if(cond'.Length
        $end = & $close $text $open
        if ($end -lt 0) { return $null }
        $condition = $text.Substring($open + 1, $end - $open - 1)
        $then = [regex]::Match($text.Substring($end + 1), '^\s*,\s*then\(')
        if (-not $then.Success) { return $null }
        $start = $end + 1 + $then.Length - 1
        $last = & $close $text $start
        if ($last -lt 0) { return $null }
        return [pscustomobject]@{ Shape = 'if'; If = $condition.Trim(); Then = $text.Substring($start + 1, $last - $start - 1).Trim() }
    }
    if ($text) { return [pscustomobject]@{ Shape = 'told'; Key = $text } }
    return $null
}

function Test-LambekProofOnce {
    param(
        [string[]] $Premises,
        [string[]] $Conclusions,
        # One case of a thing told with or: when what is told cannot all hold, the case is closed
        [switch] $Case
    )

    # (a premise in a shape it does not read: nothing is checked, it says so)
    $facts = [System.Collections.Generic.List[object]]::new()
    foreach ($premise in $Premises) {
        $fact = ConvertFrom-LambekProofFact -Text $premise
        if ($null -eq $fact) { return [pscustomobject]@{ Holds = $null; Reason = "not read: $premise" } }
        $facts.Add($fact)
    }
    $facts = @($facts)
    # One of two things told with or: what follows in each case follows (each case is the rest with that part told)
    for ($i = 0; $i -lt $facts.Count; $i++) {
        if ($facts[$i].Shape -ne 'ruleor') { continue }
        $rest = @(for ($j = 0; $j -lt $Premises.Count; $j++) { if ($j -ne $i) { $Premises[$j] } })
        $unsure = $false
        foreach ($side in $facts[$i].Parts) {
            $verdict = Test-LambekProofOnce -Premises ([string[]] @(@($rest) + @($side))) -Conclusions $Conclusions -Case
            if ($verdict.Holds -eq $false) { return $verdict }
            if ($null -eq $verdict.Holds) { $unsure = $true }
        }
        if ($unsure) { return [pscustomobject]@{ Holds = $null; Reason = "not checked: $($Conclusions -join ', ')" } }
        return [pscustomobject]@{ Holds = $true; Reason = '' }
    }
    $told = [System.Collections.Generic.HashSet[string]]::new()
    $rules = @($facts | Where-Object Shape -EQ 'if')
    foreach ($fact in @($facts | Where-Object Shape -EQ 'told')) { [void] $told.Add($fact.Key) }
    # Modus ponens, as far as it goes
    do {
        $more = $false
        foreach ($rule in $rules) { if ($told.Contains($rule.If) -and $told.Add($rule.Then)) { $more = $true } }
    } while ($more)

    $kinds = @($facts | Where-Object { $_.Shape -eq 'category' })
    # One more so than one told to be so is so; one less so than one told not to be is not (being so is being so
    # beyond some point, the same for both): what was told one is, and is not, of one word, carried along "more"
    $compared = @($facts | Where-Object { $_.Shape -eq 'compare' -and $_.Kind -eq 'more' })
    if ($compared.Count -gt 0) {
        $said = [System.Collections.Generic.List[object]]::new()
        foreach ($fact in @($kinds | Where-Object { -not $_.Usual -and $_.Kind -in 'is', 'isnot' -and @($_.Atoms).Count -eq 1 })) { $said.Add($fact) }
        do {
            $more = $false
            foreach ($edge in $compared) {
                foreach ($fact in @($said)) {
                    if ("$(@($fact.Atoms)[0])" -ne $edge.Of) { continue }
                    $who = $(if ($fact.Kind -eq 'is' -and $fact.Who -eq $edge.B) { $edge.A } elseif ($fact.Kind -eq 'isnot' -and $fact.Who -eq $edge.A) { $edge.B } else { $null })
                    if (-not $who -or @($said | Where-Object { $_.Kind -eq $fact.Kind -and $_.Who -eq $who -and "$(@($_.Atoms)[0])" -eq $edge.Of }).Count -gt 0) { continue }
                    $said.Add([pscustomobject]@{ Shape = 'category'; Kind = $fact.Kind; Usual = $false; Who = $who; Atoms = [string[]] @($edge.Of); Subject = [string[]] @($who) })
                    $more = $true
                }
            }
        } while ($more)
        $kinds = @(@($kinds | Where-Object { $_.Usual -or $_.Kind -notin 'is', 'isnot' -or @($_.Atoms).Count -ne 1 }) + @($said))
    }
    $strict = @($kinds | Where-Object { -not $_.Usual -and $_.Kind -in 'all', 'no' })
    $usual = @($kinds | Where-Object { $_.Usual -and $_.Kind -in 'all', 'no' })
    $subset = { param([string[]] $part, $whole) @($part | Where-Object { -not $whole.Contains($_) }).Count -eq 0 }

    # What one is, and is not, by the strict rules: the kinds it is in, and the sets of kinds it is not all of
    $close = {
        param([string[]] $is, [object[]] $isNot)
        $pos = [System.Collections.Generic.HashSet[string]]::new([string[]] $is)
        $neg = [System.Collections.Generic.List[string[]]]::new()
        foreach ($set in $isNot) { $neg.Add([string[]] $set) }
        do {
            $more = $false
            foreach ($rule in $strict) {
                if (-not (& $subset $rule.Subject $pos)) { continue }
                if ($rule.Kind -eq 'all') { foreach ($atom in $rule.Atoms) { if ($pos.Add($atom)) { $more = $true } } }
                elseif (@($neg | Where-Object { ($_ -join '+') -eq ($rule.Atoms -join '+') }).Count -eq 0) { $neg.Add($rule.Atoms); $more = $true }
            }
        } while ($more)
        [pscustomobject]@{ Is = $pos; IsNot = $neg }
    }
    $isNotAll = { param($state, [string[]] $atoms) @($state.IsNot | Where-Object { & $subset $_ ([System.Collections.Generic.HashSet[string]]::new([string[]] $atoms)) }).Count -gt 0 }
    # One is not all of these kinds when being them too would make it what it is not (every cat is black, I am not
    # black: I am not a cat)
    $refuted = {
        param([string[]] $is, [object[]] $isNot, [string[]] $atoms)
        $state = & $close ([string[]] @(@($is) + @($atoms) | Where-Object { $_ })) $isNot
        @($state.IsNot | Where-Object { & $subset $_ $state.Is }).Count -gt 0
    }

    # (what was told one is, and the sets of kinds told it is not all of; each given back whole, as one array)
    $toldIs = { param([string] $who) , [string[]] @($kinds | Where-Object { -not $_.Usual -and $_.Kind -eq 'is' -and $_.Who -eq $who } | ForEach-Object { $_.Atoms }) }
    $toldNot = { param([string] $who) , [object[]] @($kinds | Where-Object { -not $_.Usual -and $_.Kind -eq 'isnot' -and $_.Who -eq $who } | ForEach-Object { , $_.Atoms }) }
    $individual = { param([string] $who) & $close (& $toldIs $who) (& $toldNot $who) }

    # The rules told with if about named ones: when the condition holds of the one it is about, what follows holds of
    # its own; when what follows cannot hold, the condition does not (si Rex est un chien, Rex aboie; Rex n'aboie pas:
    # Rex n'est pas un chien). As far as it goes, what is found told as of each one
    $conditional = @($facts | Where-Object { $_.Shape -eq 'ruleif' })
    if ($conditional.Count -gt 0) {
        $holds = {
            param($part)
            $state = & $individual $part.Who
            if ($part.Kind -eq 'is') { & $subset $part.Atoms $state.Is }
            else { (& $isNotAll $state $part.Atoms) -or (& $refuted (& $toldIs $part.Who) (& $toldNot $part.Who) $part.Atoms) }
        }
        $flipped = { param($part) [pscustomobject]@{ Kind = $(if ($part.Kind -eq 'is') { 'isnot' } else { 'is' }); Who = $part.Who; Atoms = $part.Atoms } }
        $known = { param($part) @($kinds | Where-Object { -not $_.Usual -and $_.Kind -eq $part.Kind -and $_.Who -eq $part.Who -and ($_.Atoms -join '+') -eq ($part.Atoms -join '+') }).Count -gt 0 }
        $add = { param($part) [pscustomobject]@{ Shape = 'category'; Kind = $part.Kind; Usual = $false; Who = $part.Who; Atoms = $part.Atoms; Subject = [string[]] @($part.Who) } }
        do {
            $more = $false
            foreach ($rule in $conditional) {
                if ((& $holds $rule.If) -and -not (& $known $rule.Then)) { $kinds = @($kinds) + @(& $add $rule.Then); $more = $true }
                $back = & $flipped $rule.If
                if ((& $holds (& $flipped $rule.Then)) -and -not (& $known $back)) { $kinds = @($kinds) + @(& $add $back); $more = $true }
            }
        } while ($more)
    }

    # (a case of a thing told with or that cannot be with the rest: one named is, and is not, the same)
    if ($Case) {
        foreach ($who in @($kinds | Where-Object { -not $_.Usual -and $_.Kind -in 'is', 'isnot' } | ForEach-Object { $_.Who } | Select-Object -Unique)) {
            $state = & $individual $who
            if (@($state.IsNot | Where-Object { & $subset $_ $state.Is }).Count -gt 0) { return [pscustomobject]@{ Holds = $true; Reason = '' } }
        }
    }

    # What is supposed of one: each rule that holds normalement and starts from what it is, unless what it says is
    # already known false, or a rule about a narrower kind it also starts from says otherwise
    $suppose = {
        param($state)
        $is = [System.Collections.Generic.HashSet[string]]::new($state.Is)
        $isNot = [System.Collections.Generic.List[string[]]]::new($state.IsNot)
        $open = @($usual | Where-Object { & $subset $_.Subject $state.Is })
        foreach ($rule in $open) {
            $says = $(if ($rule.Kind -eq 'all') { 'is' } else { 'isnot' })
            if ($says -eq 'is' -and (& $isNotAll $state $rule.Atoms)) { continue }
            if ($says -eq 'isnot' -and (& $subset $rule.Atoms $state.Is)) { continue }
            $beaten = @($open | Where-Object {
                    $other = $_
                    $other -ne $rule -and $other.Kind -ne $rule.Kind -and ($other.Atoms -join '+') -eq ($rule.Atoms -join '+') -and
                    (& $subset $rule.Subject (& $close $other.Subject @()).Is) -and -not (& $subset $other.Subject (& $close $rule.Subject @()).Is)
                }).Count -gt 0
            $tied = @($open | Where-Object {
                    $other = $_
                    $other -ne $rule -and $other.Kind -ne $rule.Kind -and ($other.Atoms -join '+') -eq ($rule.Atoms -join '+') -and
                    -not (& $subset $rule.Subject (& $close $other.Subject @()).Is) -and -not (& $subset $other.Subject (& $close $rule.Subject @()).Is)
                }).Count -gt 0
            if ($beaten -or $tied) { continue }
            if ($says -eq 'is') { foreach ($atom in $rule.Atoms) { [void] $is.Add($atom) } } else { $isNot.Add($rule.Atoms) }
        }
        [pscustomobject]@{ Is = $is; IsNot = $isNot }
    }

    # One of several kinds ("or:chat;chien", each kind of several words written chat&noir): what holds in each of them
    # holds; one that cannot be, with what else one is and is not, is no case at all (Rex is a dog or a cat, Rex is not a
    # cat: Rex is a dog). Each such property is taken apart once, the first in order first
    $alternatives = { param([string] $atom) @("$atom".Substring(3) -split ';' | ForEach-Object { , [string[]] @($_ -split '&' | Where-Object { $_ }) }) }
    $has = {
        param($state, [string] $atom)
        if (-not "$atom".StartsWith('or:')) { return $state.Is.Contains($atom) }
        $state.Is.Contains($atom) -or @(& $alternatives $atom | Where-Object { & $subset $_ $state.Is }).Count -gt 0
    }
    $hasNot = {
        param($state, [string[]] $is, [object[]] $isNot, [string[]] $atoms)
        # (not all of them: for one of several kinds, none of the kinds)
        $plain = @($atoms | Where-Object { -not "$_".StartsWith('or:') })
        $either = @($atoms | Where-Object { "$_".StartsWith('or:') })
        if ($either.Count -eq 0) { return (& $isNotAll $state $plain) -or (& $refuted $is $isNot $plain) }
        if ($plain.Count -gt 0 -or $either.Count -gt 1) { return $false }
        @(& $alternatives $either[0] | Where-Object { -not ((& $isNotAll $state $_) -or (& $refuted $is $isNot $_)) }).Count -eq 0
    }
    $cases = {
        param([string] $kind, [string[]] $atoms, [string[]] $is, [object[]] $isNot, [string[]] $used)
        $state = & $close $is $isNot
        # (a case that cannot be: nothing to show in it)
        if (@($state.IsNot | Where-Object { & $subset $_ $state.Is }).Count -gt 0) { return $true }
        $here = $(if ($kind -eq 'is') { @($atoms | Where-Object { -not (& $has $state $_) }).Count -eq 0 } else { & $hasNot $state $is $isNot $atoms })
        if ($here) { return $true }
        $open = @($state.Is | Where-Object { "$_".StartsWith('or:') -and $_ -notin $used } | Sort-Object | Select-Object -First 1)
        if ($open.Count -eq 0) { return $false }
        foreach ($alternative in (& $alternatives $open[0])) {
            if (-not (& $cases $kind $atoms ([string[]] @(@($is) + @($alternative))) $isNot ([string[]] @(@($used) + @($open[0]))))) { return $false }
        }
        return $true
    }

    if ($Conclusions.Count -eq 0) { return [pscustomobject]@{ Holds = $null; Reason = 'no conclusion' } }
    foreach ($conclusion in $Conclusions) {
        $said = ConvertFrom-LambekProofFact -Text $conclusion
        if (-not $said) { return [pscustomobject]@{ Holds = $null; Reason = "not read: $conclusion" } }
        if ($said.Shape -eq 'told') {
            if (-not $told.Contains($said.Key)) { return [pscustomobject]@{ Holds = $false; Reason = "does not follow: $conclusion" } }
            continue
        }
        if ($said.Shape -eq 'count') {
            # (how many: at least so many of a narrower kind being something narrower are at least as many of the wider;
            # at most so many of a wider kind being something wider, at most as many of the narrower; what is narrower is
            # what the strict rules give, or a part of it)
            $within = { param([string[]] $narrow, [string[]] $wide) & $subset $wide (& $close $narrow @()).Is }
            $counts = @($facts | Where-Object { $_.Shape -eq 'count' })
            $least = { param($n) @($counts | Where-Object { $_.Way -in 'least', 'exactly' -and $_.N -ge $n -and (& $within $_.Subject $said.Subject) -and (& $within $_.Atoms $said.Atoms) }).Count -gt 0 }
            $most = { param($n) @($counts | Where-Object { $_.Way -in 'most', 'exactly' -and $_.N -le $n -and (& $within $said.Subject $_.Subject) -and (& $within $said.Atoms $_.Atoms) }).Count -gt 0 }
            $holds = switch ($said.Way) {
                'least' { & $least $said.N }
                'most' { & $most $said.N }
                'exactly' { (& $least $said.N) -and (& $most $said.N) }
                'notleast' { $said.N -ge 1 -and (& $most ($said.N - 1)) }
                'notmost' { & $least ($said.N + 1) }
            }
            if (-not $holds) { return [pscustomobject]@{ Holds = $false; Reason = "does not follow: $conclusion" } }
            continue
        }
        if ($said.Shape -eq 'compare') {
            # (more than: every one reached from the one that is more, by what was told is more than what)
            $more = @($facts | Where-Object { $_.Shape -eq 'compare' -and $_.Kind -eq 'more' -and $_.Of -eq $said.Of })
            # (one done on a day before the day another did it is before it, and the other after it: of
            # time:before:arriver, from date(time:arriver|...))
            $timed = [regex]::Match($said.Of, '^time:(?<way>before|after):(?<done>.+)$')
            $days = @(if ($timed.Success) { $facts | Where-Object { $_.Shape -eq 'date' -and $_.Of -eq "time:$($timed.Groups['done'].Value)" } })
            foreach ($early in $days) {
                foreach ($late in $days) {
                    if ([string]::CompareOrdinal($early.Day, $late.Day) -ge 0 -or $early.Who -eq $late.Who) { continue }
                    $edge = $(if ($timed.Groups['way'].Value -eq 'before') { [pscustomobject]@{ A = $early.Who; B = $late.Who } } else { [pscustomobject]@{ A = $late.Who; B = $early.Who } })
                    $more = @($more) + @($edge)
                }
            }
            $reach = {
                param([string] $from, [string] $to)
                $seen = [System.Collections.Generic.HashSet[string]]::new()
                $todo = [System.Collections.Generic.Queue[string]]::new()
                $todo.Enqueue($from)
                while ($todo.Count -gt 0) {
                    $at = $todo.Dequeue()
                    foreach ($fact in @($more | Where-Object { $_.A -eq $at })) {
                        if ($fact.B -eq $to) { return $true }
                        if ($seen.Add($fact.B)) { $todo.Enqueue($fact.B) }
                    }
                }
                return $false
            }
            $holds = $(if ($said.Kind -eq 'more') { & $reach $said.A $said.B } else { & $reach $said.B $said.A })
            if (-not $holds) { return [pscustomobject]@{ Holds = $false; Reason = "does not follow: $conclusion" } }
            continue
        }
        if ($said.Shape -eq 'date') {
            # (done on that day: told so)
            if (@($facts | Where-Object { $_.Shape -eq 'date' -and $_.Of -eq $said.Of -and $_.Who -eq $said.Who -and $_.Day -eq $said.Day }).Count -eq 0) { return [pscustomobject]@{ Holds = $false; Reason = "does not follow: $conclusion" } }
            continue
        }
        if ($said.Shape -eq 'belief') {
            # What one believes follows from what that one believes alone
            $believed = @($facts | Where-Object { $_.Shape -eq 'belief' -and $_.Who -eq $said.Who } | ForEach-Object { $_.Inner })
            $inner = Test-LambekProofOnce -Premises ([string[]] $believed) -Conclusions ([string[]] @($said.Inner))
            if ($inner.Holds -eq $false) { return [pscustomobject]@{ Holds = $false; Reason = "does not follow: $conclusion" } }
            if ($null -eq $inner.Holds) { return [pscustomobject]@{ Holds = $null; Reason = "not checked: $conclusion" } }
            continue
        }
        if ($said.Shape -ne 'category') { return [pscustomobject]@{ Holds = $null; Reason = "not checked: $conclusion" } }
        $holds = $null
        switch ($said.Kind) {
            { $_ -in 'is', 'isnot' } {
                if ($said.Usual) {
                    $state = & $suppose (& $individual $said.Who)
                    $holds = $(if ($said.Kind -eq 'is') { & $subset $said.Atoms $state.Is } else { (& $isNotAll $state $said.Atoms) -or (& $refuted (& $toldIs $said.Who) (& $toldNot $said.Who) $said.Atoms) })
                }
                else { $holds = & $cases $said.Kind $said.Atoms (& $toldIs $said.Who) (& $toldNot $said.Who) @() }
            }
            { $_ -in 'all', 'no' } {
                # Every one of the kind: what one that is only of that kind is
                $holds = & $cases $(if ($said.Kind -eq 'all') { 'is' } else { 'isnot' }) $said.Atoms $said.Subject @() @()
            }
            default { return [pscustomobject]@{ Holds = $null; Reason = "not checked: $conclusion" } }
        }
        if (-not $holds) { return [pscustomobject]@{ Holds = $false; Reason = "does not follow: $conclusion" } }
    }
    return [pscustomobject]@{ Holds = $true; Reason = '' }
}

function Test-LambekCalculation {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Text)

    # A sum as an answer shows it, "2 + 3 = 5" or "2,5 + 1 = 3,5": $true when it is right, $false when it is not, $null
    # for what is not a sum of numbers
    $sides = $Text -split '='
    if ($sides.Count -ne 2) { return $null }
    $number = {
        param([string] $part)
        # (spaces group the thousands; a comma alone is the decimal mark)
        $digits = ($part -replace '[\s\u00A0\u202F]', '')
        if ($digits -notmatch '^-?\d+([.,]\d+)?$') { return $null }
        [decimal]::Parse(($digits -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
    }
    $parts = @($sides[0] -split '\+')
    $total = & $number $sides[1]
    if ($null -eq $total -or $parts.Count -lt 2) { return $null }
    $sum = [decimal] 0
    $places = [regex]::Match($sides[1], '[.,](\d+)').Groups[1].Length
    foreach ($part in $parts) {
        $term = & $number $part
        if ($null -eq $term) { return $null }
        $sum += $term
        $places = [math]::Max($places, [regex]::Match($part, '[.,](\d+)').Groups[1].Length)
    }
    # (numbers shown rounded are each off by at most half their last place)
    $slack = [decimal] 0.5 * [decimal] [math]::Pow(10, -$places) * ($parts.Count + 1)
    if ($places -eq 0) { $slack = 0 }
    return [math]::Abs($sum - $total) -le $slack
}
