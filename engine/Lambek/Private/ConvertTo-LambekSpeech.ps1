function ConvertTo-LambekSpeech {
    [CmdletBinding()]
    param(
        # What was found: yes, no, or what is supposed (usualyes, usualno)
        [Parameter(Mandatory)]
        [ValidateSet('yes', 'no', 'usualyes', 'usualno')]
        [string] $Verdict,

        # What it is about, as Lambek says it: "Socrate est mortel", "vous etes mortel"
        [Parameter(Mandatory)]
        [string] $Conclusion,

        # What it rests on: the things told, each with how it was read
        [Parameter(Mandatory)]
        [object[]] $Premises,

        [Parameter(Mandatory)]
        [string] $Language,

        # The conversation, for not saying it the same way twice in a row (each chat has its own)
        [object] $Key,

        # Every way of saying it, with what the listener read and what each satellite measured
        [switch] $All
    )

    # Lambek says an answer in its own sentence, made from what it means: the conclusion, what it rests on in the
    # order of the reasoning (Socrate is a man, every man is mortal), and the ways the language has to tie them
    # ("donc", "car", "puisque", ":"), to say again someone already said ("c'est un homme", "il"), and to join.
    # Every way is built. Each is then read by a second Lambek that gets the text only, never the meaning: it must
    # read back exactly the same conclusion and the same reasons, nothing more, in one way only, and find again that
    # the conclusion follows from them. The ways it reads are weighed by satellites (how the language sounds, learned
    # from free corpora; brevity; the answer first; no name said twice), fused as Lambek fuses its scorers. When no
    # way is read right, nothing is returned: the answer is said as before, in lines
    $data = Get-LambekSpeechData -Language $Language
    if (-not $data -or $Premises.Count -lt 1 -or $Premises.Count -gt 3) { return $null }

    # What the listener must read: the conclusion and each reason, as Lambek says them, read as Lambek's own words
    $said = Read-LambekCategorySentence -Sentence (ConvertTo-LambekSpeechPlain -Text $Conclusion) -Language $Language -Listener -Strict
    if (-not $said) { return $null }
    # (inside an answer only a name keeps its capital: "Yes, you are mortal")
    $Conclusion = $Conclusion.Trim().TrimEnd('.')
    if (-not ($said.Individual -and "$($said.Individual.Key)".StartsWith('name:'))) { $Conclusion = $Conclusion.Substring(0, 1).ToLowerInvariant() + $Conclusion.Substring(1) }
    $reasons = [System.Collections.Generic.List[object]]::new()
    foreach ($premise in $Premises) {
        $text = (Format-LambekFact -Fact $premise.Fact -Language $Language -Register 'vous' -Bare).Trim().TrimEnd('.').Trim()
        $item = Read-LambekCategorySentence -Sentence (ConvertTo-LambekSpeechPlain -Text $text) -Language $Language -Listener
        if (-not $item) { return $null }
        # (a sentence starts with a capital; inside an answer only a name keeps it)
        if (-not ($item.Individual -and "$($item.Individual.Key)".StartsWith('name:'))) { $text = $text.Substring(0, 1).ToLowerInvariant() + $text.Substring(1) }
        $reasons.Add([pscustomobject]@{ Text = $text; Item = $item })
    }
    # (what was told as it is asked is no reason to give: "Tweety ne vole pas : Tweety ne vole pas")
    $signature = Get-LambekCategorySignature -Item $said
    if (@($reasons | Where-Object { (Get-LambekCategorySignature -Item $_.Item) -ceq $signature }).Count -gt 0) { return $null }
    $ordered = @(Get-LambekSpeechOrder -Reasons $reasons.ToArray() -Conclusion $said)
    $meaning = [pscustomobject]@{
        Verdict    = $Verdict
        Conclusion = Get-LambekCategorySignature -Item $said
        Reasons    = (@($ordered | ForEach-Object { Get-LambekCategorySignature -Item $_.Item } | Sort-Object) -join "`n")
    }

    # (a part said the same way in many ways of saying it is read once)
    $script:SpeechReadings = @{}
    $candidates = @(Get-LambekSpeechCandidate -Verdict $Verdict -Conclusion ([pscustomobject]@{ Text = $Conclusion; Item = $said }) -Reasons $ordered -Language $Language)
    if ($candidates.Count -eq 0) { return $null }
    Measure-LambekSpeech -Candidates $candidates -Language $Language
    $check = {
        param($candidate)
        if (-not $candidate.PSObject.Properties['Right']) {
            $heard = Read-LambekSpeech -Text $candidate.Text -Language $Language
            $right = $null -ne $heard -and $heard.Verdict -eq $meaning.Verdict -and $heard.Conclusion -ceq $meaning.Conclusion -and $heard.Reasons -ceq $meaning.Reasons -and $heard.Follows
            $candidate | Add-Member -NotePropertyName Heard -NotePropertyValue $heard
            $candidate | Add-Member -NotePropertyName Right -NotePropertyValue $right
        }
        return $candidate.Right
    }
    # (every way, read, when they are asked for: to fit the satellites on answers known to be the best)
    if ($All -or $null -ne $script:SpeechCapture) {
        foreach ($candidate in $candidates) { [void] (& $check $candidate) }
        if ($All) { return $candidates }
        $script:SpeechCapture.Add($candidates)
    }
    if ($null -eq $Key) { $Key = Get-LambekTold }
    return Select-LambekSpeech -Candidates $candidates -Language $Language -Key $Key -Check $check
}

function Get-LambekSpeechData {
    param([string] $Language)

    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    if (-not $dialogue -or -not $dialogue['Speech']) { return $null }
    return $dialogue['Speech']
}

function ConvertTo-LambekSpeechPlain {
    param([string] $Text)

    # As a sentence is read: a comma only marks a pause
    return ((("$Text".Trim().TrimEnd('.')) -replace ',', ' ') -replace '\s+', ' ').Trim()
}

function Get-LambekSpeechOrder {
    param([object[]] $Reasons, [pscustomobject] $Conclusion)

    # The reasons in the order of the reasoning: first what is said of the one the answer is about, then each rule
    # whose kind is already reached ("Minou est un chat", "les chats sont des felins", "les felins sont des animaux").
    # Among those that can come next, the first told
    $reached = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (-not $Conclusion.Individual -and $Conclusion.Subject) { foreach ($atom in $Conclusion.Subject.Atoms) { [void] $reached.Add($atom) } }
    $left = [System.Collections.Generic.List[object]]::new($Reasons)
    while ($left.Count -gt 0) {
        $next = $null
        foreach ($reason in $left) {
            $item = $reason.Item
            if ($item.Individual) { $next = $reason; break }
            if ($item.Subject -and @($item.Subject.Atoms | Where-Object { -not $reached.Contains($_) }).Count -eq 0) { $next = $reason; break }
        }
        if (-not $next) { $next = $left[0] }
        [void] $left.Remove($next)
        foreach ($atom in @($next.Item.Predicate.Atoms)) { [void] $reached.Add($atom) }
        $next
    }
}

function Get-LambekSpeechMention {
    param([pscustomobject] $Clause, [string] $Gender, [hashtable] $Data)

    # The ways of saying a clause about one already named: as it is, then with "c'est", "il", "elle"
    $ways = [System.Collections.Generic.List[object]]::new()
    $ways.Add([pscustomobject]@{ Text = $Clause.Text; Again = $false })
    $subject = "$($Clause.Item.Written.Subject)"
    if (-not $subject -or -not $Clause.Text.StartsWith("$subject ", [System.StringComparison]::OrdinalIgnoreCase)) { return $ways.ToArray() }
    $rest = $Clause.Text.Substring($subject.Length + 1)
    foreach ($rule in @($Data['Again'])) {
        $match = [regex]::Match($rest, "$($rule['From'])")
        if (-not $match.Success) { continue }
        $text = $match.Result("$($rule['To'])")
        if ($rule['Pronoun']) {
            if (-not $Gender -or -not $Data['Pronouns'] -or -not $Data['Pronouns'][$Gender]) { continue }
            $text = $text.Replace('{p}', "$($Data['Pronouns'][$Gender])")
        }
        $ways.Add([pscustomobject]@{ Text = $text; Again = $true })
    }
    return $ways.ToArray()
}

function Get-LambekSpeechCandidate {
    param([string] $Verdict, [pscustomobject] $Conclusion, [object[]] $Reasons, [string] $Language)

    # Every way of saying it: each frame, each way of joining the reasons, and each way of saying again the one the
    # answer is about once it is named
    $data = Get-LambekSpeechData -Language $Language
    $one = $Conclusion.Item.Individual
    $gender = $null
    if ($one -and $one.Key -ne 'speaker') {
        $genders = @(foreach ($reason in $Reasons) {
                # (only what one is says it: "Moby n'est pas un poisson" says nothing of Moby)
                if (-not $reason.Item.Individual -or $reason.Item.Individual.Key -ne $one.Key -or $reason.Item.Kind -ne 'is') { continue }
                foreach ($rule in @($data['Gender'])) { if ("$($reason.Item.Written.Predicate)" -match "$($rule[0])") { "$($rule[1])" } }
            })
        $genders = @($genders | Sort-Object -Unique)
        if ($genders.Count -eq 1) { $gender = $genders[0] }
    }
    $about = { param($clause) $one -and $one.Key -ne 'speaker' -and $clause.Item.Individual -and $clause.Item.Individual.Key -eq $one.Key }
    $conclusion = [pscustomobject]@{ Text = $Conclusion.Text; Item = $Conclusion.Item; Conclusion = $true }
    $reasons = @($Reasons | ForEach-Object { [pscustomobject]@{ Text = $_.Text; Item = $_.Item; Conclusion = $false } })
    foreach ($frame in @($data['Frames'])) {
        $order = $(if ($frame['Reasons'] -eq 'before') { @($reasons) + @($conclusion) } else { @($conclusion) + @($reasons) })
        # The ways of saying each clause, in the order they are said: the first one about the one named says the name
        $named = $false
        $choices = @(foreach ($clause in $order) {
                if ((& $about $clause) -and $named) { , @(Get-LambekSpeechMention -Clause $clause -Gender $gender -Data $data) }
                else { , @([pscustomobject]@{ Text = $clause.Text; Again = $false }) }
                if (& $about $clause) { $named = $true }
            })
        $join = $data['Joins'][$frame['Join']]
        foreach ($picked in Get-LambekSpeechProduct -Choices $choices) {
            $texts = @($picked | ForEach-Object { $_.Text })
            $again = @($picked | Where-Object { $_.Again }).Count
            $c = $(if ($frame['Reasons'] -eq 'before') { $texts[-1] } else { $texts[0] })
            $p = @($(if ($frame['Reasons'] -eq 'before') { $texts[0..($texts.Count - 2)] } else { $texts[1..($texts.Count - 1)] }))
            foreach ($last in @($join['Last'])) {
                $joined = $p[-1]
                if ($p.Count -gt 1) { $joined = ($p[0..($p.Count - 2)] -join "$($join['Between'])") + "$last" + $p[-1] }
                $text = "$($frame['Text'])".Replace('{V}', "$($data['Verdicts'][$Verdict])").Replace('{C}', $c).Replace('{P}', $joined)
                foreach ($rule in @($data['Elide'])) { $text = [regex]::Replace($text, "$($rule[0])", "$($rule[1])") }
                $text = $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1)
                # (how many times the name is said again where it could have been said shortly)
                $mentions = @($order | Where-Object { & $about $_ }).Count
                [pscustomobject]@{
                    Text    = $text
                    Frame   = "$($frame['Name'])"
                    First   = $frame['Reasons'] -ne 'before'
                    Repeats = [math]::Max(0, $mentions - 1 - $again)
                    Mentions = $mentions
                }
            }
        }
    }
}

function Get-LambekSpeechProduct {
    param([object[]] $Choices)

    # Every way of taking one of each, in order
    $ways = [System.Collections.Generic.List[object[]]]::new()
    $ways.Add([object[]] @())
    foreach ($options in $Choices) {
        $next = [System.Collections.Generic.List[object[]]]::new()
        foreach ($way in $ways) { foreach ($option in @($options)) { $next.Add([object[]] (@($way) + @($option))) } }
        $ways = $next
    }
    foreach ($way in $ways) { , $way }
}

function Read-LambekSpeech {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Language
    )

    # The second Lambek: it has the text, nothing else. It finds the answer word, which part is the conclusion and
    # which the reasons (by the words that tie them: "donc" before the conclusion, "car", "puisque", ":" before the
    # reasons), cuts the reasons where they are joined, says again who "c'est", "il", "elle" are (the one named before,
    # when there is only one), and reads each part with the grammar. Every way of cutting the reasons that reads is
    # followed: if two read differently, the text is ambiguous and nothing is read. Then it reasons on what it read:
    # does the conclusion follow from the reasons?
    $data = Get-LambekSpeechData -Language $Language
    if (-not $data) { return $null }
    $listen = $data['Listener']
    $rest = $Text.Trim()
    if ($rest.EndsWith('.')) { $rest = $rest.Substring(0, $rest.Length - 1) }
    $verdict = $null
    foreach ($entry in @($data['Verdicts'].GetEnumerator() | Sort-Object { - "$($_.Value)".Length }, { $_.Key })) {
        foreach ($separator in @($listen['Separators'])) {
            $head = "$($entry.Value)$separator"
            if ($rest.StartsWith($head, [System.StringComparison]::OrdinalIgnoreCase)) { $verdict = $entry.Key; $rest = $rest.Substring($head.Length); break }
        }
        if ($verdict) { break }
    }
    if (-not $verdict) { return $null }

    # The conclusion and the reasons
    $conclusion = $null
    $because = $null
    $first = $true
    foreach ($marker in @($listen['Reasons'])) {
        $at = $rest.IndexOf("$marker", [System.StringComparison]::OrdinalIgnoreCase)
        if ($at -gt 0) { $conclusion = $rest.Substring(0, $at); $because = $rest.Substring($at + "$marker".Length); break }
    }
    if (-not $because) {
        foreach ($marker in @($listen['Conclusion'])) {
            $at = $rest.IndexOf("$marker", [System.StringComparison]::OrdinalIgnoreCase)
            if ($at -gt 0) { $because = $rest.Substring(0, $at); $conclusion = $rest.Substring($at + "$marker".Length); $first = $false; break }
        }
    }
    if (-not $because -or -not $conclusion) { return $null }

    # Where the reasons may be cut, and every way of cutting them
    $joins = @($listen['Joins'] | Sort-Object { - "$_".Length }, { "$_" } | ForEach-Object { [regex]::Escape("$_") })
    $pieces = [regex]::Split($because, "($($joins -join '|'))")
    $parts = @(for ($i = 0; $i -lt $pieces.Count; $i += 2) { $pieces[$i] })
    $glue = @(for ($i = 1; $i -lt $pieces.Count; $i += 2) { $pieces[$i] })
    if ($parts.Count -gt 8) { return $null }
    $readings = [System.Collections.Generic.Dictionary[string, object]]::new()
    for ($mask = 0; $mask -lt [math]::Pow(2, $parts.Count - 1); $mask++) {
        $clauses = [System.Collections.Generic.List[string]]::new()
        $current = $parts[0]
        for ($i = 1; $i -lt $parts.Count; $i++) {
            if ($mask -band (1 -shl ($i - 1))) { $clauses.Add($current); $current = $parts[$i] } else { $current += $glue[$i - 1] + $parts[$i] }
        }
        $clauses.Add($current)
        $heard = Read-LambekSpeechClause -Conclusion $conclusion -Reasons $clauses.ToArray() -First:$first -Language $Language
        if ($heard -and -not $readings.ContainsKey($heard.Key)) { $readings[$heard.Key] = $heard }
    }
    if ($readings.Count -ne 1) { return $null }
    $heard = @($readings.Values)[0]

    # What follows from what was read: the conclusion, sure, from the reasons (what is supposed is only read)
    $follows = $true
    if ($verdict -in 'yes', 'no') {
        $atoms = @{}
        $statements = [LambekCategoryStatement[]] @($heard.Items | ForEach-Object { ConvertTo-LambekCategoryStatement -Item $_ -Atoms $atoms })
        $asks = @{ is = 'askis', $false; isnot = 'askis', $true; does = 'askdoes', $false; doesnot = 'askdoes', $true; all = 'askall', $false; no = 'askno', $false; some = 'asksome', $false; somenot = 'asksomenot', $false }
        $ask = $asks["$($heard.Conclusion.Kind)"]
        $follows = $false
        if ($ask -and [LambekCategories]::Satisfiable($statements)) {
            $question = [pscustomobject]@{ Kind = $ask[0]; Subject = $heard.Conclusion.Subject; Individual = $heard.Conclusion.Individual; Predicate = $heard.Conclusion.Predicate }
            $individual = $(if ($heard.Conclusion.Individual) { $heard.Conclusion.Individual.Key } else { '' })
            $opposite = Get-LambekCategoryOpposite -Item $question -Atoms $atoms -Individual $individual -No:$ask[1]
            $follows = [LambekCategories]::Follows($statements, $opposite)
        }
    }
    return [pscustomobject]@{
        Verdict    = $verdict
        Conclusion = Get-LambekCategorySignature -Item $heard.Conclusion
        Reasons    = (@($heard.Items | ForEach-Object { Get-LambekCategorySignature -Item $_ } | Sort-Object) -join "`n")
        Clauses    = $heard.Clauses
        Said       = $heard.Said
        Because    = $heard.Because
        Follows    = $follows
    }
}

function Read-LambekSpeechClause {
    param([string] $Conclusion, [string[]] $Reasons, [switch] $First, [string] $Language)

    # The parts read in the order they are said, each "c'est", "il", "elle" said again as the one named before it
    $listen = (Get-LambekSpeechData -Language $Language)['Listener']
    $genders = (Get-LambekSpeechData -Language $Language)['Gender']
    $order = $(if ($First) { @(, @($Conclusion, $true)) + @($Reasons | ForEach-Object { , @($_, $false) }) } else { @($Reasons | ForEach-Object { , @($_, $false) }) + @(, @($Conclusion, $true)) })
    $named = [System.Collections.Generic.List[object]]::new()
    $gender = @{}
    $items = [System.Collections.Generic.List[object]]::new()
    $clauses = [System.Collections.Generic.List[string]]::new()
    $because = [System.Collections.Generic.List[string]]::new()
    $said = $null
    $saidText = $null
    foreach ($entry in $order) {
        $clause = "$($entry[0])".Trim()
        if (-not $entry[1]) {
            foreach ($that in @($listen['That'])) { if ($clause.StartsWith("$that", [System.StringComparison]::OrdinalIgnoreCase)) { $clause = $clause.Substring("$that".Length); break } }
        }
        foreach ($rule in @($listen['Again'])) {
            if ($clause -notmatch "(?i)$($rule[0])") { continue }
            # (only one named before: anyone else, and it could be either)
            $keys = @($named | ForEach-Object { $_.Key } | Sort-Object -Unique)
            if ($keys.Count -ne 1 -or $keys[0] -eq 'speaker') { return $null }
            $one = @($named)[0]
            if ($rule[2] -and $gender.ContainsKey($one.Key) -and $gender[$one.Key] -ne $rule[2]) { return $null }
            $clause = [regex]::Replace($clause, "(?i)$($rule[0])", "$($rule[1])".Replace('{n}', $one.Written.Replace('$', '$$')))
            break
        }
        $plain = ConvertTo-LambekSpeechPlain -Text $clause
        $known = "$Language|$([bool] $entry[1])|$plain"
        if ($null -eq $script:SpeechReadings) { $script:SpeechReadings = @{} }
        if (-not $script:SpeechReadings.ContainsKey($known)) { $script:SpeechReadings[$known] = Read-LambekCategorySentence -Sentence $plain -Language $Language -Listener -Strict:$entry[1] }
        $item = $script:SpeechReadings[$known]
        if (-not $item -or "$($item.Kind)".StartsWith('ask')) { return $null }
        if ($item.Individual) {
            $named.Add($item.Individual)
            if ($item.Kind -eq 'is') { foreach ($rule in @($genders)) { if ("$($item.Written.Predicate)" -match "$($rule[0])") { $gender[$item.Individual.Key] = "$($rule[1])" } } }
        }
        $clauses.Add($clause)
        if ($entry[1]) { $said = $item; $saidText = $clause } else { $items.Add($item); $because.Add($clause) }
    }
    $key = "$(Get-LambekCategorySignature -Item $said)`n$((@($items | ForEach-Object { Get-LambekCategorySignature -Item $_ } | Sort-Object) -join "`n"))"
    return [pscustomobject]@{ Key = $key; Conclusion = $said; Items = $items.ToArray(); Clauses = $clauses.ToArray(); Said = $saidText; Because = $because.ToArray() }
}

function Get-LambekFluency {
    param([string] $Language)

    # How the language sounds (Data/Speech), read once
    if ($null -eq $script:Fluency) { $script:Fluency = @{} }
    if (-not $script:Fluency.ContainsKey($Language)) {
        $path = Join-Path $PSScriptRoot "../Data/Speech/$Language.fluency.gz"
        $model = $null
        if (Test-Path -LiteralPath $path -PathType Leaf) { $model = [LambekFluency]::Load($path) }
        $script:Fluency[$Language] = $model
    }
    return $script:Fluency[$Language]
}

function Get-LambekSpeechFusion {
    param([string] $Language)

    # The fusion of the satellites fitted by Optimize-LambekSpeech; none fitted, they weigh the same
    if ($null -eq $script:SpeechFusion) { $script:SpeechFusion = @{} }
    if (-not $script:SpeechFusion.ContainsKey($Language)) {
        $path = Join-Path $PSScriptRoot "../Data/Speech/$Language.speech.json"
        $fusion = $null
        if (Test-Path -LiteralPath $path -PathType Leaf) { $fusion = [LambekFusion]::Load((Get-Content -LiteralPath $path -Raw)) }
        $script:SpeechFusion[$Language] = $fusion
    }
    return $script:SpeechFusion[$Language]
}

function Get-LambekSpeechSatellite {
    # The satellites, each a measure of a way of saying it, between 0 and 1 among the ways that were read right:
    # Fluency, how the language sounds word by word; Whole, how it sounds as a whole (a short sentence is likelier);
    # Brevity, the fewest words; First, the answer before the reasons; Again, the name not said twice when it
    # could be said shortly
    return @('Fluency', 'Whole', 'Brevity', 'First', 'Again')
}

function Measure-LambekSpeech {
    param([object[]] $Candidates, [string] $Language)

    $model = Get-LambekFluency -Language $Language
    $dictionary = Get-LambekDictionary -Language $Language
    foreach ($candidate in $Candidates) {
        $words = @($candidate.Text -split '\s+' | Where-Object { $_ }).Count
        $score = @(0.0, 1.0)
        if ($model) { $score = $model.Score($candidate.Text, $dictionary) }
        $candidate | Add-Member -NotePropertyName Words -NotePropertyValue $words -Force
        $candidate | Add-Member -NotePropertyName LogProbability -NotePropertyValue $score[0] -Force
        $candidate | Add-Member -NotePropertyName PerWord -NotePropertyValue ($score[0] / $score[1]) -Force
    }
    # (each measure from 0, the worst of the ways, to 1, the best)
    $range = {
        param([double[]] $values)
        $low = [System.Linq.Enumerable]::Min($values)
        [pscustomobject]@{ Low = $low; Width = [System.Linq.Enumerable]::Max($values) - $low }
    }
    $spread = { param($range, [double] $value) if ($range.Width -lt 1e-9) { 1.0 } else { ($value - $range.Low) / $range.Width } }
    $perWord = & $range ([double[]] @($Candidates | ForEach-Object { $_.PerWord }))
    $whole = & $range ([double[]] @($Candidates | ForEach-Object { $_.LogProbability }))
    $fewest = [System.Linq.Enumerable]::Min([int[]] @($Candidates | ForEach-Object { $_.Words }))
    foreach ($candidate in $Candidates) {
        $again = $(if ($candidate.Mentions -le 1) { 1.0 } else { 1.0 - $candidate.Repeats / ($candidate.Mentions - 1) })
        $values = [double[]] @(
            (& $spread $perWord $candidate.PerWord),
            (& $spread $whole $candidate.LogProbability),
            ($fewest / [double] $candidate.Words),
            $(if ($candidate.First) { 1.0 } else { 0.0 }),
            $again
        )
        $candidate | Add-Member -NotePropertyName Satellites -NotePropertyValue $values -Force
    }
}

function Select-LambekSpeech {
    param([object[]] $Candidates, [string] $Language, [object] $Key, [scriptblock] $Check)

    # The fused measure of the satellites, best first, and the listener asked in that order: the first way it reads
    # right is said. A way the satellites disagree on too much (RAIM: the residuals past the chi-square limit) comes
    # after the others. Not the same frame twice in a row in a conversation when another one is almost as good
    $fusion = Get-LambekSpeechFusion -Language $Language
    $names = Get-LambekSpeechSatellite
    foreach ($candidate in $Candidates) {
        $fused = 0.0
        $sound = $true
        if ($fusion -and $fusion.Names.Count -eq $names.Count) {
            $fused = $fusion.Fuse($candidate.Satellites, $fusion.Weights)
            $sound = $fusion.ChiSquare($candidate.Satellites, $fused) -le $fusion.ChiSquareLimit
        }
        else { $fused = ($candidate.Satellites | Measure-Object -Average).Average }
        $candidate | Add-Member -NotePropertyName Fused -NotePropertyValue $fused -Force
        $candidate | Add-Member -NotePropertyName Sound -NotePropertyValue $sound -Force
    }
    $ranked = @($Candidates | Sort-Object -Stable @{ Expression = { $_.Sound }; Descending = $true }, @{ Expression = { $_.Fused }; Descending = $true }, @{ Expression = { $_.Text } })
    $best = $null
    foreach ($candidate in $ranked) { if (& $Check $candidate) { $best = $candidate; break } }
    if (-not $best) { return $null }
    if ($null -eq $script:SpeechFrames) { $script:SpeechFrames = [System.Collections.Generic.Dictionary[object, object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance) }
    $last = $null
    if ($script:SpeechFrames.ContainsKey($Key)) { $last = $script:SpeechFrames[$Key] }
    if ($last -and $best.Frame -eq $last) {
        foreach ($candidate in $ranked) {
            if ($candidate.Sound -ne $best.Sound -or $candidate.Fused -lt $best.Fused - 0.1) { continue }
            if ($candidate.Frame -ne $last -and (& $Check $candidate)) { $best = $candidate; break }
        }
    }
    $script:SpeechFrames[$Key] = $best.Frame
    return $best
}
