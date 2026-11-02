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
      if(cond(X), then(Y))|            a rule told with if: when X was told, Y follows
      X|                               a thing told, as it is held (what follows the last bar is its day)
    and what an answer may conclude: one of those facts, or "usual:is"/"usual:isnot" about someone, for what is only
    supposed. The rules it uses:
      - one is every kind its kinds are in (Tom is a cat, every cat is an animal: Tom is an animal)
      - one is not what no one of its kinds is (Nemo is a fish, no fish is a mammal: Nemo is not a mammal)
      - one is not of a kind when being of it too would make it what it is not (every cat is black, I am not black: I
        am not a cat)
      - every one of a kind is what a wider kind is (every cat is a mammal, every mammal is an animal)
      - what holds normalement is supposed of one when nothing told and no rule about a narrower kind says otherwise
      - modus ponens on the rules told with if
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
        $usual = $kind.StartsWith('usual:')
        if ($usual) { $kind = $kind.Substring(6) }
        # (what one does is said like what one is: its verb is among its kinds, "v:voler")
        $kind = @{ does = 'is'; doesnot = 'isnot' }[$kind] ?? $kind
        $set = { param($s) [string[]] @($s -split '\+' | Where-Object { $_ }) }
        return [pscustomobject]@{ Shape = 'category'; Kind = $kind; Usual = $usual; Who = $category.Groups['who'].Value; Atoms = (& $set $category.Groups['what'].Value); Subject = (& $set $category.Groups['who'].Value) }
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
    param([string[]] $Premises, [string[]] $Conclusions)

    $facts = @(foreach ($premise in $Premises) { ConvertFrom-LambekProofFact -Text $premise })
    $told = [System.Collections.Generic.HashSet[string]]::new()
    $rules = @($facts | Where-Object Shape -EQ 'if')
    foreach ($fact in @($facts | Where-Object Shape -EQ 'told')) { [void] $told.Add($fact.Key) }
    # Modus ponens, as far as it goes
    do {
        $more = $false
        foreach ($rule in $rules) { if ($told.Contains($rule.If) -and $told.Add($rule.Then)) { $more = $true } }
    } while ($more)

    $kinds = @($facts | Where-Object { $_.Shape -eq 'category' })
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

    if ($Conclusions.Count -eq 0) { return [pscustomobject]@{ Holds = $null; Reason = 'no conclusion' } }
    foreach ($conclusion in $Conclusions) {
        $said = ConvertFrom-LambekProofFact -Text $conclusion
        if (-not $said) { return [pscustomobject]@{ Holds = $null; Reason = "not read: $conclusion" } }
        if ($said.Shape -eq 'told') {
            if (-not $told.Contains($said.Key)) { return [pscustomobject]@{ Holds = $false; Reason = "does not follow: $conclusion" } }
            continue
        }
        if ($said.Shape -ne 'category') { return [pscustomobject]@{ Holds = $null; Reason = "not checked: $conclusion" } }
        $holds = $null
        switch ($said.Kind) {
            { $_ -in 'is', 'isnot' } {
                $state = & $individual $said.Who
                if ($said.Usual) { $state = & $suppose $state }
                $holds = $(if ($said.Kind -eq 'is') { & $subset $said.Atoms $state.Is } else { (& $isNotAll $state $said.Atoms) -or (& $refuted (& $toldIs $said.Who) (& $toldNot $said.Who) $said.Atoms) })
            }
            { $_ -in 'all', 'no' } {
                # Every one of the kind: what one that is only of that kind is
                $state = & $close $said.Subject @()
                $holds = $(if ($said.Kind -eq 'all') { & $subset $said.Atoms $state.Is } else { (& $isNotAll $state $said.Atoms) -or (& $refuted $said.Subject @() $said.Atoms) })
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
