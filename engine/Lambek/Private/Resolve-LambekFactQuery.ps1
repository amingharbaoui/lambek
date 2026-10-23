function Resolve-LambekFactQuery {
    # A question about the world made of several facts read in Wikidata, each one said with where it was read:
    #   "Mozart est-il ne avant Beethoven ?", "who was born first, Mozart or Beethoven?": two dates compared
    #   "quelle est la ville la plus peuplee du Japon ?": the most (or least) of a kind of things, in a place
    #   "ou est ne l'auteur de Germinal ?", "quelle est la capitale du pays le plus peuple d'Europe ?": a thing named
    #   by what it is (the author of a book, the most populous country of a continent), then the question about it
    # Every word is read, as for one fact; a word left over and nothing is said. Only what is surely known is said: the
    # most of a kind, when the things kept are surely all those that could be the most (the cities of 100 000 people
    # or more hold the most populous one, not the least populous one: Query.Superlatives says which)
    param([string] $Plain, [bool] $Asked, [string[]] $Languages)

    $base = Get-LambekFactBase
    $all = @($Plain -split ' ' | Where-Object { $_ })
    $script:FactReads = [System.Collections.Generic.List[object]]::new()
    # What the user told about a name of the question comes first: then the conversation answers, not Wikidata
    $told = @((Get-LambekTold).ToArray() | ForEach-Object { " $([LambekFacts]::Plain("$($_.Text)")) " })
    if ($told.Count -gt 0) {
        foreach ($mention in @($base.Find($Plain))) {
            if ($mention.Name.Length -lt 3) { continue }
            if (@($told | Where-Object { $_.Contains(" $($mention.Name) ") }).Count -gt 0) { return $null }
        }
    }
    foreach ($language in $Languages) {
        $facts = (Get-LambekLexicon -Language $language).Facts
        if (-not $facts.Contains('Query')) { continue }
        $words = @(Get-LambekFactQuestionWord -Words $all -Facts $facts)
        if ($words.Count -eq 0) { continue }

        $compared = Resolve-LambekFactCompare -Words $words -Asked $Asked -Language $language -Facts $facts
        if ($compared) { return $compared }

        # A thing named by what it is, somewhere in the question
        for ($at = 0; $at -lt $words.Count; $at++) {
            $phrase = Read-LambekFactNoun -Words $words -At $at -Language $language -Facts $facts -Depth 0
            if (-not $phrase) { continue }
            $before = @($(if ($at -gt 0) { $words[0..($at - 1)] }))
            $after = @($(if ($phrase.End -lt $words.Count) { $words[$phrase.End..($words.Count - 1)] }))
            # The question is that thing itself: "quelle est la capitale du pays le plus peuple d'Europe ?"
            if (Test-LambekFactAround -Words (@($before) + @($after)) -Facts $facts -Asked $Asked) {
                return [pscustomobject]@{ Language = $language; Reply = (@($phrase.Lines) -join "`n"); Fact = $phrase.Fact }
            }
            # Else a question about it: "ou est ne [l'auteur de Germinal] ?", read with its name in its place
            $name = [LambekFacts]::Plain($phrase.Thing.Label($language))
            $rewritten = (@($before) + @($name) + @($after)) -join ' '
            $read = Resolve-LambekFactReading -Plain $rewritten -Asked $Asked -Languages @($language) -PinName $name -Pin $phrase.Thing
            if (-not $read) { return $null }
            # ("pourquoi ?": every fact read, the one about the thing found last)
            $last = Get-LambekLastProof
            if ($last) { Set-LambekLastProof -Read (@($script:FactReads) + @($last.Read)) }
            return [pscustomobject]@{ Language = $language; Reply = ((@($phrase.Lines) + @($read.Reply)) -join "`n"); Fact = $read.Fact }
        }
    }
    return $null
}

function Get-LambekFactQuestionWord {
    # The words of the question without the asking and thanking around it ("dis-moi", "s'il te plait")
    param([string[]] $Words, [hashtable] $Facts)

    $from = 0
    $to = $Words.Count
    foreach ($pass in 1..2) {
        $open = @(Find-LambekFactSpan -Words $Words -Phrases @($Facts['Openers']) -From $from -To $to -Before ($from + 1))
        if ($open.Count -gt 0) { $from += $open[0].Length }
        $close = @(Find-LambekFactSpan -Words $Words -Phrases @($Facts['Closers']) -From ([math]::Max($from, $to - 3)) -To $to | Where-Object { $_.Start + $_.Length -eq $to })
        if ($close.Count -gt 0) { $to = $close[0].Start }
    }
    if ($to -le $from) { return [string[]] @() }
    return [string[]] @($Words[$from..($to - 1)])
}

function Test-LambekFactAround {
    # Only a question word and small words around what is asked ("quelle est", "what is the"), and a question indeed:
    # a question word, or the question mark
    param([string[]] $Words, [hashtable] $Facts, [bool] $Asked)

    $fillers = [System.Collections.Generic.HashSet[string]]::new([string[]] @($Facts['Fillers']), [StringComparer]::Ordinal)
    $phrases = @($Facts['Questions'].Values | ForEach-Object { @($_) })
    $read = [bool[]]::new($Words.Count)
    $question = $false
    foreach ($span in @(Find-LambekFactSpan -Words $Words -Phrases $phrases)) {
        $question = $true
        for ($k = $span.Start; $k -lt $span.Start + $span.Length; $k++) { $read[$k] = $true }
    }
    for ($k = 0; $k -lt $Words.Count; $k++) { if (-not $read[$k] -and -not $fillers.Contains($Words[$k])) { return $false } }
    return ($question -or $Asked)
}

function Select-LambekFactThing {
    # The thing a name names among those of some kinds: the best known, when it is far better known than the next one;
    # a person named by the last word of their name only when that is clear beyond doubt (as the reading of one fact)
    param([object] $Mention, [string[]] $Kinds)

    $things = @($Mention.Things | Where-Object { $thing = $_; @($Kinds | Where-Object { $thing.Is($_) }).Count -gt 0 })
    if ($things.Count -eq 0) { return $null }
    $ratio = $(if ($Mention.Surname) { 3 } else { 2 })
    if ($Mention.Surname -and $things[0].Links -lt 50) { return $null }
    if ($things.Count -gt 1 -and $things[0].Links -lt $ratio * $things[1].Links) { return $null }
    return $things[0]
}

function Read-LambekFactName {
    # A thing of some kinds named at a place of the question: by its name ("Germinal", "la Joconde", "du film Titanic"),
    # or by what it is ("du pays le plus peuple d'Europe"); with where its name ends
    param([string[]] $Words, [int] $At, [string[]] $Kinds, [string] $Language, [hashtable] $Facts, [int] $Depth)

    if ($At -ge $Words.Count) { return $null }
    if ($Depth -lt 2) {
        $inner = Read-LambekFactNoun -Words $Words -At $At -Language $Language -Facts $Facts -Depth ($Depth + 1)
        if ($inner -and @($Kinds | Where-Object { $inner.Thing.Is($_) }).Count -gt 0) { return $inner }
    }
    $base = Get-LambekFactBase
    $mentions = @($base.Find(($Words -join ' ')))
    $nouns = @($Kinds | ForEach-Object { @($Facts['Kinds'][$_]) })
    # (a small word or the kind of the thing before its name: "de la Joconde", "du film Titanic")
    $places = [System.Collections.Generic.List[int]]::new()
    $places.Add($At)
    $at = $At
    if ($Words[$at] -in @($Facts['Query']['Determiners'])) { $at++; $places.Add($at) }
    $noun = @(Find-LambekFactSpan -Words $Words -Phrases $nouns -From $at -Before ($at + 1))
    if ($noun.Count -gt 0) { $places.Add($at + $noun[0].Length) }
    foreach ($place in $places) {
        $here = @($mentions | Where-Object Start -EQ $place | Sort-Object Length -Descending)
        foreach ($mention in $here) {
            $thing = Select-LambekFactThing -Mention $mention -Kinds $Kinds
            if ($thing) { return [pscustomobject]@{ Thing = $thing; Start = $place; End = $place + $mention.Length; Lines = @(); Fact = $null } }
            # (the longest name at that place only: "Les Miserables" is not "Les")
            break
        }
    }
    return $null
}

function Read-LambekFactNoun {
    # A thing named by what it is, at a place of the question: the value of a fact of another thing ("l'auteur de
    # Germinal", "the capital of the most populous country in Africa"), or the most of a kind ("la ville la plus peuplee
    # du Japon"). With the sentences that say how it was found, each one read in Wikidata
    param([string[]] $Words, [int] $At, [string] $Language, [hashtable] $Facts, [int] $Depth)

    $base = Get-LambekFactBase
    $query = $Facts['Query']
    $i = $At
    if ($i -lt $Words.Count -and $Words[$i] -in @($query['Determiners'])) { $i++ }
    if ($i -ge $Words.Count) { return $null }

    # The value of a fact: "l'auteur de", "the director of"
    foreach ($relation in @($Facts['Relations'] | Where-Object { $_.Contains('Role') -and -not ($_.Contains('Inverse') -and $_['Inverse']) })) {
        $role = @(Find-LambekFactSpan -Words $Words -Phrases @($relation['Role']) -From $i -Before ($i + 1))
        if ($role.Count -eq 0) { continue }
        $j = $i + $role[0].Length
        # (after "de la", the name, or the name that starts with "la": "de la France", "de la Joconde")
        $inner = $null
        foreach ($of in @($query['Of'] | ForEach-Object { , @("$_" -split ' ') } | Sort-Object { - $_.Count })) {
            if ($j + $of.Count -gt $Words.Count -or (@($Words[$j..($j + $of.Count - 1)]) -join ' ') -ne ($of -join ' ')) { continue }
            $inner = Read-LambekFactName -Words $Words -At ($j + $of.Count) -Kinds @($relation['Subject']) -Language $Language -Facts $Facts -Depth $Depth
            if ($inner) { break }
        }
        if (-not $inner) { continue }
        $values = @($inner.Thing.Values("$($relation['Property'])") | ForEach-Object { $base.Thing($_.Value) } | Where-Object { $_ -and $_.Labels.Count -gt 0 })
        if ($values.Count -ne 1) { return $null }
        # Said as the reading of that one fact says it
        $mention = [pscustomobject]@{ Name = [LambekFacts]::Plain($inner.Thing.Label($Language)); Length = $inner.End - $inner.Start; Surname = $false }
        # (the small words said before a thing named by what it is are not those of its name: "du [pays le plus peuple]")
        $start = $(if (@($inner.Lines).Count -gt 0) { 0 } else { $inner.Start })
        $candidate = [pscustomobject]@{ Relation = $relation; Mention = $mention; Start = $start; Things = @($inner.Thing); Object = $null; Inverse = $false }
        $said = Get-LambekFactReply -Candidate $candidate -Base $base -Facts $Facts -Language $Language -Words $Words
        if (-not $said) { return $null }
        $entry = Add-LambekFactRead -Text $said.Reply -Language $Language -Core $said.Core -Thing $inner.Thing.Id -Property "$($relation['Property'])" -Bare $said.Bare
        return [pscustomobject]@{ Thing = $values[0]; Start = $At; End = $inner.End; Lines = @(@($inner.Lines) + @($said.Reply)); Fact = $entry }
    }

    # The most of a kind: "la ville la plus peuplee du Japon", "la plus grande ville d'Allemagne", "the most populous
    # country in South America"
    foreach ($entry in @($query['Superlatives'])) {
        foreach ($kind in @($entry['Kinds'])) {
            $nouns = @($Facts['Kinds'][$kind])
            $end = -1
            $noun = @(Find-LambekFactSpan -Words $Words -Phrases $nouns -From $i -Before ($i + 1))
            if ($noun.Count -gt 0) {
                $j = $i + $noun[0].Length
                $most = @(Find-LambekFactSpan -Words $Words -Phrases @($entry['Words']) -From $j -Before ($j + 1))
                if ($most.Count -gt 0) { $end = $j + $most[0].Length }
            }
            if ($end -lt 0) {
                $most = @(Find-LambekFactSpan -Words $Words -Phrases @($entry['Words']) -From $i -Before ($i + 1))
                if ($most.Count -gt 0) {
                    $j = $i + $most[0].Length
                    $noun = @(Find-LambekFactSpan -Words $Words -Phrases $nouns -From $j -Before ($j + 1))
                    if ($noun.Count -gt 0) { $end = $j + $noun[0].Length }
                }
            }
            if ($end -lt 0) { continue }
            $most = Get-LambekFactMost -Words $Words -At $end -Entry $entry -Kind $kind -Language $Language -Facts $Facts
            if (-not $most) { return $null }
            return [pscustomobject]@{ Thing = $most.Thing; Start = $At; End = $most.End; Lines = @($most.Line); Fact = $most.Fact }
        }
    }
    return $null
}

function Get-LambekFactMost {
    # The most (or least) of a kind in a place said after it ("du Japon", "d'Europe", "in Brazil"), or in the world
    # ("du monde", or nothing said): every thing of that kind in that place, by the value of one fact
    param([string[]] $Words, [int] $At, [hashtable] $Entry, [string] $Kind, [string] $Language, [hashtable] $Facts)

    $base = Get-LambekFactBase
    $query = $Facts['Query']
    $scope = $null
    $end = $At
    $linker = @()
    $world = @(Find-LambekFactSpan -Words $Words -Phrases @($query['World']) -From $At -Before ($At + 1))
    if ($world.Count -gt 0) { $end = $At + $world[0].Length }
    else {
        $in = @(Find-LambekFactSpan -Words $Words -Phrases @($query['In']) -From $At -Before ($At + 1))
        if ($in.Count -gt 0) {
            $j = $At + $in[0].Length
            $linker = @($Words[$At..($j - 1)])
            # (the place: a thing other facts of that kind point at, by the paths Query.Within gives: a country for a
            # city, a continent for a city or a country)
            $paths = @($query['Within'][$Kind])
            $mentions = @($base.Find(($Words -join ' ')) | Where-Object Start -EQ $j | Sort-Object Length -Descending)
            foreach ($mention in $mentions) {
                $places = @($mention.Things | Where-Object { $_.Labels.Count -gt 0 })
                $places = @($places | Where-Object { $place = $_; @($paths | Where-Object { $base.Having("$(@($_)[-1])", $place.Id).Count -gt 0 }).Count -gt 0 })
                if ($places.Count -eq 0) { break }
                if ($places.Count -gt 1 -and $places[0].Links -lt 2 * $places[1].Links) { return $null }
                $scope = $places[0]
                $end = $j + $mention.Length
                break
            }
            if (-not $scope) { return $null }
        }
    }

    # Every thing of the kind in that place, with the value of the fact
    $property = "$($Entry['Property'])"
    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($thing in $base.OfKind($Kind)) {
        if ($scope -and -not (Test-LambekFactWithin -Thing $thing -Scope $scope -Paths @($query['Within'][$Kind]))) { continue }
        $values = @($thing.Values($property))
        # (one count, of a known year: a count without one is not kept)
        if ($values.Count -ne 1 -or "$($values[0].Extra)" -notmatch '^\d{4}$') { continue }
        $number = 0.0
        if (-not [double]::TryParse($values[0].Value, [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref] $number)) { continue }
        $kept.Add([pscustomobject]@{ Thing = $thing; Number = $number; Year = $values[0].Extra })
    }
    if ($kept.Count -lt 2) { return $null }
    $sorted = @($kept | Sort-Object Number -Descending:($Entry['Order'] -eq 'max'))
    # Two equal at the top, and it is not known which
    if ($sorted[0].Number -eq $sorted[1].Number) { return $null }
    $best = $sorted[0]

    $digits = ([decimal] $best.Number).ToString('#,0', [cultureinfo]::InvariantCulture) -replace ',', $Facts['Number']['Group']
    if ($scope) {
        # (with the small words the user said before it: "de France", "du Japon", "d'Afrique", "in Brazil")
        $label = $scope.Label($Language)
        $said = $linker -join ' '
        if ($said -eq 'd') { $where = "d'$label" }
        else { $where = "$said $label" }
    }
    else { $where = "$($query['WorldSay'])" }
    $template = "$($Entry['Say'][$Kind])"
    if (-not $template -or -not $best.Year) { return $null }
    # (a country with its article in French: "le Nigeria", "la Russie"; a city without: "Paris")
    $value = $best.Thing.Label($Language)
    if ($Kind -eq 'country' -and $Facts.Contains('Places') -and $Facts['Places']) {
        $article = Get-LambekFactPlace -Label $value -Language $Language -Facts $Facts
        if ($article) { $value = $article.The }
    }
    $fill = @{ scope = $where; value = $value; digits = $digits; year = $best.Year }
    $sentence = [regex]::Replace($template, '\{(\w+)\}', { param($m) "$($fill[$m.Groups[1].Value])" })
    $core = "wikidata($($Entry['Order']), $property, $Kind, $(if ($scope) { $scope.Id } else { 'world' }), $($best.Thing.Id))"
    $fact = Add-LambekFactRead -Text ($sentence + $Facts['According'] + '.') -Language $Language -Core $core -Thing $best.Thing.Id -Property $property -Bare "$sentence."
    return [pscustomobject]@{ Thing = $best.Thing; End = $end; Line = ($sentence + $Facts['According'] + '.'); Fact = $fact }
}

function Test-LambekFactWithin {
    # Whether a thing is in a place by one of the paths of facts: P17 (its country), or P17 then P30 (the continent of
    # its country)
    param([LambekThing] $Thing, [LambekThing] $Scope, [object[]] $Paths)

    $base = Get-LambekFactBase
    foreach ($path in $Paths) {
        $here = @($Thing)
        foreach ($property in @($path)) {
            $next = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $here) {
                foreach ($fact in @($item.Values("$property"))) {
                    if ($fact.Value -eq $Scope.Id) { $next.Add($Scope); continue }
                    $value = $base.Thing($fact.Value)
                    if ($value) { $next.Add($value) }
                }
            }
            $here = @($next)
        }
        if (@($here | Where-Object { $_.Id -eq $Scope.Id }).Count -gt 0) { return $true }
    }
    return $false
}

function Resolve-LambekFactCompare {
    # Two things compared by the date of one fact: "Mozart est-il ne avant Beethoven ?" (yes or no), "Folklore est-il
    # sorti avant ou apres Lover ?" (which), "qui est le plus age, Victor Hugo ou Balzac ?" (one of the two)
    param([string[]] $Words, [bool] $Asked, [string] $Language, [hashtable] $Facts)

    $base = Get-LambekFactBase
    $query = $Facts['Query']
    $fillers = [System.Collections.Generic.HashSet[string]]::new([string[]] @($Facts['Fillers']), [StringComparer]::Ordinal)
    $comparison = $null
    $span = $null
    foreach ($entry in @($query['Compare'])) {
        $found = @(Find-LambekFactSpan -Words $Words -Phrases @($entry['Words']))
        if ($found.Count -gt 0) { $comparison = $entry; $span = $found[0]; break }
    }
    if (-not $comparison) { return $null }
    $read = [bool[]]::new($Words.Count)
    for ($k = $span.Start; $k -lt $span.Start + $span.Length; $k++) { $read[$k] = $true }

    # The fact compared: said by the words ("ne", "sorti", "publie"), or by the comparison itself ("le plus age")
    $relations = @($Facts['Relations'] | Where-Object { @($_['Asks']) -contains 'when' -and -not ($_.Contains('Inverse') -and $_['Inverse']) })
    $chosen = @()
    if ($comparison.Contains('Property')) { $chosen = @($relations | Where-Object { "$($_['Property'])" -eq "$($comparison['Property'])" }) }
    else {
        foreach ($relation in $relations) {
            $cues = @(Find-LambekFactSpan -Words $Words -Phrases @($relation['Cues']) | Where-Object { -not $read[$_.Start] })
            if ($cues.Count -gt 0) { $chosen += $relation }
        }
    }
    if ($chosen.Count -eq 0) { return $null }

    $mentions = @($base.Find(($Words -join ' ')))
    foreach ($relation in $chosen) {
        $marks = [bool[]] $read.Clone()
        foreach ($cue in @(Find-LambekFactSpan -Words $Words -Phrases @($relation['Cues']))) {
            if ($marks[$cue.Start]) { continue }
            for ($k = $cue.Start; $k -lt $cue.Start + $cue.Length; $k++) { $marks[$k] = $true }
        }
        # Two names, the longest at each place, apart from each other and from the words read
        $names = [System.Collections.Generic.List[object]]::new()
        foreach ($mention in @($mentions | Sort-Object Start, { - $_.Length })) {
            $free = $true
            for ($k = $mention.Start; $k -lt $mention.Start + $mention.Length; $k++) { if ($marks[$k]) { $free = $false; break } }
            if (-not $free) { continue }
            if ($mention.Length -eq 1 -and $fillers.Contains($mention.Name)) { continue }
            $thing = Select-LambekFactThing -Mention $mention -Kinds @($relation['Subject'])
            if (-not $thing) { continue }
            $names.Add([pscustomobject]@{ Mention = $mention; Thing = $thing })
            for ($k = $mention.Start; $k -lt $mention.Start + $mention.Length; $k++) { $marks[$k] = $true }
        }
        if ($names.Count -ne 2 -or $names[0].Thing.Id -eq $names[1].Thing.Id) { continue }
        # Every other word: a question word, "ou", the kind of the things, small words
        $question = $false
        $others = @($Facts['Questions'].Values | ForEach-Object { @($_) })
        foreach ($other in @(Find-LambekFactSpan -Words $Words -Phrases $others)) {
            if ($marks[$other.Start]) { continue }
            $question = $true
            for ($k = $other.Start; $k -lt $other.Start + $other.Length; $k++) { $marks[$k] = $true }
        }
        $small = @(@($query['Or']) + @(@($relation['Subject']) | ForEach-Object { @($Facts['Kinds'][$_]) }))
        foreach ($other in @(Find-LambekFactSpan -Words $Words -Phrases $small)) {
            if ($marks[$other.Start]) { continue }
            for ($k = $other.Start; $k -lt $other.Start + $other.Length; $k++) { $marks[$k] = $true }
        }
        $left = @(for ($k = 0; $k -lt $Words.Count; $k++) { if (-not $marks[$k] -and -not $fillers.Contains($Words[$k])) { $k } })
        if ($left.Count -gt 0 -or -not ($question -or $Asked)) { continue }

        # The dates, one for each, compared as far as both are known
        $property = "$($relation['Property'])"
        $dates = @($names | ForEach-Object { @($_.Thing.Values($property)) })
        if ($dates.Count -ne 2) { return $null }
        $order = Compare-LambekFactDate -First $dates[0] -Second $dates[1]
        if ($null -eq $order -or $order -eq 0) { return $null }
        $lines = @()
        foreach ($name in $names) {
            $mention = [pscustomobject]@{ Name = $name.Mention.Name; Length = $name.Mention.Length; Surname = $false }
            $candidate = [pscustomobject]@{ Relation = $relation; Mention = $mention; Start = $name.Mention.Start; Things = @($name.Thing); Object = $null; Inverse = $false }
            $said = Get-LambekFactReply -Candidate $candidate -Base $base -Facts $Facts -Language $Language -Words $Words
            if (-not $said) { return $null }
            $fact = Add-LambekFactRead -Text $said.Reply -Language $Language -Core $said.Core -Thing $name.Thing.Id -Property $property -Bare $said.Bare
            $lines += "$($said.Bare)".TrimEnd('.')
        }
        $head = switch ("$($comparison['Order'])") {
            'before' { $(if ($order -lt 0) { $Facts['Yes'] } else { $Facts['No'] }) }
            'after' { $(if ($order -gt 0) { $Facts['Yes'] } else { $Facts['No'] }) }
            'which' { $(if ($order -lt 0) { $query['SayBefore'] } else { $query['SayAfter'] }) }
            'earliest' { $names[$(if ($order -lt 0) { 0 } else { 1 })].Thing.Label($Language) }
            'latest' { $names[$(if ($order -gt 0) { 0 } else { 1 })].Thing.Label($Language) }
        }
        if (-not $head) { return $null }
        # (inside the sentence, without their capital, but a name keeps its own)
        for ($k = 0; $k -lt 2; $k++) {
            if ($lines[$k].Length -gt 0 -and -not $lines[$k].StartsWith($names[$k].Thing.Label($Language))) { $lines[$k] = $lines[$k].Substring(0, 1).ToLowerInvariant() + $lines[$k].Substring(1) }
        }
        $reply = "$head : $($lines[0]) ; $($lines[1])$($Facts['According'])."
        if ($Language -ne 'fr') { $reply = "${head}: $($lines[0]); $($lines[1])$($Facts['According'])." }
        return [pscustomobject]@{ Language = $Language; Reply = $reply; Fact = $fact }
    }
    return $null
}

function Compare-LambekFactDate {
    # Which of two dates comes first, as far as both are known (the year, the month, the day): -1, 1, or 0 when they
    # are the same as far as that; nothing for a date that is not a date
    param([object] $First, [object] $Second)

    $parts = foreach ($date in $First, $Second) {
        $match = [regex]::Match("$($date.Value)", '^(-?)(\d+)-(\d{2})-(\d{2})$')
        if (-not $match.Success) { return $null }
        $year = [int] $match.Groups[2].Value
        if ($match.Groups[1].Value) { $year = - $year }
        $precision = 9
        if ("$($date.Extra)" -match '^\d+$') { $precision = [int] $date.Extra }
        if ($precision -lt 9) { return $null }
        , @($year, [int] $match.Groups[3].Value, [int] $match.Groups[4].Value, $precision)
    }
    $precision = [math]::Min($parts[0][3], $parts[1][3])
    $count = $precision - 8
    for ($k = 0; $k -lt $count; $k++) {
        if ($parts[0][$k] -lt $parts[1][$k]) { return -1 }
        if ($parts[0][$k] -gt $parts[1][$k]) { return 1 }
    }
    return 0
}

function Add-LambekFactRead {
    # A fact read in Wikidata, put on the board as read, with where it was read and the day of the data; "pourquoi ?"
    # says it
    param([string] $Text, [string] $Language, [string] $Core, [string] $Thing, [string] $Property, [string] $Bare)

    $base = Get-LambekFactBase
    $facts = (Get-LambekLexicon -Language $Language).Facts
    $entry = [pscustomobject]@{ Text = $Text; Form = $Text; Language = $Language; Core = $Core; Told = $base.Day; Source = 'wikidata'; Thing = $Thing; Property = $Property }
    [void] (Get-LambekBoard).Put($entry, 'read', 'wikidata', $base.Day, $Core, $false, $null, $Text, [int[]] @())
    if ($null -eq $script:FactReads) { $script:FactReads = [System.Collections.Generic.List[object]]::new() }
    $script:FactReads.Add([pscustomobject]@{ Source = $facts['Source']; Day = $base.Day; Line = $Bare; Id = $Thing })
    Set-LambekLastProof -Read @($script:FactReads)
    return $entry
}
