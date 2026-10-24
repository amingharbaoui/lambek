function Get-LambekFactBase {
    # What Lambek knows of the world (Data/Knowledge, written by tools/Get-LambekFacts.ps1), read once; nothing when
    # the file is not there
    if ($script:FactBase -is [LambekFacts]) { return $script:FactBase }
    if ($script:FactBase -eq $false) { return $null }
    $path = Join-Path $PSScriptRoot '../Data/Knowledge/wikidata.facts.gz'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $script:FactBase = $false; return $null }
    $script:FactBase = [LambekFacts]::Load([IO.Path]::GetFullPath($path))
    return $script:FactBase
}

function Find-LambekFactSpan {
    # Where one of the phrases is among the words, from a place on: the first place, the longest phrase there
    # (Before: the places a phrase may start at end there; To: where every phrase must end)
    param([string[]] $Words, [object[]] $Phrases, [int] $From = 0, [int] $To = -1, [int] $Before = -1)

    if ($To -lt 0) { $To = $Words.Count }
    if ($Before -lt 0) { $Before = $To }
    $found = [System.Collections.Generic.List[object]]::new()
    $split = @($Phrases | Where-Object { $_ } | ForEach-Object { , @("$_" -split ' ') } | Sort-Object { - $_.Count })
    for ($i = $From; $i -lt [math]::Min($To, $Before); $i++) {
        foreach ($phrase in $split) {
            if ($i + $phrase.Count -gt $To) { continue }
            $same = $true
            for ($k = 0; $k -lt $phrase.Count; $k++) { if ($Words[$i + $k] -ne $phrase[$k]) { $same = $false; break } }
            if ($same) { $found.Add([pscustomobject]@{ Start = $i; Length = $phrase.Count }); break }
        }
    }
    return $found.ToArray()
}

function Get-LambekFactGender {
    # The gender and number of a name or a noun as the treebanks used it ("Maroc": Masc, "Belgique": Fem,
    # "Etats-Unis": Plur), from the forms it was seen with; nothing when it was never seen. A few words take another
    # gender when they name a currency or the like (Facts.Genders: "livre")
    param([string] $Word, [string] $Language, [hashtable] $Facts)

    if ($Facts.Contains('Genders') -and $Facts['Genders'] -and $Facts['Genders'].Contains($Word.ToLowerInvariant())) { return "$($Facts['Genders'][$Word.ToLowerInvariant()])" }
    $model = Get-LambekFormModel -Language $Language
    if (-not $model) { return $null }
    if ($null -eq $script:FactGenders) { $script:FactGenders = @{} }
    $key = "$Language|$Word"
    if ($script:FactGenders.ContainsKey($key)) { return $script:FactGenders[$key] }
    # (the gender from every form seen; plural only for a name never seen in the singular: "Etats-Unis")
    $counts = @{ Masc = 0; Fem = 0; Sing = 0; Plur = 0 }
    $lemma = $Word.ToLowerInvariant()
    foreach ($upos in 'PROPN', 'NOUN') {
        foreach ($feats in @('Gender=Masc|Number=Sing', 'Gender=Fem|Number=Sing', 'Gender=Masc|Number=Plur', 'Gender=Fem|Number=Plur', 'Number=Plur', 'Number=Sing', 'Gender=Masc', 'Gender=Fem')) {
            $forms = $null
            if (-not $model.Paradigms.TryGetValue("$upos`t$lemma`t$feats", [ref] $forms)) { continue }
            $seen = 0
            foreach ($count in $forms.Values) { $seen += $count }
            if ($feats -match 'Gender=Masc') { $counts.Masc += $seen }
            if ($feats -match 'Gender=Fem') { $counts.Fem += $seen }
            if ($feats -match 'Number=Plur') { $counts.Plur += $seen }
            if ($feats -match 'Number=Sing') { $counts.Sing += $seen }
        }
    }
    $gender = $null
    if ($counts.Plur -gt 0 -and $counts.Sing -eq 0) { $gender = 'Plur' }
    elseif ($counts.Masc -gt 0 -and $counts.Masc -ge 0.75 * ($counts.Masc + $counts.Fem)) { $gender = 'Masc' }
    elseif ($counts.Fem -gt 0 -and $counts.Fem -ge 0.75 * ($counts.Masc + $counts.Fem)) { $gender = 'Fem' }
    $script:FactGenders[$key] = $gender
    return $gender
}

function Get-LambekFactPlace {
    # A name as a sentence of the language needs it: in French with its article ("la France"), after "de" ("de la
    # France", "du Japon", "d'Israel") and after "a" ("en France", "au Japon", "aux Etats-Unis", "a Cuba"): taken from
    # the words the user said before it when there are some ("du Nigeria"), else from the gender the treebanks give it
    # (Facts.Places). Nothing when neither tells: the sentence is then said without them. In English, the name, with
    # "the" when the user said it
    param([string] $Label, [string] $Language, [hashtable] $Facts, [string[]] $Before = @())

    $last = "$(@($Before | Select-Object -Last 1))"
    $places = $(if ($Facts.Contains('Places')) { $Facts['Places'] })
    if (-not $places) {
        $the = $(if ($last -eq 'the') { "the $Label" } else { $Label })
        return [pscustomobject]@{ The = $the; Of = $the; In = $the }
    }
    $vowel = [LambekFacts]::Plain($Label) -match '^[aeiouy]'
    $two = (@($Before | Select-Object -Last 2) -join ' ')
    $article = $null
    if ($two -and $places['Before'].Contains($two)) { $article = "$($places['Before'][$two])" }
    elseif ($last -and $places['Before'].Contains($last)) { $article = "$($places['Before'][$last])" }
    # Said without an article, or with "en" that does not tell the gender: the gender the treebanks give
    if ($article -in $null, 'none', 'en') {
        $gender = Get-LambekFactGender -Word (($Label -split '[ -]')[0]) -Language $Language -Facts $Facts
        if ($gender -eq 'Plur') { $article = 'les' }
        elseif ($vowel -and ($gender -or $article -eq 'en')) { $article = 'l' }
        elseif ($gender -eq 'Masc') { $article = 'le' }
        elseif ($gender -eq 'Fem') { $article = 'la' }
        elseif ($article -eq 'en') { $article = $(if ($vowel) { 'l' } else { 'la' }) }
        elseif ($article -eq 'none') { $article = $(if ($vowel) { 'none-vowel' } else { 'none' }) }
    }
    if (-not $article -or -not $places['Forms'].Contains($article)) { return $null }
    $forms = @($places['Forms'][$article])
    return [pscustomobject]@{ The = $forms[0] -f $Label; Of = $forms[1] -f $Label; In = $forms[2] -f $Label }
}

function Get-LambekFactAge {
    # The age of a person in whole years: at death, or today for a person with no death read. Nothing when a date is
    # not known to the day, is given twice, is before year 1, or when the person would be older than 120 today
    param([LambekThing] $Thing)

    $births = @($Thing.Values('P569'))
    $deaths = @($Thing.Values('P570'))
    if ($births.Count -ne 1 -or $deaths.Count -gt 1) { return $null }
    $dates = @($births) + @($deaths)
    if (@($dates | Where-Object { $_.Extra -ne '11' -or $_.Value -notmatch '^\d{4}-\d{2}-\d{2}$' }).Count -gt 0) { return $null }
    $born = [datetime]::ParseExact($births[0].Value, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    $dead = $deaths.Count -eq 1
    $end = $(if ($dead) { [datetime]::ParseExact($deaths[0].Value, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture) } else { (Get-LambekNow).Date })
    $years = $end.Year - $born.Year
    if ($end.Month -lt $born.Month -or ($end.Month -eq $born.Month -and $end.Day -lt $born.Day)) { $years-- }
    if ($years -lt 0 -or (-not $dead -and $years -gt 120)) { return $null }
    return [pscustomobject]@{ Years = $years; Dead = $dead }
}

function Format-LambekFactDate {
    # 1802-02-26 said as far as its precision goes: the day (11), the month (10), the year (9); less precise, nothing
    param([string] $Value, [string] $Precision, [hashtable] $Facts)

    if ($Value -notmatch '^(-?\d+)-(\d\d)-(\d\d)$') { return $null }
    $year = [long] $Matches[1]
    $month = [int] $Matches[2]
    $day = [int] $Matches[3]
    $dates = $Facts['Dates']
    $yearSaid = "$year"
    if ($year -le 0) { $yearSaid = $dates['BeforeEra'] -f [math]::Abs($year) }
    switch ([int] "0$Precision") {
        11 {
            if ($month -lt 1 -or $day -lt 1) { return $null }
            $name = $Facts['Months'][$month - 1]
            $number = "$day"
            if ($day -eq 1 -and $dates['First']) { $number = $dates['First'] }
            # (English says the month first: "on February 26, 1802")
            if ($dates['Day'] -like 'on *') { return $dates['Day'] -f "$name $day, $yearSaid" }
            return $dates['Day'] -f "$number $name $yearSaid"
        }
        10 {
            if ($month -lt 1) { return $null }
            return $dates['Month'] -f "$($Facts['Months'][$month - 1]) $yearSaid"
        }
        9 { return $dates['Year'] -f $yearSaid }
    }
    return $null
}

function Join-LambekFactList {
    param([string[]] $Items, [string] $And)
    $Items = @($Items | Where-Object { $_ })
    if ($Items.Count -le 1) { return "$($Items -join '')" }
    return (($Items[0..($Items.Count - 2)]) -join ', ') + " $And " + $Items[-1]
}

function Resolve-LambekFact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # "quelle est la capitale du Nigeria ?", "who wrote Hamlet?", "ou est ne Gandhi ?": one fact read in Wikidata.
    # Else a question made of several: "ou est ne l'auteur de Germinal ?", "Mozart est-il ne avant Beethoven ?",
    # "quelle est la ville la plus peuplee du Japon ?" (Resolve-LambekFactQuery)
    $base = Get-LambekFactBase
    if (-not $base) { return $null }
    $plain = [LambekFacts]::Plain($Text)
    $all = @($plain -split ' ' | Where-Object { $_ })
    if ($all.Count -eq 0 -or $all.Count -gt 24) { return $null }
    $asked = $Text.Trim().EndsWith('?')
    $first = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text)
    $languages = @(@($first) + @(Get-LambekAvailableLanguage | Where-Object { $_ -ne $first }) | Where-Object { (Get-LambekLexicon -Language $_).Facts })
    $read = Resolve-LambekFactReading -Plain $plain -Asked $asked -Languages $languages
    if ($read) { return $read }
    return Resolve-LambekFactQuery -Plain $plain -Asked $asked -Languages $languages
}

function Resolve-LambekFactReading {
    # One fact: only when every word of the question is read: the question word, the words of one fact, the name of
    # one thing, and small words. A word left over ("the largest", "and Italy", "in 1500") and nothing is said: what is
    # asked is then more than one fact. Pin: the name of a thing already known (found by a question around this one:
    # "ou est ne [l'auteur de Germinal]"), which names that thing only
    param([string] $Plain, [bool] $Asked, [string[]] $Languages, [string] $PinName, [object] $Pin)

    $base = Get-LambekFactBase
    $plain = $Plain
    $asked = $Asked
    $all = @($plain -split ' ' | Where-Object { $_ })
    if ($all.Count -eq 0) { return $null }
    $mentions = @($base.Find($plain) | ForEach-Object {
            if ($Pin -and $_.Name -ceq $PinName) { [LambekNameMention] @{ Start = $_.Start; Length = $_.Length; Name = $_.Name; Things = [LambekThing[]] @($Pin); Surname = $false } }
            elseif ($Pin -and $_.Surname) { }
            else { $_ }
        })
    if ($mentions.Count -eq 0) { return $null }

    foreach ($language in $Languages) {
        $facts = (Get-LambekLexicon -Language $language).Facts
        # Asking and thanking around the question are not the question ("dis-moi", "s'il te plait")
        $from = 0
        $to = $all.Count
        foreach ($pass in 1..2) {
            $open = @(Find-LambekFactSpan -Words $all -Phrases @($facts['Openers']) -From $from -To $to -Before ($from + 1))
            if ($open.Count -gt 0) { $from += $open[0].Length }
            $close = @(Find-LambekFactSpan -Words $all -Phrases @($facts['Closers']) -From ([math]::Max($from, $to - 3)) -To $to | Where-Object { $_.Start + $_.Length -eq $to })
            if ($close.Count -gt 0) { $to = $close[0].Start }
        }
        if ($to -le $from) { continue }
        $words = [string[]] @($all[$from..($to - 1)])

        # The question word, at the start or at the end ("Mozart est ne ou ?")
        $kind = $null
        $question = $null
        foreach ($name in @($facts['Questions'].Keys | Sort-Object)) {
            foreach ($at in @(0, -1)) {
                $spans = @(Find-LambekFactSpan -Words $words -Phrases @($facts['Questions'][$name]))
                $span = $(if ($at -eq 0) { @($spans | Where-Object Start -EQ 0) } else { @($spans | Where-Object { $_.Start + $_.Length -eq $words.Count }) }) | Sort-Object Length -Descending | Select-Object -First 1
                if ($span -and (-not $question -or $span.Length -gt $question.Length)) { $kind = $name; $question = $span }
            }
        }
        if (-not $question -and -not $asked) { continue }
        $fillers = [System.Collections.Generic.HashSet[string]]::new([string[]] @($facts['Fillers']), [StringComparer]::Ordinal)

        $candidates = [System.Collections.Generic.List[object]]::new()
        foreach ($relation in @($facts['Relations'])) {
            $inverse = $relation.Contains('Inverse') -and $relation['Inverse']
            $cues = @(Find-LambekFactSpan -Words $words -Phrases @($relation['Cues']))
            foreach ($cue in @($cues | Select-Object -First 1)) {
                foreach ($mention in $mentions) {
                    $start = $mention.Start - $from
                    if ($start -lt 0 -or $start + $mention.Length -gt $words.Count) { continue }
                    # (the name is not the word of the fact, nor the question word)
                    if (@($cues | Where-Object { -not ($start -lt $_.Start + $_.Length -and $_.Start -lt $start + $mention.Length) }).Count -eq 0) { continue }
                    if ($question -and $start -lt $question.Start + $question.Length -and $question.Start -lt $start + $mention.Length) { continue }
                    $things = @($mention.Things | Where-Object { $thing = $_; @($relation['Subject'] | Where-Object { $thing.Is($_) }).Count -gt 0 })
                    if ($things.Count -eq 0) { continue }
                    # A name of one word that is also a word of the question is that word ("est", "capitale")
                    if ($mention.Length -eq 1 -and $fillers.Contains($mention.Name)) { continue }

                    # Every word is read: the question word, the fact, the name, the kind of thing named, small words;
                    # in a yes-no question, the name of the value asked about too
                    $read = [bool[]]::new($words.Count)
                    foreach ($span in @($question, [pscustomobject]@{ Start = $start; Length = $mention.Length }) | Where-Object { $_ }) {
                        for ($k = $span.Start; $k -lt $span.Start + $span.Length; $k++) { $read[$k] = $true }
                    }
                    # (every word of the fact: "quelle langue parle-t-on")
                    foreach ($span in $cues) {
                        if ($span.Start -lt $start + $mention.Length -and $start -lt $span.Start + $span.Length) { continue }
                        for ($k = $span.Start; $k -lt $span.Start + $span.Length; $k++) { $read[$k] = $true }
                    }
                    $nouns = @()
                    foreach ($subject in @($relation['Subject'])) { $nouns += @($facts['Kinds'][$subject]) }
                    if ($relation.Contains('Kind')) { $nouns += @($relation['Kind']) }
                    $needs = @()
                    if ($relation.Contains('Needs')) { $needs = @($relation['Needs']) }
                    foreach ($span in @(Find-LambekFactSpan -Words $words -Phrases (@($nouns) + @($needs)))) {
                        for ($k = $span.Start; $k -lt $span.Start + $span.Length; $k++) { $read[$k] = $true }
                    }
                    if ($needs.Count -gt 0 -and @(Find-LambekFactSpan -Words $words -Phrases $needs).Count -eq 0 -and $kind -ne 'country') { continue }
                    $object = $null
                    $left = @(for ($k = 0; $k -lt $words.Count; $k++) { if (-not $read[$k] -and -not $fillers.Contains($words[$k])) { $k } })
                    if ($left.Count -gt 0 -and -not $inverse -and $kind -in $null, 'yesno') {
                        # Yes or no: "Paris est-elle la capitale de la France ?", the rest is the value asked about (not
                        # after "quand" or "ou": "quand est mort le peintre de la Joconde ?" asks no yes or no)
                        $other = @($mentions | Where-Object {
                                $_.Start - $from -le $left[0] -and $_.Start - $from + $_.Length -gt $left[-1] -and -not $_.Surname -and
                                ($_.Start - $from + $_.Length -le $start -or $_.Start - $from -ge $start + $mention.Length)
                            } | Sort-Object Length -Descending | Select-Object -First 1)
                        if ($other.Count -eq 0) { continue }
                        for ($k = $other[0].Start - $from; $k -lt $other[0].Start - $from + $other[0].Length; $k++) { $read[$k] = $true }
                        $left = @(for ($k = 0; $k -lt $words.Count; $k++) { if (-not $read[$k] -and -not $fillers.Contains($words[$k])) { $k } })
                        if ($left.Count -gt 0) { continue }
                        $object = $other[0]
                    }
                    elseif ($left.Count -gt 0) { continue }
                    $wanted = $kind
                    if ($object) { $wanted = 'yesno' }
                    elseif (-not $wanted -or $wanted -eq 'yesno') { $wanted = 'what' }
                    if ($wanted -notin @($relation['Asks'])) { continue }
                    $objectStart = $(if ($object) { $object.Start - $from } else { -1 })
                    $candidates.Add([pscustomobject]@{ Relation = $relation; Mention = $mention; Start = $start; Things = $things; Object = $object; ObjectStart = $objectStart; Inverse = $inverse })
                }
            }
        }
        if ($candidates.Count -eq 0) { continue }

        # The longest name read; between readings of the same name, the plain one before its inverse
        $longest = ($candidates | Measure-Object -Property { $_.Mention.Length } -Maximum).Maximum
        $kept = @($candidates | Where-Object { $_.Mention.Length -eq $longest })
        $plainOnes = @($kept | Where-Object { -not $_.Inverse })
        if ($plainOnes.Count -gt 0) { $kept = $plainOnes }
        $reply = $null
        foreach ($candidate in $kept) {
            $said = Get-LambekFactReply -Candidate $candidate -Base $base -Facts $facts -Language $language -Words $words
            if (-not $said) { continue }
            # Two readings that say different things: it is not known which was asked
            if ($reply -and $reply.Reply -cne $said.Reply) { return $null }
            if (-not $reply) { $reply = $said }
        }
        if (-not $reply) { return $null }

        # What the user told comes first. Told about the same fact in this conversation, it is said, then what Wikidata
        # says; told something else about the same name ("Minou est un chat"), the conversation answers, not Wikidata
        $name = $reply.Candidate.Mention.Name
        # (by the words of the fact itself: "est" says nothing of which fact)
        $cues = @($reply.Candidate.Relation['Cues'] | ForEach-Object { "$_" } | Where-Object { -not $fillers.Contains($_) })
        $toldName = @((Get-LambekTold).ToArray() | Where-Object { " $([LambekFacts]::Plain("$($_.Text)")) ".Contains(" $name ") })
        $toldSame = @($toldName | Where-Object {
                $plainTold = " $([LambekFacts]::Plain("$($_.Text)")) "
                @($cues | Where-Object { $plainTold.Contains(" $_ ") }).Count -gt 0
            })
        if ($toldName.Count -gt 0 -and $toldSame.Count -eq 0) { return $null }
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($fact in $toldSame) { $lines.Add(($facts['Told'] -f "$($fact.Text)".Trim().TrimEnd('.'))) }
        $lines.Add($reply.Reply)

        # On the board, as read, with where it was read and the day of the data; "pourquoi ?" says it
        $entry = [pscustomobject]@{
            Text = $reply.Reply; Form = $reply.Reply; Language = $language; Core = $reply.Core; Told = $base.Day
            Source = 'wikidata'; Thing = $reply.Thing.Id; Property = $reply.Candidate.Relation['Property']
        }
        [void] (Get-LambekBoard).Put($entry, 'read', 'wikidata', $base.Day, $reply.Core, $false, $null, $reply.Reply, [int[]] @())
        Set-LambekLastProof -Read @([pscustomobject]@{ Source = $facts['Source']; Day = $base.Day; Line = $reply.Bare; Id = $reply.Thing.Id })
        return [pscustomobject]@{ Language = $language; Reply = ($lines -join "`n"); Fact = $entry }
    }
    return $null
}

function Get-LambekFactReply {
    # The sentence of one reading: the thing named, the values of its fact, said with the words of the language
    param([pscustomobject] $Candidate, [LambekFacts] $Base, [hashtable] $Facts, [string] $Language, [string[]] $Words)

    $relation = $Candidate.Relation
    $property = "$($relation['Property'])"
    $mention = $Candidate.Mention
    # The thing: the best known of those the name names, when it is far better known than the next one; a person
    # named by the last word of their name only when that is clear beyond doubt
    $things = @($Candidate.Things)
    $ratio = $(if ($mention.Surname) { 3 } else { 2 })
    if ($mention.Surname -and ($property -eq 'Description' -or $things[0].Links -lt 50)) { return $null }
    if ($things.Count -gt 1 -and $things[0].Links -lt $ratio * $things[1].Links) { return $null }
    $thing = $things[0]
    $label = $thing.Label($Language)
    $female = @($thing.Values('P21') | Where-Object { $_.Value -in 'Q6581072', 'Q1052281' }).Count -gt 0
    $template = "$($relation['Say'])"
    if ($Candidate.Object) { $template = "$($relation['SayYes'])" }
    $fill = @{ label = $label; e = $(if ($female) { 'e' } else { '' }) }
    $core = $null

    if ($property -eq 'Description') {
        $description = $thing.Description($Language)
        if (-not $description) { return $null }
        $fill.description = $description
        $core = "wikidata($($thing.Id), description)"
    }
    elseif ($property -eq 'Age') {
        # "a quel age est mort Mozart ?", "how old is Barack Obama?": the years between birth and death, or until today;
        # only from dates known to the day, one of each (a person with no death read is taken as living)
        $age = Get-LambekFactAge -Thing $thing
        if ($null -eq $age) { return $null }
        if (-not $age.Dead) { $template = "$($relation['SayAlive'])" }
        $fill.age = $age.Years
        $core = "wikidata($($thing.Id), age, $($age.Years))"
    }
    elseif ($Candidate.Inverse) {
        # "Paris est la capitale de quel pays ?", "qu'a ecrit Victor Hugo ?": the things whose fact points at this one
        $subjects = @($Base.Having($property, $thing.Id) | Where-Object { $_.Labels.Count -gt 0 } | Select-Object -First 3)
        if ($subjects.Count -eq 0) { return $null }
        $names = @($subjects | ForEach-Object { $_.Label($Language) })
        $fill.value = Join-LambekFactList -Items $names -And $Facts['And']
        if ($template.Contains('{valueof}')) {
            if ($subjects.Count -ne 1) { return $null }
            $place = Get-LambekFactPlace -Label $names[0] -Language $Language -Facts $Facts
            if (-not $place) { $template = "$($relation['Bare'])" } else { $fill.valueof = $place.Of }
        }
        $core = "wikidata($($thing.Id), $property, inverse)"
    }
    else {
        $values = @($thing.Values($property))
        if ($values.Count -eq 0) { return $null }
        $shape = $values[0].Value
        if ($shape -match '^Q\d+$') {
            $named = @($values | ForEach-Object { $Base.Thing($_.Value) } | Where-Object { $_ -and $_.Labels.Count -gt 0 })
            if ($named.Count -eq 0) { return $null }
            # Yes or no: is the thing asked about one of the values?
            if ($Candidate.Object) {
                $asked = @($Candidate.Object.Things | Where-Object { $_.Id -in @($named | ForEach-Object Id) })
                $yes = $asked.Count -gt 0
                if (-not $yes) { $template = "$($relation['SayNo'])" }
                if (-not $template) { return $null }
                $fill.object = $(if ($yes) { $asked[0].Label($Language) } else { @($Candidate.Object.Things)[0].Label($Language) })
                # (with the small words said before it: "membre de l'Union europeenne", "a member of the European Union")
                $said = @()
                if ($Candidate.PSObject.Properties['ObjectStart'] -and $Candidate.ObjectStart -gt 0) { $said = @($Words[([math]::Max(0, $Candidate.ObjectStart - 2))..($Candidate.ObjectStart - 1)]) }
                $objectPlace = Get-LambekFactPlace -Label $fill.object -Language $Language -Facts $Facts -Before $said
                $fill.objectof = $(if ($objectPlace) { $objectPlace.Of } else { $fill.object })
            }
            # (many values: the best known of them, Limit: the actors of a film, what a country is a member of)
            if ($relation.Contains('Limit') -and $named.Count -gt [int] $relation['Limit']) { $named = @($named | Sort-Object { - $_.Links }, Id | Select-Object -First ([int] $relation['Limit'])) }
            $labels = @($named | ForEach-Object { $_.Label($Language) })
            $fill.value = Join-LambekFactList -Items $labels -And $Facts['And']
            $fill.bare = $fill.value
            if ($named.Count -gt 1 -and $relation.Contains('Plural')) { $template = "$($relation['Plural'])" }
            # With their articles, in French ("le yen", "la livre sterling"), where the sentence needs them
            if ($template -match '\{(the|valuein|valueof)\}') {
                $places = @($labels | ForEach-Object { Get-LambekFactPlace -Label $_ -Language $Language -Facts $Facts })
                if (@($places | Where-Object { -not $_ }).Count -gt 0 -or $places.Count -eq 0) {
                    if (-not $relation.Contains('Bare')) { return $null }
                    $template = "$($relation['Bare'])"
                }
                else {
                    $fill.the = Join-LambekFactList -Items @($places | ForEach-Object The) -And $Facts['And']
                    $fill.valuein = Join-LambekFactList -Items @($places | ForEach-Object In) -And $Facts['And']
                    $fill.valueof = Join-LambekFactList -Items @($places | ForEach-Object Of) -And $Facts['And']
                }
            }
            $core = "wikidata($($thing.Id), $property, $(@($named | ForEach-Object Id) -join ' '))"
        }
        elseif ($relation.Contains('Unit')) {
            # A measure (an area, a length, a height): the largest of those given, as Wikidata gives several (the radius
            # of a planet at its equator and at its poles)
            $numbers = @($values | ForEach-Object { [decimal] $_.Value } | Sort-Object -Descending)
            $fill.measure = Format-LambekFactNumber -Number $numbers[0] -Facts $Facts
            $core = "wikidata($($thing.Id), $property, $($numbers[0]))"
        }
        elseif ($property -eq 'P1082') {
            $number = [decimal] $values[0].Value
            $digits = $number.ToString('#,0', [cultureinfo]::InvariantCulture) -replace ',', $Facts['Number']['Group']
            $fill.number = $(if ($values[0].Extra) { $Facts['Number']['Of'] -f $digits, $values[0].Extra } else { $Facts['Number']['OfUndated'] -f $digits })
            $core = "wikidata($($thing.Id), $property, $($values[0].Value))"
        }
        else {
            # A date: two dates given for the same thing, and it is not known which one is right
            if ($values.Count -gt 1) { return $null }
            $date = Format-LambekFactDate -Value $values[0].Value -Precision $values[0].Extra -Facts $Facts
            if (-not $date) { return $null }
            $fill.date = $date
            $core = "wikidata($($thing.Id), $property, $($values[0].Value))"
        }
    }

    # The thing named, as a French sentence needs it, from the words said before it ("du Nigeria")
    if ($template -match '\{(of|in|subject)\}') {
        $before = @()
        if ($Candidate.Start -gt 0) { $before = @($Words[([math]::Max(0, $Candidate.Start - 2))..($Candidate.Start - 1)]) }
        # (a name read with its article is said with it: "the capital of the United States")
        $first = "$(@("$($Candidate.Mention.Name)" -split ' ')[0])"
        $articles = $(if ($Facts.Contains('Places')) { $Facts['Places']['Before'] } else { @{ the = 'the' } })
        if ("$($Candidate.Mention.Name)".Contains(' ') -and $articles.Contains($first)) { $before = @($before) + @($first) }
        $place = Get-LambekFactPlace -Label $label -Language $Language -Facts $Facts -Before $before
        if (-not $place) {
            # (in a yes or no, the bare sentence of that answer: BareYes, BareNo)
            $bare = 'Bare'
            if ($Candidate.Object) { $bare = $(if ($template -ceq "$($relation['SayNo'])") { 'BareNo' } else { 'BareYes' }) }
            if (-not $relation.Contains($bare)) { return $null }
            $template = "$($relation[$bare])"
        }
        else { $fill.of = $place.Of; $fill.in = $place.In; $fill.subject = $place.The }
    }
    if (-not $template) { return $null }
    $sentence = [regex]::Replace($template, '\{(\w+)\}', { param($m) $name = $m.Groups[1].Value; if ($fill.ContainsKey($name)) { "$($fill[$name])" } else { $m.Value } })
    if ($sentence -match '\{\w+\}') { return $null }
    $sentence = $sentence.Substring(0, 1).ToUpperInvariant() + $sentence.Substring(1)
    return [pscustomobject]@{ Reply = $sentence + $Facts['According'] + '.'; Bare = "$sentence."; Thing = $thing; Core = $core; Candidate = $Candidate }
}
