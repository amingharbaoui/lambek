function Resolve-LambekCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # General rules told in words, and what follows from them, exactly:
    #   "tous les chats de ma soeur sont noirs", "Minou est un chat de ma soeur", "Minou est-il noir ?" -> yes, and why;
    #   "aucun chien n'est un chat", "Rex est un chien", "Rex est-il un chat ?" -> no, and why;
    #   "certains chats sont gris", "Tom est un chat", "Tom est-il gris ?" -> it cannot be concluded: "certains" says not which.
    # Every sentence of the message must read as one of these, or nothing is taken. What is told is kept as told; what
    # is asked is answered yes, no, or that it cannot be known, never guessed (see Category.cs)
    if ($Text -notmatch '\p{L}') { return $null }
    # The answer to the question Lambek asked when it could not conclude: "oui" tells what the question asked,
    # and the question that could not be answered is answered again. Anything else said, the question is dropped
    $pending = Get-LambekCategoryPending
    if ($pending) {
        Set-LambekCategoryPending -Pending $null
        $answer = Test-LambekCategoryAnswer -Text $Text -Language $pending.Language
        if ($answer) {
            $told = $(if ($answer -eq 'yes') { $pending.Yes } else { $pending.No })
            $sentences = @(Split-LambekCategorySentence -Text "$told. $($pending.Question)" -Language $pending.Language)
            $result = Resolve-LambekCategoryMessage -Sentences $sentences -Language $pending.Language -Noted
            if ($result) { return $result }
        }
    }
    $detected = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) -Forms
    # (the languages general rules were told in come first, after the one the message reads as when rules were told
    # in it: "Rex abbaia?" after "tutti i cani abbaiano" is Italian, whatever its few words alone say)
    # (and a language whose dialogue was learned, where what was told of someone is kept for the rules: "Rex e grande?"
    # after "Rex e un cane. Lui e grande." is Italian, whatever "grande" says in Portuguese)
    $kept = { param($l) @(Get-LambekCategoryKnown -Language $l -Shape | Where-Object { $_.Item.Kind -in 'all', 'no', 'some', 'somenot' -or ((Get-LambekLexicon -Language $l).Dialogue['Learned'] -and "$($_.Fact.Action)" -eq 'verb:category') }).Count -gt 0 }
    $told = @(Get-LambekAvailableLanguage | Sort-Object | Where-Object { $_ -ne $detected -and (& $kept $_) })
    $own = & $kept $detected
    $languages = $(if ($own -or $told.Count -eq 0) { @($detected) + $told } else { $told + @($detected) })
    $languages = @($languages) + @(Get-LambekAvailableLanguage | Where-Object { $_ -notin $languages } | Sort-Object)
    foreach ($language in $languages) {
        $words = Get-LambekCategoryVocabulary -Language $language
        if (-not $words) { continue }
        $sentences = @(Split-LambekCategorySentence -Text $Text -Language $language)
        if ($sentences.Count -eq 0) { continue }
        # Two names told together ("Rex en Max zijn honden"), in the language the message reads as: a sentence that
        # does not read whole is told name by name, when each part reads (Split-LambekCoordination)
        if ($language -eq $detected) { $sentences = @(Split-LambekCategoryCoordination -Sentences $sentences -Language $language) }
        # A question of two things at once ("tous les chats sont-ils noirs et gentils ?"): each asked, each answered
        $asked = @($sentences | Where-Object { $_.Question })
        $joins = @(Get-LambekConjunctionWord -Language $language | ForEach-Object { [regex]::Escape("$_") })
        if ($asked.Count -eq 1 -and $joins.Count -gt 0 -and [object]::ReferenceEquals($asked[0], $sentences[-1])) {
            $both = @(Split-LambekCategoryBoth -Text $asked[0].Text -Language $language -Joins $joins -Question)
            if ($both.Count -eq 2) {
                $told = @($sentences | Select-Object -SkipLast 1)
                $answers = @(foreach ($one in $both) {
                        $question = [pscustomobject]@{ Original = "$one ?"; Text = $one; Question = $true; Correcting = $false }
                        Resolve-LambekCategoryMessage -Sentences (@($told) + @($question)) -Language $language
                    })
                if ($answers.Count -eq 2 -and $answers[0] -and $answers[1]) {
                    return [pscustomobject]@{ Language = $language; Reply = "$($answers[0].Reply)`n$($answers[1].Reply)"; Facts = $answers[0].Facts }
                }
            }
        }
        # A quick look first, with the shapes of the sentences only
        $shapes = @(foreach ($sentence in $sentences) {
                $shape = Read-LambekCategorySentence -Sentence $sentence.Text -Language $language -Question:$sentence.Question -Shape
                if (-not $shape) { break }
                $shape
            })
        if ($shapes.Count -ne $sentences.Count) { continue }
        # (what is told just after the question asked is the answer to it, said in full: the question is answered again)
        if ($pending -and $language -eq $pending.Language -and @($sentences | Where-Object { $_.Question }).Count -eq 0) {
            $again = @(Split-LambekCategorySentence -Text $pending.Question -Language $language)
            $result = Resolve-LambekCategoryMessage -Sentences (@($sentences) + @($again)) -Language $language -Noted
            # (what does not settle it is only told: the question still waits for its answer)
            if (-not $result -or ($result.PSObject.Properties['Settled'] -and $result.Settled)) { return $result }
        }
        return Resolve-LambekCategoryMessage -Sentences $sentences -Language $language
    }
    return $null
}

function Split-LambekCategoryBoth {
    param([string] $Text, [string] $Language, [string[]] $Joins, [switch] $Question)

    # One sentence that says two things with one word that says both, as two sentences, each read as such:
    #   what is said of one kind or one, twice: "tous les chats sont noirs et gentils" is "tous les chats sont noirs" and
    #   "tous les chats sont gentils"; "Rex aboie et mord", "tous les chats aiment le lait et le poisson";
    #   two kinds said the same: "tous les chats et les chiens sont des animaux" is said of the chats and of the
    #   chiens, the second taking the word of how many of the first ("all cats and dogs": "all dogs").
    # Only when both read, about the same one or kind, or saying the same of each, and only for what holds of each
    # part when it holds of both: never with "aucun" or a word that says not ("aucun chat n'est noir et gentil" says
    # no such thing of each), never a question
    $words = @($Text.Trim() -split '\s+' | Where-Object { $_ })
    $at = @(for ($i = 1; $i -lt $words.Count - 1; $i++) { if ($words[$i] -match "(?i)^($($Joins -join '|'))$") { $i } })
    if ($at.Count -ne 1) { return }
    $left = @($words[0..($at[0] - 1)])
    $right = @($words[($at[0] + 1)..($words.Count - 1)])
    # (rules about kinds only: what is told of one is read by the rest of Lambek, which splits it its own way; asked,
    # whether it holds of every one or of some)
    $kept = $(if ($Question) { 'askall', 'asksome' } else { 'all', 'some' })
    $read = { param($t) $r = Read-LambekCategorySentence -Sentence $t -Language $Language -Question:$Question; if ($r -and $r.Kind -in $kept) { $r } }
    $who = { param($r) if ($r.Individual) { "one:$($r.Individual.Key)" } elseif ($r.Subject) { "kind:$(@($r.Subject.Atoms) -join '+')" } else { '' } }
    $what = { param($r) "$([bool] $r.Verb)|$(@($r.Predicate.Atoms) -join '+')" }
    # (what is said of the same one or kind, twice: the longest start of the first that reads with the second, where
    # the second takes the place of words of the same part of speech, "noirs" for "gentils", "aboient" for "mordent")
    $model = Get-LambekFormModel -Language $Language
    $first = & $read ($left -join ' ')
    if ($first -and $model) {
        $leftTags = @($model.Read([string[]] $left))
        for ($k = $left.Count - 1; $k -ge 1; $k--) {
            # (the second part with what the first part's own words would say twice is no reading: "un un animal")
            if ($left[$k - 1].ToLowerInvariant() -eq $right[0].ToLowerInvariant()) { continue }
            # (read in the sentence it makes, as the first word it takes the place of was read in its own)
            $candidateTags = @($model.Read([string[]] (@($left[0..($k - 1)]) + $right)))
            if ($leftTags.Count -ne $left.Count -or $candidateTags.Count -le $k) { continue }
            # (words that say something stand for each other, whatever the tagger made of each, "grands" for "forts";
            # a small word only for one of its own kind, "le" for "le", never "in" for "work")
            $sort = { param($u) if ("$u" -in 'NOUN', 'PROPN', 'ADJ', 'VERB', 'ADV', 'NUM', 'X') { 'content' } else { "$u" } }
            if ((& $sort $leftTags[$k].Upos) -ne (& $sort $candidateTags[$k].Upos)) { continue }
            $second = & $read ((@($left[0..($k - 1)]) + $right) -join ' ')
            if ($second -and $second.Kind -eq $first.Kind -and (& $who $second) -eq (& $who $first) -and (& $what $second) -ne (& $what $first)) {
                return @(($left -join ' '), ((@($left[0..($k - 1)]) + $right) -join ' '))
            }
        }
    }
    # (two kinds said the same: the first takes what follows the second, the second the word of how many of the first)
    $logic = Get-LambekLogicWord -Language $Language
    $many = $(if ($logic -and $logic.Kinds.ContainsKey($left[0].ToLowerInvariant())) { $left[0] } else { '' })
    # (what follows the second kind starts at its verb: "sont des animaux")
    $tags = @($(if ($model) { $model.Read([string[]] $right) }))
    # (one said of one kind, then a noun said without its own article: "every representative and client" may be every
    # one who is both, as much as each of them; told of several, "all cats and dogs", or each with its article, "tous
    # les chats et les chiens", it is each of them)
    $before = @($(if ($model) { $model.Read([string[]] $left) }))
    if ($before.Count -gt 0 -and "|$($before[-1].Feats)|" -match '\|Number=Sing\|' -and $tags.Count -gt 0 -and "$($tags[0].Upos)" -ne 'DET') { return }
    for ($j = 1; $j -lt $right.Count; $j++) {
        if ($tags.Count -ne $right.Count -or "$($tags[$j].Upos)" -notin 'VERB', 'AUX') { continue }
        $rest = @($right[$j..($right.Count - 1)])
        $one = & $read ((@($left) + $rest) -join ' ')
        if (-not $one -or -not $one.Subject) { continue }
        $others = [System.Collections.Generic.List[string]]::new()
        if ($many -and $right[0].ToLowerInvariant() -ne $many.ToLowerInvariant()) { $others.Add((@($many) + $right) -join ' ') }
        $others.Add($right -join ' ')
        foreach ($other in $others) {
            $two = & $read $other
            if ($two -and $two.Subject -and $two.Kind -eq $one.Kind -and [bool] $two.Default -eq [bool] $one.Default -and (& $what $two) -eq (& $what $one) -and (& $who $two) -ne (& $who $one)) {
                return @(((@($left) + $rest) -join ' '), $other)
            }
        }
    }
}

function Get-LambekConjunctionWord {
    param([string] $Language)

    # The words that join two things said and say both: learned where English says "and" or "but" (General.And), never
    # those that say one of them; a language that has none learned joins nothing
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $general = $(if ($dialogue -and $dialogue['General']) { $dialogue['General'] } else { $null })
    if (-not $general -or -not $general.Contains('And')) { return }
    @($general['And']) | Where-Object { $_ }
}

function Get-LambekDisjunctionWord {
    param([string] $Language)

    # The words that join two things said and say one of them: learned where English says "or" (General.Or); a
    # language that has none learned joins nothing so
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $general = $(if ($dialogue -and $dialogue['General']) { $dialogue['General'] } else { $null })
    if (-not $general -or -not $general.Contains('Or')) { return }
    @($general['Or']) | Where-Object { $_ } | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" }
}

function Split-LambekCategoryCoordination {
    param([object[]] $Sentences, [string] $Language)

    # (only the words that say both, "et", "and", "und", learned where English says "and" or "but": never "ou", "o",
    # "oder", which say one of them)
    $joins = @(Get-LambekConjunctionWord -Language $Language | ForEach-Object { [regex]::Escape("$_") })
    foreach ($sentence in $Sentences) {
        # A sentence told with two kinds or two things said of the same ("tous les chats et les chiens sont des
        # animaux", "tous les chats sont noirs et gentils", "tous les chiens aboient et mordent"): two sentences
        if (-not $sentence.Question -and $joins.Count -gt 0) {
            $both = @(Split-LambekCategoryBoth -Text $sentence.Text -Language $Language -Joins $joins)
            if ($both.Count -eq 2) {
                $split = @(Split-LambekCategorySentence -Text (($both | ForEach-Object { "$_." }) -join ' ') -Language $Language)
                if ($split.Count -eq 2) { $split; continue }
            }
        }
        # (only a sentence told, with a word that joins, that does not read as it is, its shape aside)
        if ($sentence.Question -or $joins.Count -eq 0 -or $sentence.Text -notmatch "(?i)(^|\s)($($joins -join '|'))(\s|$)" -or
            (Read-LambekCategorySentence -Sentence $sentence.Text -Language $Language)) { $sentence; continue }
        [string[]] $parts = Split-LambekCoordination -Text $sentence.Original -Language $Language
        $split = @()
        if ($parts.Count -gt 1) { $split = @(Split-LambekCategorySentence -Text (($parts | ForEach-Object { "$_." }) -join ' ') -Language $Language) }
        $read = @($split | Where-Object { -not $_.Question -and (Read-LambekCategorySentence -Sentence $_.Text -Language $Language -Shape) })
        if ($parts.Count -gt 1 -and $split.Count -eq $parts.Count -and $read.Count -eq $split.Count) {
            # (what they are said to be together is said back as it was said, once: "Rex et Max sont des chiens", not "Rex
            # est des chiens"; what they do is said of each, "your sister lives in Lyon")
            $kinds = @($split | ForEach-Object { (Read-LambekCategorySentence -Sentence $_.Text -Language $Language -Shape).Kind })
            if (@($kinds | Where-Object { $_ -notin 'is', 'isnot' }).Count -eq 0) {
                foreach ($part in $split) { $part | Add-Member -NotePropertyName Joined -NotePropertyValue $sentence.Original -Force }
            }
            $split
        }
        else { $sentence }
    }
}

function Find-LambekCategoryReplaced {
    param([object] $Premises, [object] $Statements, [object] $Facts)

    # Which older thing told the thing told now replaces: among the sentences that cannot all be true together, the
    # last one told about the same one as the sentence told now. A general rule is never replaced by a sentence about
    # someone, and nothing is replaced when the one told now is about no one in particular
    if (@($Facts).Count -ne 1) { return $null }
    $conflict = @([LambekCategories]::Smallest($Statements, $null))
    if ($conflict.Count -eq 0) { return $null }
    $new = @(for ($i = 0; $i -lt $Premises.Count; $i++) { if ($Premises[$i].Fact -and $Premises[$i].Fact -eq $Facts[0]) { $i } })
    if ($new.Count -ne 1 -or $new[0] -notin $conflict) { return $null }
    # (a general rule is about no one in particular)
    $who = { param($item) $(if ($item.Individual) { "$($item.Individual.Key)" } else { '' }) }
    $about = & $who $Premises[$new[0]].Item
    if (-not $about) { return $null }
    $older = @($conflict | Where-Object { $_ -ne $new[0] -and $Premises[$_].Fact -and (& $who $Premises[$_].Item) -eq $about })
    if ($older.Count -eq 0) { return $null }
    return $older[$older.Count - 1]
}

function Find-LambekCategoryTakenBack {
    param([object] $Premises, [object[]] $Items, [object[]] $Facts, [string] $Language)

    # What a correction takes back, among the things told before about the same one, each with the thing told now that
    # takes its place:
    #   "Tom n'est pas un chat" (said after "je me suis trompe", or with "pas un chat") takes back "Tom est un chat";
    #   "Tom est un chien" alone (after "en fait") takes back the last kind Tom was said to be, unless the dictionary
    #   says one of the two is a kind of the other ("Tom est un animal" stays: a chien is one).
    # Only sentences about someone are taken back, never a general rule
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $articles = @($data['Articles'] | Where-Object { $_ })
    $said = [System.Collections.Generic.List[object]]::new()
    $k = 0
    foreach ($entry in $Items) {
        if ($entry.Item.Kind.StartsWith('ask')) { continue }
        if ($entry.Sentence.PSObject.Properties['Correcting'] -and $entry.Sentence.Correcting -and $entry.Item.Individual) {
            $said.Add([pscustomobject]@{ Item = $entry.Item; Fact = $Facts[$k] })
        }
        $k++
    }
    $key = { param($item) (@($item.Predicate.Atoms) | ForEach-Object { "$_" }) -join ' ' }
    $before = @(for ($i = 0; $i -lt $Premises.Count; $i++) {
            $premise = $Premises[$i]
            if (-not $premise.Fact -or @($Facts | Where-Object { [object]::ReferenceEquals($_, $premise.Fact) }).Count -gt 0) { continue }
            if ($premise.Item.Kind -ne 'is' -or -not $premise.Item.Individual -or -not $premise.Item.Predicate) { continue }
            [pscustomobject]@{ Index = $i; Who = "$($premise.Item.Individual.Key)"; What = (& $key $premise.Item); Item = $premise.Item }
        })
    $dictionary = Get-LambekDictionary -Language $Language
    $related = {
        param([string] $one, [string] $other)
        if ($dictionary -isnot [LambekDictionary]) { return $false }
        foreach ($pair in @(@($one, $other), @($other, $one))) {
            if ($null -eq $script:CategoryCircles) { $script:CategoryCircles = @{} }
            $circle = "$Language`t$($pair[0])`t$($pair[1])"
            if (-not $script:CategoryCircles.ContainsKey($circle)) {
                $script:CategoryCircles[$circle] = $dictionary.Under($pair[0], $pair[1], $Language, 'n', $script:CategoryCircleSenses, $script:CategoryCircleHops)
            }
            if ($script:CategoryCircles[$circle] -gt 0) { return $true }
        }
        return $false
    }
    $found = [System.Collections.Generic.List[object]]::new()
    $taken = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($one in @($said | ForEach-Object { "$($_.Item.Individual.Key)" } | Select-Object -Unique)) {
        $denied = @($said | Where-Object { "$($_.Item.Individual.Key)" -eq $one -and $_.Item.Kind -eq 'isnot' })
        $told = @($said | Where-Object { "$($_.Item.Individual.Key)" -eq $one -and $_.Item.Kind -eq 'is' })
        # (what one does is told in a sentence of another kind: nothing it says is a kind to take back)
        if ($told.Count -eq 0 -and $denied.Count -eq 0) { continue }
        $by = $(if ($told.Count -gt 0) { $told[0].Fact } else { $denied[0].Fact })
        if ($denied.Count -gt 0) {
            foreach ($no in $denied) {
                foreach ($old in @($before | Where-Object { $_.Who -eq $one -and $_.What -ceq (& $key $no.Item) })) {
                    if ($taken.Add($old.Index)) { $found.Add([pscustomobject]@{ Index = $old.Index; By = $by }) }
                }
            }
            continue
        }
        foreach ($yes in $told) {
            $kinds = @($before | Where-Object {
                    $_.Who -eq $one -and $_.What -cne (& $key $yes.Item) -and
                    @("$($_.Item.Written.Predicate)".Trim() -split '\s+')[0] -in $articles
                })
            for ($j = $kinds.Count - 1; $j -ge 0; $j--) {
                $old = $kinds[$j]
                if (& $related $old.What (& $key $yes.Item)) { continue }
                if ($taken.Add($old.Index)) { $found.Add([pscustomobject]@{ Index = $old.Index; By = $yes.Fact }) }
                break
            }
        }
    }
    return $found.ToArray()
}

function Get-LambekCategoryVocabulary {
    param([string] $Language)

    # The words and shapes of general rules in a language, with their patterns read once
    if ($null -eq $script:CategoryWords) { $script:CategoryWords = @{} }
    if ($script:CategoryWords.ContainsKey($Language)) { return $script:CategoryWords[$Language] }
    $dialogue = (Get-LambekLexicon -Language $Language).Dialogue
    $words = $null
    if ($dialogue -and $dialogue['Categories']) {
        $data = $dialogue['Categories']
        $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        $rules = {
            param($list)
            # ("fait partie des chats" says what "est un chat" says, with the name of the kind in the plural)
            @(foreach ($rule in @($list)) {
                    if (-not $rule) { continue }
                    $kind = "$($rule[0])"
                    $member = $kind.EndsWith('member')
                    if ($member) { $kind = @{ ismember = 'is'; isnotmember = 'isnot'; askmember = 'askis' }[$kind] }
                    [pscustomobject]@{ Kind = $kind; Member = $member; Regex = [regex]::new("$($rule[1])", $options) }
                })
        }
        $words = [pscustomobject]@{
            Statements = & $rules $data['Statements']
            Listener   = & $rules $data['Listener']
            Questions  = & $rules $data['Questions']
            # (what is only imagined: "et si Tweety etait un pingouin", "would he fly")
            Imagined   = $(if ($data['Imagine']) { & $rules $data['Imagine']['Statements'] } else { @() })
            Wondered   = $(if ($data['Imagine']) { & $rules $data['Imagine']['Questions'] } else { @() })
            Data       = $data
        }
    }
    $script:CategoryWords[$Language] = $words
    return $words
}

function Split-LambekCategorySentence {
    param([string] $Text, [string] $Language)

    # The sentences of the message, each as written, in its plain form, and whether it asks. A sentence with anything
    # but words (a number, a path, a file) is no general rule: the whole message is left to the rest of Lambek
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $lead = @($data['Lead'] | Where-Object { $_ } | ForEach-Object { [regex]::Escape("$_") })
    # (the words that take back what was told, the longest first: "non, en fait", "I was wrong")
    $taking = @($data['Corrections'] | Where-Object { $_ } | Sort-Object { -"$_".Length }, { "$_" } | ForEach-Object { [regex]::Escape("$_") -replace '\\ ', '\s+' })
    $sentences = [System.Collections.Generic.List[object]]::new()
    foreach ($part in [regex]::Split($Text.Trim(), '(?<=[.!?;])\s+')) {
        $original = $part.Trim()
        if (-not $original) { continue }
        $question = $original -match '\?\s*$'
        # (a mark that opens a sentence is no word of it: the inverted one of Spanish; an apostrophe is a letter's)
        $plain = (($original -replace '[.!?;]+\s*$', '') -replace "^[\p{Po}-['\u2019]]+", '').Trim()
        if ($lead.Count -gt 0) { $plain = [regex]::Replace($plain, "(?i)^(?:$($lead -join '|'))\s*,?\s+", '') }
        # "non, en fait Tom est un chien", "correction : Tom est un chien, pas un chat": what follows the words that take
        # something back is told in its place (Find-LambekCategoryTakenBack)
        $correcting = $false
        if (-not $question -and $taking.Count -gt 0) {
            # (marked off as such: "no, actually", "correction :"; "no dog is a cat" takes nothing back)
            $taken = [regex]::Match($plain, "(?i)^(?:(?:$($taking -join '|'))\s*[,:]\s*)+(?:(?:$($taking -join '|'))\s+)?")
            if ($taken.Success -and $taken.Length -lt $plain.Length) {
                $plain = $plain.Substring($taken.Length)
                if ($lead.Count -gt 0) { $plain = [regex]::Replace($plain, "(?i)^(?:$($lead -join '|'))\s*,?\s+", '') }
                $correcting = $true
            }
        }
        if ($correcting) {
            $parts = @(Split-LambekCategoryCorrection -Text $plain -Language $Language)
            if ($parts.Count -gt 0) {
                foreach ($said in $parts) { $sentences.Add([pscustomobject]@{ Text = $said; Original = $said; Question = $false; Correcting = $true }) }
                continue
            }
        }
        # (a comma only marks a pause: "normalement, les oiseaux volent")
        $plain = (($plain -replace ',', ' ') -replace '\s+', ' ').Trim()
        # (a name may have figures in it, "the XR-200", "le PC-6082"; a figure alone is a number, for the rest of Lambek)
        if (-not $plain -or -not (Test-LambekCategoryWording -Text $plain)) { return @() }
        $sentences.Add([pscustomobject]@{ Text = $plain; Original = ($original -replace '[.;]+\s*$', '').Trim(); Question = $question; Correcting = $correcting })
    }
    return $sentences.ToArray()
}

function Test-LambekCategoryWording {
    param([string] $Text)

    # Only words: letters, and figures only in a word that has letters too ("XR-200"), never a number alone
    if ($Text -notmatch "^[\p{L}\p{N}'\u2019 -]+$") { return $false }
    foreach ($word in @($Text -split '\s+' | Where-Object { $_ })) { if ($word -match '\p{N}' -and $word -notmatch '\p{L}') { return $false } }
    return $true
}

function Split-LambekCategoryCorrection {
    param([string] $Text, [string] $Language)

    # What a correction tells, as sentences of their own: "Tom est un chien, pas un chat" is "Tom est un chien" and
    # "Tom n'est pas un chat"; "Tom n'est pas un chat mais un chien" is "Tom n'est pas un chat" and "Tom est un chien".
    # The first part that reads says who it is about; a part that does not read is what is said of the same one, denied
    # when it holds a word that denies. Nothing when no part reads, or a part is anything else
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $lead = @($data['Lead'] | Where-Object { $_ } | ForEach-Object { [regex]::Escape("$_") })
    $denying = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($word in @($general['Negations'])) { if ($word) { [void] $denying.Add("$word") } }
    $joins = '\s*,\s*'
    if ($lead.Count -gt 0) { $joins += "|\s+(?:$($lead -join '|'))\s+" }
    $pieces = @([regex]::Split($Text, "(?i)$joins") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($pieces.Count -eq 0 -or @($pieces | Where-Object { $_ -notmatch "^[\p{L}'\u2019 -]+$" }).Count -gt 0) { return @() }
    $first = Read-LambekCategorySentence -Sentence $pieces[0] -Language $Language
    if (-not $first -or $first.Kind -notin 'is', 'isnot' -or -not $first.Individual) { return @() }
    $said = [System.Collections.Generic.List[string]]::new()
    $said.Add($pieces[0])
    $sentences = $data['Sentences']
    foreach ($piece in @($pieces | Select-Object -Skip 1)) {
        $words = @($piece -split "\s+|(?<=['\u2019])")
        $denied = @($words | Where-Object { $denying.Contains(("$_" -replace "['\u2019]$", '')) }).Count -gt 0
        $what = (@($words | Where-Object { -not $denying.Contains(("$_" -replace "['\u2019]$", '')) }) -join ' ').Trim()
        $shape = $(if ($denied) { 'isnot' } else { 'is' })
        if (-not $what -or -not $sentences[$shape]) { return @() }
        $sentence = $sentences[$shape] -f $first.Individual.Written, $what
        $read = Read-LambekCategorySentence -Sentence $sentence -Language $Language
        if (-not $read -or $read.Kind -ne $shape) { return @() }
        $said.Add($sentence)
    }
    return $said.ToArray()
}

function Read-LambekCategorySentence {
    param(
        [string] $Sentence,
        [string] $Language,
        # A question ends with its mark; a sentence without one that only reads as a question is one too
        [switch] $Question,
        # The sentence is said by Lambek: "vous" is the user
        [switch] $Listener,
        # Only the shape: what kind of sentence it is, without the dictionary
        [switch] $Shape,
        # The sentence is read as it is, without looking for "normalement" in it
        [switch] $Strict,
        # The sentence is imagined: "Tweety etait un pingouin", "est-ce que Tweety serait gris"
        [switch] $Imagined
    )

    $words = Get-LambekCategoryVocabulary -Language $Language
    if (-not $words) { return $null }
    # "normalement, les oiseaux volent", "la plupart des oiseaux volent": a rule about every one that holds unless
    # something told says otherwise. It must read as such a rule once the word is taken out
    if (-not $Question -and -not $Strict) {
        $usual = @(Get-LambekCategoryUsual -Sentence $Sentence -Language $Language)
        if ($usual.Count -gt 0) {
            foreach ($rest in $usual) {
                $read = Read-LambekCategorySentence -Sentence $rest -Language $Language -Listener:$Listener -Shape:$Shape -Strict
                if (-not $read -or $read.Kind -notin 'all', 'no') { continue }
                $read | Add-Member -NotePropertyName Default -NotePropertyValue $true -Force
                return $read
            }
            return $null
        }
    }
    $lists = @()
    if (-not $Question) {
        if ($Listener) { $lists += , @($words.Listener) }
        if ($Imagined) { $lists += , @($words.Imagined) }
        $lists += , @($words.Statements)
    }
    if ($Imagined) { $lists += , @($words.Wondered) }
    $lists += , @($words.Questions)
    # Read first by the tags of its words and the words of logic learned, the same in every language that has them
    # ("tous les appareils ont un capteur", "mon telephone a-t-il un capteur"); then by the patterns of the language
    if (-not $Listener -and -not $Imagined) {
        $tagged = Read-LambekCategoryTagged -Sentence $Sentence -Language $Language -Question:$Question -Shape:$Shape
        if ($tagged) { return $tagged }
    }
    foreach ($list in $lists) {
        foreach ($rule in $list) {
            $match = $rule.Regex.Match($Sentence)
            if (-not $match.Success) { continue }
            if ($Shape) { return [pscustomobject]@{ Kind = $rule.Kind } }
            $read = ConvertTo-LambekCategoryItem -Kind $rule.Kind -Match $match -Language $Language -Listener:$Listener -Member:$rule.Member
            if ($read) { return $read }
        }
    }
    return $null
}

function ConvertTo-LambekCategoryItem {
    param([string] $Kind, [System.Text.RegularExpressions.Match] $Match, [string] $Language, [switch] $Listener, [switch] $Member)

    # What the parts of a sentence are: the quantifier, the kind of things, the one named, what is said of them.
    # Parts side by side ("is my sister a student", "tous les chats de ma soeur aiment le lait") are cut where they all
    # read: the first cut that does, from the left
    $groups = $Match.Groups
    $group = { param($name) if ($groups[$name].Success) { $groups[$name] } else { $null } }
    $values = @{}
    foreach ($name in 'q', 's', 'n', 'p', 'v', 'o') { $found = & $group $name; if ($found) { $values[$name] = $found.Value } }
    $next = { param($a, $b) $a -and $b -and $a.Index + $a.Length + 1 -eq $b.Index }
    $who = $(if (& $group 's') { 's' } elseif (& $group 'n') { 'n' } else { $null })
    $cuts = @($values)
    if ($who -and (& $next (& $group $who) (& $group 'p'))) {
        $span = "$($values[$who]) $($values['p'])"
        $cuts = @(foreach ($space in [regex]::Matches($span, ' ')) {
                $cut = $values.Clone()
                $cut[$who] = $span.Substring(0, $space.Index)
                $cut['p'] = $span.Substring($space.Index + 1)
                $cut
            })
    }
    elseif ($who -and (& $next (& $group $who) (& $group 'v'))) {
        # (the verb is one word; what follows it right away is its object)
        $span = "$($values[$who]) $($values['v'])"
        $tail = $(if (& $next (& $group 'v') (& $group 'o')) { " $($values['o'])" } else { '' })
        $parts = @(($span + $tail) -split ' ')
        $cuts = @(for ($j = 1; $j -lt $parts.Count; $j++) {
                if (-not $tail -and $j -ne $parts.Count - 1) { continue }
                $cut = $values.Clone()
                $cut[$who] = ($parts[0..($j - 1)] -join ' ')
                $cut['v'] = $parts[$j]
                if ($tail) { if ($j -lt $parts.Count - 1) { $cut['o'] = ($parts[($j + 1)..($parts.Count - 1)] -join ' ') } else { $cut.Remove('o') } }
                $cut
            })
    }
    foreach ($cut in $cuts) {
        $item = Read-LambekCategoryPart -Kind $Kind -Values $cut -Language $Language -Listener:$Listener -Member:$Member
        if ($item) { return $item }
    }
    return $null
}

function ConvertTo-LambekCategoryOpaque {
    param(
        [string] $Text,
        [string] $Language,

        # What is said of one, not what is done to: kept to one thing said, with no number
        [switch] $Predicate
    )

    # What is said of one or of a kind that is no kind of thing the dictionary knows ("veulent etre de grands tenors",
    # "travel freely within Europe", "are from Sweden"), kept whole: one thing said, written with the lemma of each
    # of its words, the articles left out, so that "veut etre un grand tenor" and "veulent etre de grands tenors" are
    # the same thing said. Nothing follows from it but what is said with the same words: never a kind of anything, so
    # it can make no answer that does not follow. Read by the tags of the forms model of the language; nothing when a
    # word is a word of logic or says not, when a word is no word of the language, or when it is long. What is said of
    # one is nothing either when it holds more than one thing said (a comma, a word that stands for one named
    # elsewhere: "un homme, c'est un homme"), or a number, which says how much or when ("depuis 2000")
    $model = Get-LambekFormModel -Language $Language
    if (-not $model) { return $null }
    if ($Predicate -and ($Text.Trim() -replace '[.!?]+$', '') -match '[,;:]') { return $null }
    $plain = (($Text -replace "[,;:.!?]+", ' ') -replace '\s+', ' ').Trim()
    if (-not $plain) { return $null }
    $readings = @($model.ReadText($plain))
    if ($readings.Count -eq 0 -or $readings.Count -gt 8) { return $null }
    $logic = Get-LambekLogicWord -Language $Language
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $denying = @($general['Negations'] | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" })
    $words = [System.Collections.Generic.List[string]]::new()
    $content = $false
    foreach ($reading in $readings) {
        $form = "$($reading.Form)"
        $low = $form.ToLowerInvariant()
        if ("$($reading.Upos)" -eq 'PUNCT') { continue }
        if ($Predicate -and "$($reading.Upos)" -in 'PRON', 'NUM') { return $null }
        if (($logic -and $logic.Kinds.ContainsKey($low)) -or (ConvertTo-LambekNormalizedText -Text $low) -in $denying -or "|$($reading.Feats)|" -match '\|Polarity=Neg\|') { return $null }
        $known = $model.Knows($low) -or ($model.Lexicon -and $model.Lexicon.Forms.ContainsKey($low))
        # (a word the language does not know is taken only as a noun, an adjective or a name, as when reading by tags)
        if (-not $known -and -not ($form.Length -gt 0 -and [char]::IsUpper($form[0])) -and "$($reading.Upos)" -notin 'NOUN', 'ADJ', 'PROPN') { return $null }
        # (an article says nothing of what is said: "un", "de", "les", "the", "a")
        if ("$($reading.Upos)" -eq 'DET' -and "|$($reading.Feats)|" -match '\|PronType=Art\|') { continue }
        if ("$($reading.Upos)" -in 'NOUN', 'PROPN', 'ADJ', 'VERB', 'ADV', 'NUM') { $content = $true }
        $lemma = $(if ($reading.Lemma -and "$($reading.Upos)" -ne 'PROPN') { "$($reading.Lemma)" } else { $form })
        $words.Add((ConvertTo-LambekNormalizedText -Text $lemma))
    }
    if (-not $content -or $words.Count -eq 0) { return $null }
    return [pscustomobject]@{ Atoms = @("op:$($words -join ' ')") }
}

function Read-LambekCategoryPart {
    param([string] $Kind, [hashtable] $Values, [string] $Language, [switch] $Listener, [switch] $Member)

    $item = [pscustomobject]@{
        Kind       = $Kind
        Member     = [bool] $Member
        Default    = $false
        Quantifier = ''
        Subject    = $null
        Individual = $null
        Predicate  = $null
        Verb       = $false
        Written    = [pscustomobject]@{ Subject = ''; Predicate = ''; Object = '' }
    }
    if ($Values.ContainsKey('q')) { $item.Quantifier = ConvertTo-LambekNormalizedText -Text $Values['q'] }
    if ($Values.ContainsKey('s')) {
        $item.Subject = ConvertTo-LambekCategoryTerm -Text $Values['s'] -Language $Language -Bare -Lemmas $Values['lemmas']
        if (-not $item.Subject) { return $null }
        $item.Written.Subject = $Values['s'].Trim()
    }
    if ($Values.ContainsKey('n')) {
        $item.Individual = ConvertTo-LambekCategoryIndividual -Text $Values['n'] -Language $Language -Listener:$Listener -Lemmas $Values['lemmas']
        $item.Written.Subject = $Values['n'].Trim()
        # (asked of "il", "he", or told of it after the one it stands for in the same message: the one it stands for,
        # said by its name)
        if (-not $item.Individual -and (($Values.ContainsKey('asked') -and $Values['asked']) -or $null -ne $script:CategoryMessage)) {
            $item.Individual = Resolve-LambekCategoryPronoun -Text $Values['n'] -Language $Language
            if ($item.Individual) {
                $item.Written.Subject = "$($item.Individual.Written)"
                $item | Add-Member -NotePropertyName Pronoun -NotePropertyValue $Values['n'].Trim()
            }
        }
        if (-not $item.Individual) { return $null }
    }
    if ($Values.ContainsKey('p')) {
        # (one of several kinds, "un chien ou un chat", only where it is said to be so: what is said not to be one of
        # several, "n'est pas noir ou blanc", may say not either or not both, and is left as it is)
        $either = $Kind -in 'is', 'all', 'some', 'askis', 'askall', 'asksome'
        $item.Predicate = ConvertTo-LambekCategoryTerm -Text $Values['p'] -Language $Language -Lemmas $Values['lemmas'] -Alternatives:$either
        if (-not $item.Predicate) { $item.Predicate = ConvertTo-LambekCategoryOpaque -Text $Values['p'] -Language $Language -Predicate }
        if (-not $item.Predicate) { return $null }
        $item.Written.Predicate = $Values['p'].Trim()
    }
    elseif ($Values.ContainsKey('v')) {
        # (the lemma the forms model read the verb with in its sentence, when the sentence was read by its tags)
        $lemma = $(if ($Values.ContainsKey('lemma')) { ConvertTo-LambekNormalizedText -Text $Values['lemma'] } else { Get-LambekCategoryLemma -Word (ConvertTo-LambekNormalizedText -Text $Values['v']) -Language $Language -Verb })
        if (-not $lemma) { return $null }
        # "aiment le lait": the verb and what it is done to are one thing said ("aimer le lait"), whatever the article
        $atom = "v:$lemma"
        if ($Values.ContainsKey('o') -and $Values['o']) {
            $object = ConvertTo-LambekCategoryTerm -Text $Values['o'] -Language $Language -Object -Lemmas $Values['lemmas']
            if (-not $object) { $object = ConvertTo-LambekCategoryOpaque -Text $Values['o'] -Language $Language }
            if (-not $object) { return $null }
            $atom += ">$($object.Atoms -join '+')"
            $item.Written.Object = " $($Values['o'].Trim())"
        }
        $item.Predicate = [pscustomobject]@{ Atoms = @($atom) }
        $item.Verb = $true
        $item.Written.Predicate = $Values['v'].Trim()
    }
    # A question about who has no one named; anything else is about someone or about a kind of things
    if (-not $item.Predicate -or ($Kind -ne 'askwho' -and -not $item.Subject -and -not $item.Individual)) { return $null }
    # A plural said of a kind with no word of how many ("les chats aiment le lait", "cats like milk") is said of the kind,
    # not of every one: it holds "normalement", unless something told says otherwise. Only "tous", "aucun" and their
    # like say every one
    if ($Kind -in 'all', 'no' -and $item.Subject) {
        $articles = @((Get-LambekCategoryVocabulary -Language $Language).Data['Articles'] | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" })
        if (-not $item.Quantifier -or $item.Quantifier -in $articles) { $item.Default = $true }
    }
    return $item
}

function Get-LambekCategoryToken {
    param([string] $Text)

    # The words, plain, an elided word on its own: "l'animal" is "l" and "animal"
    return @((ConvertTo-LambekNormalizedText -Text $Text) -split "[\s'\u2019]+" | Where-Object { $_ })
}

function Split-LambekCategoryRelative {
    param([string] $Text, [string] $Language)

    # Where a kind ends and what is said of it after a relative pronoun begins: "personne qui a le droit" gives
    # "personne" and "a le droit". Read by the forms model of the language; nothing when there is no such pronoun
    # after a word, or no verb right after it (but what says not), or when it is said twice
    $model = Get-LambekFormModel -Language $Language
    if (-not $model -or $Text -notmatch '\p{L}') { return $null }
    $words = @($Text.Trim() -split '\s+' | Where-Object { $_ })
    if ($words.Count -lt 3) { return $null }
    $readings = @($model.Read([string[]] $words))
    if ($readings.Count -ne $words.Count) { return $null }
    # (read so in this part of the sentence, or a word its treebanks write so: "that" read alone may be another)
    $relative = {
        param($i)
        if ("$($readings[$i].Upos)" -eq 'PRON' -and "|$($readings[$i].Feats)|" -match '\|PronType=([^|]*,)?Rel(,|\|)') { return $true }
        $known = $null
        return [bool] ($model.Tags.TryGetValue("$($readings[$i].Form)".ToLowerInvariant(), [ref] $known) -and @($known | Where-Object { "$_" -match '^PRON\|' -and "$_" -match '(^|\|)PronType=([^|]*,)?Rel(,|\||$)' }).Count -gt 0)
    }
    $at = @(for ($i = 1; $i -lt $readings.Count - 1; $i++) { if (& $relative $i) { $i } })
    if ($at.Count -ne 1) { return $null }
    $next = $at[0] + 1
    while ($next -lt $readings.Count -and ("$($readings[$next].Upos)" -in 'ADV', 'PART') -and "|$($readings[$next].Feats)|" -match '\|Polarity=Neg\|') { $next++ }
    if ($next -ge $readings.Count) { return $null }
    # (a verb, or a word the tagger read otherwise here that its treebanks or its dictionary also give as a verb:
    # "dogs that bark")
    $tags = $null
    $form = "$($readings[$next].Form)".ToLowerInvariant()
    $tagged = $model.Tags.TryGetValue($form, [ref] $tags) -and @($tags | Where-Object { "$_".StartsWith('VERB|') }).Count -gt 0
    $listed = $model.Lexicon -and $model.Lexicon.Forms.ContainsKey($form) -and @($model.Lexicon.Forms[$form] | Where-Object { "$($_.Upos)" -eq 'VERB' }).Count -gt 0
    $verbal = "$($readings[$next].Upos)" -in 'VERB', 'AUX' -or $tagged -or $listed
    if (-not $verbal) { return $null }
    # (anyone the clause may be said of: a name its model reads as one, so that the sentence reads as about someone)
    return [pscustomobject]@{ Head = ($words[0..($at[0] - 1)] -join ' '); Clause = ($words[($at[0] + 1)..($words.Count - 1)] -join ' '); Someone = 'Rex' }
}

function ConvertTo-LambekCategoryTerm {
    param(
        [string] $Text,
        [string] $Language,
        # Said without its article ("chats" in "tous les chats")
        [switch] $Bare,

        # What a verb is done to ("le lait", "de lait" after "ne... pas")
        [switch] $Object,

        # The lemmas the words were read with in their sentence, for a word the dictionary does not know out of it
        [hashtable] $Lemmas,

        # One of several kinds may be said, joined by the word that says one of them ("un chien ou un chat")
        [switch] $Alternatives
    )

    # A kind of things, as the properties it puts together: "un chat noir de ma soeur" is chat, noir and "de ma soeur".
    # Every word must be one the dictionary knows as a noun or an adjective, each taken in its base form ("noires" is
    # "noir"), and none a small word of the language; what follows "de" is one property, whose it is said the same
    # from either side ("ma soeur", "votre soeur")
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $lexicon = Get-LambekLexicon -Language $Language
    $general = $lexicon.Dialogue['General']
    # One of several kinds ("un chien ou un chat", "noirs ou blancs"): each read as a kind, kept as one property
    # "or:chat;chien" that the clauses read as one or the other (ConvertTo-LambekCategoryClause); a reader that does not
    # know it takes it for a property of its own, and so concludes nothing from it
    $or = @(Get-LambekDisjunctionWord -Language $Language)
    $words = @($Text.Trim() -split '\s+' | Where-Object { $_ })
    if ($or.Count -gt 0 -and @($words | Where-Object { (ConvertTo-LambekNormalizedText -Text $_) -in $or }).Count -gt 0) {
        if (-not $Alternatives) { return $null }
        $parts = [System.Collections.Generic.List[string]]::new()
        $part = [System.Collections.Generic.List[string]]::new()
        foreach ($word in $words) {
            if ((ConvertTo-LambekNormalizedText -Text $word) -in $or) { $parts.Add(($part -join ' ')); $part.Clear() } else { $part.Add($word) }
        }
        $parts.Add(($part -join ' '))
        $each = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($said in $parts) {
            if (-not $said) { return $null }
            $term = ConvertTo-LambekCategoryTerm -Text $said -Language $Language -Bare:$Bare -Object:$Object -Lemmas $Lemmas
            if (-not $term -or @($term.Atoms | Where-Object { "$_" -match '[;&]' -or "$_".StartsWith('or:') }).Count -gt 0) { return $null }
            [void] $each.Add((@($term.Atoms | Sort-Object) -join '&'))
        }
        if ($each.Count -lt 2) { return $null }
        return [pscustomobject]@{ Atoms = @("or:$(@($each) -join ';')") }
    }
    # A kind said with what those of it do or are, after a pronoun that says which ("personne qui a le droit de vivre
    # en Europe", "chats that are black"): the kind before it, and what is said after it, together. The pronoun is the
    # one the tags of the language read as relative (PronType=Rel) and a verb follows it, so that it is the one doing
    # ("que Paul aime" is not read); what follows is read as a sentence about anyone would be
    $relative = Split-LambekCategoryRelative -Text $Text -Language $Language
    if ($relative) {
        $head = ConvertTo-LambekCategoryTerm -Text $relative.Head -Language $Language -Bare:$Bare -Object:$Object -Lemmas $Lemmas
        if (-not $head) { return $null }
        $clause = Read-LambekCategorySentence -Sentence "$($relative.Someone) $($relative.Clause)" -Language $Language
        if (-not $clause -or $clause.Kind -notin 'is', 'does' -or -not $clause.Predicate) { return $null }
        $together = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($atom in @($head.Atoms) + @($clause.Predicate.Atoms)) { [void] $together.Add("$atom") }
        return [pscustomobject]@{ Atoms = @($together) }
    }
    $tokens = @(Get-LambekCategoryToken -Text $Text)
    $articles = @($data['Articles'])
    if ($Object) { $articles = @($data['ObjectArticles']) }
    $article = $(if (@($articles).Count -gt 0) { "$(@($articles)[0])" } else { '' })
    if (-not $Bare -and $tokens.Count -gt 0 -and $tokens[0] -in $articles) { $article = $tokens[0]; $tokens = @($tokens | Select-Object -Skip 1) }
    # (an object may be said with two such small words, as "de la" in "de la viande": "some of the" said in one)
    if ($Object -and -not $Bare -and $tokens.Count -gt 1 -and $tokens[0] -in $articles) { $article = $tokens[0]; $tokens = @($tokens | Select-Object -Skip 1) }
    # (and the article a language puts before an adjective in the plural: "de" in "de grands tenors", where "des"
    # goes before the noun alone. Read so by the tags of the words in context, or the article the language was learned
    # to say after a negation, which is the same word ("n'a pas de poils"); only before an adjective in the plural,
    # "de Paris" keeps its "de")
    if (-not $Bare -and $tokens.Count -ge 3 -and $tokens[0] -notin $articles) {
        $forms = Get-LambekFormModel -Language $Language
        if ($forms) {
            $next = @($forms.Read([string[]] @($tokens)))
            $logic = Get-LambekLogicWord -Language $Language
            $tagged = $next.Count -gt 0 -and "$($next[0].Upos)" -eq 'DET' -and "|$($next[0].Feats)|" -match '\|PronType=Art\|'
            $negated = $logic -and $logic.Negated -and (ConvertTo-LambekNormalizedText -Text "$($logic.Negated)") -eq $tokens[0]
            $leading = $next.Count -eq $tokens.Count -and ($tagged -or $negated)
            if ($leading -and "$($next[1].Upos)" -eq 'ADJ' -and "|$($next[1].Feats)|" -match '\|Number=Plur\|') { $article = $tokens[0]; $tokens = @($tokens | Select-Object -Skip 1) }
        }
    }
    if ($tokens.Count -eq 0) { return $null }
    $of = -1
    for ($i = 1; $i -lt $tokens.Count; $i++) { if ($tokens[$i] -in @($data['Of'])) { $of = $i; break } }
    $head = @($tokens)
    $complement = @()
    if ($of -gt 0) { $head = @($tokens[0..($of - 1)]); $complement = @($tokens | Select-Object -Skip ($of + 1)) }
    if ($head.Count -gt 4) { return $null }
    $atoms = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    # (a language whose dialogue Lambek learned reads every sentence by its tags: each word is the lemma its forms model
    # read it with, the same in a rule and in a question, before any dictionary's; "gatos" is "gato" as "gato" is)
    $learned = [bool] $lexicon.Dialogue['Learned']
    $lemmaOf = [System.Collections.Generic.List[string]]::new()
    foreach ($token in $head) {
        if ($lexicon.StopWords.Contains($token)) { return $null }
        $lemma = $null
        if ($learned -and $Lemmas -and $Lemmas.ContainsKey($token)) { $lemma = $Lemmas[$token] }
        if (-not $lemma) { $lemma = Get-LambekCategoryLemma -Word $token -Language $Language }
        if (-not $lemma -and $Lemmas -and $Lemmas.ContainsKey($token)) { $lemma = $Lemmas[$token] }
        if (-not $lemma) { return $null }
        [void] $atoms.Add($lemma)
        $lemmaOf.Add($lemma)
    }
    # An adjective said with a noun says how one is for that kind of thing, not for any thing: "une grande souris" is a
    # souris, and grande, but for a souris; it is no "grand animal". The adjective is kept with its noun ("grand/souris")
    # as well as alone, so "grande" and "souris" follow from it and "grand animal" does not. Which word is the noun is
    # read by the tags of the forms model of the language; when it does not say one noun and adjectives, as before
    if ($head.Count -ge 2) {
        $model = Get-LambekFormModel -Language $Language
        if ($model) {
            # (read after an article, as a noun is said: alone, "insecte" may read as an adjective)
            $tags = @($model.Read([string[]] (@($article | Where-Object { $_ }) + @($head))) | ForEach-Object { "$($_.Upos)" })
            if ($article) { $tags = @($tags | Select-Object -Skip 1) }
            $nouns = @(for ($i = 0; $i -lt $tags.Count; $i++) { if ($tags[$i] -eq 'NOUN') { $i } })
            $adjectives = @(for ($i = 0; $i -lt $tags.Count; $i++) { if ($tags[$i] -eq 'ADJ') { $i } })
            if ($nouns.Count -eq 1 -and $adjectives.Count -ge 1 -and $nouns.Count + $adjectives.Count -eq $head.Count) {
                $noun = $lemmaOf[$nouns[0]]
                foreach ($i in $adjectives) { if ($lemmaOf[$i] -cne $noun) { [void] $atoms.Add("$($lemmaOf[$i])/$noun") } }
                # An adjective that takes away what the noun says, said before it: "un ancien etudiant" is no etudiant,
                # "a fake diamond" no diamond (after the noun, "les grecs anciens" are grecs). Only the adjective with
                # its noun is kept
                $taking = @($data['Privative'] | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" })
                $before = @($adjectives | Where-Object { $_ -lt $nouns[0] -and (ConvertTo-LambekNormalizedText -Text $lemmaOf[$_]) -in $taking })
                if ($before.Count -gt 0) {
                    [void] $atoms.Remove($noun)
                    foreach ($i in $before) { [void] $atoms.Remove($lemmaOf[$i]) }
                }
            }
        }
    }
    if ($of -gt 0) {
        $whose = @(foreach ($token in $complement) {
                if ($token -in @($general['Owners'])) { '@' }
                elseif ($token -notin @($data['Definite'])) { $token }
            })
        # (whose it is, and of whom: "de ma soeur", never "de ma" alone)
        if (@($whose | Where-Object { $_ -ne '@' }).Count -eq 0 -or $whose.Count -gt 4) { return $null }
        [void] $atoms.Add("of:$($whose -join ' ')")
    }
    return [pscustomobject]@{ Atoms = @($atoms) }
}

function Resolve-LambekCategoryPronoun {
    param([string] $Text, [string] $Language)

    # Who a pronoun of the third person stands for in a question ("aime-t-il le lait", "does he like milk"): the one
    # told of last whose gender and number agree with it, as the forms model reads them, the pronoun's own and those
    # of the words said of each one ("Marie est une etudiante" is feminine); a word read without them agrees with
    # any. Two told of in the same sentence, both agreeing: nobody, as nobody when nothing agrees. Only what was told
    # before, here or earlier in the message ("Tom est un chat. Il est noir."), never what is asked
    if ($script:CategoryResolving) { return $null }
    $model = Get-LambekFormModel -Language $Language
    if (-not $model) { return $null }
    $words = @($Text.Trim() -split '\s+' | Where-Object { $_ })
    if ($words.Count -ne 1) { return $null }
    $pronoun = @($model.Read([string[]] @($words[0])))
    if ($pronoun.Count -ne 1 -or "$($pronoun[0].Upos)" -ne 'PRON') { return $null }
    $feats = "|$($pronoun[0].Feats)|"
    if ($feats -notmatch '\|Person=3\|' -or $feats -notmatch '\|PronType=Prs\|') { return $null }
    $feature = { param($text, $name) if ($text -match "\|$name=(\w+)\|") { $Matches[1] } else { '' } }
    $gender = & $feature $feats 'Gender'
    $number = & $feature $feats 'Number'
    # (one told of is never "ils" or "they": several are, which the rules read here do not keep together)
    if ($number -eq 'Plur') { return $null }
    $script:CategoryResolving = $true
    try { $known = @(Get-LambekCategoryKnown -Language $Language) + @($(if ($null -ne $script:CategoryMessage) { $script:CategoryMessage })) }
    finally { $script:CategoryResolving = $false }
    $found = $null
    $from = $null
    for ($i = $known.Count - 1; $i -ge 0; $i--) {
        $item = $known[$i].Item
        if (-not $item.Individual -or "$($item.Individual.Key)" -eq 'speaker') { continue }
        # (the gender and number of what is said of the one: its article, adjective or noun)
        $said = "$($item.Written.Predicate) $($item.Written.Object)".Trim()
        $theirs = "|" + (@($(if ($said) { $model.ReadText($said) }) | ForEach-Object { "$($_.Feats)" }) -join '|') + "|"
        $other = @([regex]::Matches($theirs, '\|Gender=(\w+)\|') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $plural = @([regex]::Matches($theirs, '\|Number=(\w+)\|') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        if ($gender -and $other.Count -eq 1 -and $other[0] -ne $gender) { continue }
        if ($number -and $plural.Count -eq 1 -and $plural[0] -ne $number) { continue }
        if ($null -eq $found) { $found = $item.Individual; $from = $known[$i].Fact; continue }
        # (another one, agreeing too, told in the same sentence: which is not said)
        if ([object]::ReferenceEquals($known[$i].Fact, $from) -and "$($item.Individual.Key)" -ne "$($found.Key)") { return $null }
        break
    }
    return $found
}

function ConvertTo-LambekCategoryIndividual {
    param([string] $Text, [string] $Language, [switch] $Listener, [hashtable] $Lemmas)

    # The one a sentence is about: the user ("je"; "vous" when Lambek says it), a name ("Minou", "Jean Dupont"),
    # or someone said with whose or which it is ("ma soeur", "le chat"). A pronoun, or something said with "un", is none
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $written = $Text.Trim()
    $plain = (ConvertTo-LambekNormalizedText -Text $written).Trim()
    $me = @($data['Speaker']); $you = @($data['Addressee'])
    if ($Listener) { $me, $you = $you, $me }
    if ($plain -in $me) { return [pscustomobject]@{ Key = 'speaker'; Written = $written } }
    if ($plain -in $you) { return $null }
    $small = @($general['Determiners']) + @($general['Pronouns']) + @($general['Speakers']) + @($general['Addressee']) + @($data['Articles'])
    $tokens = @(Get-LambekCategoryToken -Text $written)
    if ($tokens.Count -eq 0) { return $null }
    if ($written -cmatch '^\p{Lu}[\p{L}-]*(?: \p{Lu}[\p{L}-]*){0,2}$' -and $tokens[0] -notin $small) {
        return [pscustomobject]@{ Key = "name:$($tokens -join ' ')"; Written = $written }
    }
    if ($tokens.Count -lt 2 -or $tokens.Count -gt 4) { return $null }
    if ($tokens[0] -notin @($general['Owners']) -and $tokens[0] -notin @($data['Definite'])) { return $null }
    foreach ($token in @($tokens | Select-Object -Skip 1)) { if (-not (Get-LambekCategoryLemma -Word $token -Language $Language) -and -not ($Lemmas -and $Lemmas.ContainsKey($token))) { return $null } }
    $key = @(foreach ($token in $tokens) { if ($token -in @($general['Owners'])) { '@' } elseif ($token -notin @($data['Definite'])) { $token } })
    return [pscustomobject]@{ Key = "the:$($key -join ' ')"; Written = $written }
}

function Get-LambekCategoryImplied {
    param([object[]] $Items, [string] $Language)

    # Someone said with "le", "ce" or whose it is ("le cerisier", "this shape", "ma soeur") is of the kind its words
    # name: a sentence "is", read from those words alone. Names and the user are not
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $general = (Get-LambekLexicon -Language $Language).Dialogue['General']
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($item in $Items) {
        $one = $item.Individual
        if (-not $one -or -not "$($one.Key)".StartsWith('the:') -or -not $seen.Add("$($one.Key)")) { continue }
        $tokens = @(Get-LambekCategoryToken -Text $one.Written)
        if ($tokens.Count -lt 2 -or ($tokens[0] -notin @($data['Definite']) -and $tokens[0] -notin @($general['Owners']))) { continue }
        $term = ConvertTo-LambekCategoryTerm -Text (@($tokens | Select-Object -Skip 1) -join ' ') -Language $Language -Bare
        if (-not $term -or @($term.Atoms).Count -eq 0) { continue }
        [pscustomobject]@{
            Kind = 'is'; Quantifier = ''; Subject = $null; Individual = $one; Predicate = $term; Verb = $false; Member = $false; Default = $false
            Written = [pscustomobject]@{ Subject = $one.Written; Predicate = ''; Object = '' }
        }
    }
}

function Get-LambekCategoryCircle {
    param([object[]] $Items, [string] $Language)

    # What a word is a kind of, from the dictionary learned (WordNet and its wordnets): told "Minou est un siamois" and
    # "tous les chats sont noirs", the dictionary says a siamois is a kind of chat, so the rule about chats is about
    # Minou too. Only the way up is followed (every chat is an animal, not every animal a chat), so what is added is
    # always true where the dictionary is right; it is said in the answer, and kept apart from what was told
    # (the kinds of a word are in the dictionary and nowhere else: without it, the words learned know no kinds)
    $dictionary = Get-LambekDictionary -Language $Language
    if ($dictionary -isnot [LambekDictionary]) { return }
    # What is said of someone, and what the rules are about: a rule is only brought nearer, never made up
    $below = [System.Collections.Generic.List[string]]::new()
    $above = [System.Collections.Generic.List[string]]::new()
    # What each one is already said to be, and which kind the rules told already lead from one to another
    # ("toutes les roses sont des fleurs"): the dictionary fills a gap, it never takes the place of a sentence told
    $said = @{}
    $leads = @{}
    foreach ($item in $Items) {
        if ($item.Kind -in 'is', 'isnot', 'askis' -and $item.Individual -and $item.Predicate) {
            # (each of several kinds one is said to be one of is looked up too: "un siamois ou un persan")
            foreach ($atom in @($item.Predicate.Atoms)) { if ("$atom") { foreach ($one in (Get-LambekCategoryAtomPart -Atom "$atom")) { $below.Add("$one") } } }
            if ($item.Kind -eq 'is') {
                $who = "$($item.Individual.Key)"
                if (-not $said.ContainsKey($who)) { $said[$who] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
                foreach ($atom in @($item.Predicate.Atoms)) { if ("$atom") { [void] $said[$who].Add("$atom") } }
            }
        }
        if ($item.Kind -in 'all', 'no', 'some', 'somenot' -and $item.Subject) {
            foreach ($atom in @($item.Subject.Atoms)) { if ("$atom") { $above.Add("$atom") } }
        }
        # (only "every one of a kind is" carries from one kind to another, and only a rule that always holds)
        if ($item.Kind -eq 'all' -and $item.Subject -and $item.Predicate -and -not ($item.PSObject.Properties['Default'] -and $item.Default)) {
            foreach ($from in @($item.Subject.Atoms)) {
                if (-not "$from") { continue }
                if (-not $leads.ContainsKey("$from")) { $leads["$from"] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
                foreach ($to in @($item.Predicate.Atoms)) { if ("$to") { [void] $leads["$from"].Add("$to") } }
            }
        }
    }
    # Whether the rules told already lead from one kind to another, by however many steps
    $reaches = {
        param([string] $from, [string] $to)
        $seenHere = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $queue = [System.Collections.Generic.Queue[string]]::new()
        $queue.Enqueue($from)
        [void] $seenHere.Add($from)
        while ($queue.Count -gt 0) {
            $step = $queue.Dequeue()
            if (-not $leads.ContainsKey($step)) { continue }
            foreach ($next in $leads[$step]) {
                if ($next -ceq $to) { return $true }
                if ($seenHere.Add($next)) { $queue.Enqueue($next) }
            }
        }
        return $false
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($under in @($below | Select-Object -Unique)) {
        foreach ($over in @($above | Select-Object -Unique)) {
            if ($under -ceq $over -or -not $seen.Add("$under`t$over")) { continue }
            # What was told comes first: someone already said to be both, or rules told that already lead from the one
            # to the other, need no dictionary. An answer must rest on the sentences the user told, not on a word in a book
            if (@($said.Values | Where-Object { $_.Contains($under) -and $_.Contains($over) }).Count -gt 0) { continue }
            if (& $reaches $under $over) { continue }
            # (the same two words are asked about again and again in a conversation: the way up is walked once)
            if ($null -eq $script:CategoryCircles) { $script:CategoryCircles = @{} }
            $key = "$Language`t$under`t$over"
            if (-not $script:CategoryCircles.ContainsKey($key)) {
                $script:CategoryCircles[$key] = $dictionary.Under($under, $over, $Language, 'n', $script:CategoryCircleSenses, $script:CategoryCircleHops)
            }
            if ($script:CategoryCircles[$key] -le 0) { continue }
            [pscustomobject]@{
                Kind = 'all'; Quantifier = ''; Individual = $null; Verb = $false; Member = $false; Default = $false
                Subject = [pscustomobject]@{ Atoms = @($under) }
                Predicate = [pscustomobject]@{ Atoms = @($over) }
                Written = [pscustomobject]@{ Subject = $under; Predicate = $over; Object = '' }
                Circle = [pscustomobject]@{ Under = $under; Above = $over }
            }
        }
    }
}

function Format-LambekCategoryCircle {
    param([pscustomobject] $Circle, [string] $Language)

    # What the dictionary says, said plainly, with the words as the dictionary writes them: a language that has learned
    # no sentence for it names the two words alone
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $named = Get-LambekDictionarySource -Language $Language
    if ($data.Contains('Circle') -and "$($data['Circle'])") { return ($data['Circle'] -f $Circle.Under, $Circle.Above, $named) }
    return "$($Circle.Under) -> $($Circle.Above) ($named)"
}

function Get-LambekDictionarySource {
    param([string] $Language)

    # The dictionary a kind of a word was found in, by its name: the wordnet of the language, which gives the meanings of
    # its words, and the one that links the meanings ("WOLF 1.0b, Open English WordNet 2022"); each once
    $dictionary = Get-LambekDictionary -Language $Language
    if ($dictionary -isnot [LambekDictionary]) { return '' }
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($kind in @($Language, 'graph')) {
        $own = $null
        if (-not $dictionary.SourcesOf.TryGetValue($kind, [ref] $own) -or $own.Count -eq 0) { continue }
        # (the first source of a file is the wordnet it was built from; the others give the forms of the words)
        $name = (("$($own[0])" -split ',')[0] -replace '\s+from\s.*$', '').Trim()
        if ($name -and -not $names.Contains($name)) { $names.Add($name) }
    }
    return ($names -join ', ')
}

function Get-LambekCategoryLemma {
    param([string] $Word, [string] $Language, [switch] $Verb)

    # The base form of a word: of an adjective, else of a noun ("grises" is "gris", "hommes" is "homme"); or, for a verb,
    # the verb it is a form of ("volent" is "voler"), never "etre" or "avoir" (they are the sentence, not what it says)
    if ($null -eq $script:CategoryLemmas) { $script:CategoryLemmas = @{} }
    $key = "$Language|$([bool] $Verb)|$Word"
    if ($script:CategoryLemmas.ContainsKey($key)) { return $script:CategoryLemmas[$key] }
    $lemma = $null
    $dictionary = Get-LambekDictionary -Language $Language
    if ($dictionary -and $Word -match '^\p{L}+(?:-\p{L}+)*$') {
        $known = @($dictionary.Lemmas($Word, $Language))
        $plain = { param($entry) ConvertTo-LambekNormalizedText -Text "$($entry.Lemma)" }
        if ($Verb) {
            $not = @((Get-LambekCategoryVocabulary -Language $Language).Data['NotVerbs'])
            $found = @($known | Where-Object { $_.Pos -eq 'v' -and (& $plain $_) -notin $not } | Select-Object -First 1)
            if ($found.Count -gt 0) { $lemma = & $plain $found[0] }
        }
        else {
            $adjectives = @($known | Where-Object { $_.Pos -eq 'a' })
            $nouns = @($known | Where-Object { $_.Pos -eq 'n' })
            if ($adjectives.Count -gt 0) {
                # (the shortest: "grise" is a form of "gris" before it is a word of its own)
                $lemma = & $plain (@($adjectives | Sort-Object -Stable { "$($_.Lemma)".Length })[0])
            }
            elseif ($nouns.Count -gt 0) {
                $lemma = & $plain (@($nouns | Sort-Object -Stable { "$($_.Lemma)".Length })[0])
            }
        }
    }
    $script:CategoryLemmas[$key] = $lemma
    return $lemma
}

function Get-LambekCategorySignature {
    param([pscustomobject] $Item)

    # What a sentence says, the same whatever words said it: to see that a sentence said back reads the same
    $who = ''
    if ($Item.Individual) { $who = $Item.Individual.Key }
    elseif ($Item.Subject) { $who = ($Item.Subject.Atoms -join '+') }
    $usual = $(if ($Item.PSObject.Properties['Default'] -and $Item.Default) { 'usual:' } else { '' })
    return "$usual$($Item.Kind)|$who|$($Item.Predicate.Atoms -join '+')"
}

function Get-LambekCategoryConclusion {
    param([pscustomobject] $Item, [string] $Shape, [switch] $Usual)

    # What an answer says, in the shape of a thing told: "Socrate est-il mortel ?" answered yes is
    # "category(is|name:socrate|mortel)", answered "normalement oui" is "category(usual:is|name:tweety|v:voler)"
    $said = $Item.PSObject.Copy()
    $said.Kind = $Shape
    $said | Add-Member -NotePropertyName Default -NotePropertyValue ([bool] $Usual) -Force
    return "category($(Get-LambekCategorySignature -Item $said))"
}

function Get-LambekCategoryKnown {
    param([string] $Language, [switch] $Shape)

    # What was told, here and before, read as general rules and sentences about someone: each with the thing told it
    # comes from. Only what reads as one counts; rules told with "si" are another kind of thing
    $told = @((Get-LambekTold).ToArray())
    $here = @($told | Where-Object { $_.PSObject.Properties['Hash'] -and $_.Hash } | ForEach-Object { $_.Hash })
    $before = @((Get-LambekToldJournal).ToArray() | Where-Object { $_.Hash -notin $here })
    # (a sentence is read with what was told with it, the names and the words said: read again once more is told)
    $context = (@($told | Where-Object { $_.PSObject.Properties['Core'] } | ForEach-Object { "$($_.Core)" }) -join "`n")
    foreach ($fact in @($before) + @($told)) {
        if ($fact.PSObject.Properties['Condition'] -and $fact.Condition) { continue }
        if ($fact.PSObject.Properties['Deduced'] -and $fact.Deduced) { continue }
        if ($fact.PSObject.Properties['Replaced'] -and $fact.Replaced) { continue }
        if ("$($fact.Language)" -ne $Language -or -not $fact.Text) { continue }
        # (one compared with another is no thing one is: "Rex est plus grand que Max" says nothing of "grand")
        if ($fact.PSObject.Properties['Core'] -and "$($fact.Core)".StartsWith('compare(')) { continue }
        $words = "$($fact.Text)"
        if ($fact.PSObject.Properties['Said'] -and $fact.Said) { $words = "$($fact.Said)" }
        $sentence = ((($words.Trim() -replace '[.!;]+\s*$', '') -replace ',', ' ') -replace '\s+', ' ').Trim()
        if (-not (Test-LambekCategoryWording -Text $sentence)) { continue }
        if ($null -eq $script:CategoryReadings) { $script:CategoryReadings = @{} }
        $key = "$Language|$([bool] $Shape)|$sentence|$context"
        if (-not $script:CategoryReadings.ContainsKey($key)) { $script:CategoryReadings[$key] = Read-LambekCategorySentence -Sentence $sentence -Language $Language -Shape:$Shape }
        $read = $script:CategoryReadings[$key]
        if (-not $read -or "$($read.Kind)".StartsWith('ask')) { continue }
        [pscustomobject]@{ Fact = $fact; Item = $read }
    }
}

function ConvertTo-LambekCategoryFact {
    param([pscustomobject] $Sentence, [pscustomobject] $Item, [string] $Language)

    # A sentence of the message, kept as a thing told, in the shape of every thing told; one told of with a pronoun is
    # kept with the name it stands for too, so that it reads alone after ("Il est noir" is "Tom est noir")
    $signature = Get-LambekCategorySignature -Item $Item
    $said = $null
    if ($Item.PSObject.Properties['Pronoun'] -and $Item.Pronoun) {
        $said = ([regex] "(?i)(?<![\p{L}])$([regex]::Escape("$($Item.Pronoun)"))(?![\p{L}])").Replace("$($Sentence.Original)", "$($Item.Written.Subject)", 1)
    }
    $fact = [pscustomobject]@{
        Action     = 'verb:category'
        Parameters = [ordered]@{}
        What       = $Sentence.Original
        Agent      = 'other'
        Name       = ''
        Wish       = $false
        Time       = $null
        Day        = $null
        Told       = $null
        Text       = $(if ($said) { $said } else { $Sentence.Original })
        Said       = $said
        Language   = $Language
        Hash       = $null
        Negated    = $false
        Core       = "category($signature)|"
        Form       = "category($signature)"
    }
    if ($Sentence.PSObject.Properties['Joined'] -and $Sentence.Joined) { $fact | Add-Member -NotePropertyName Joined -NotePropertyValue "$($Sentence.Joined)" }
    return $fact
}

function Get-LambekCategorySaid {
    param([pscustomobject] $Fact, [string] $Register = 'vous')

    # A general rule told, said back from the other side ("tous les chats de votre soeur sont noirs"), kept only when
    # reading it again gives the same; nothing otherwise (it is then quoted as it was told)
    $sentence = ConvertTo-LambekOtherSide -Text "$($Fact.Text)" -Language "$($Fact.Language)" -Register $Register
    if (-not $sentence) { return $null }
    $plain = { param($text) (((("$text".Trim()) -replace '[.!;]+\s*$', '') -replace ',', ' ') -replace '\s+', ' ').Trim() }
    $told = Read-LambekCategorySentence -Sentence (& $plain $Fact.Text) -Language "$($Fact.Language)"
    $again = Read-LambekCategorySentence -Sentence (& $plain $sentence) -Language "$($Fact.Language)" -Listener
    if (-not $told -or -not $again -or (Get-LambekCategorySignature -Item $told) -cne (Get-LambekCategorySignature -Item $again)) { return $null }
    return $sentence
}

function Get-LambekCategoryAtomPart {
    param([string] $Atom)

    # The properties a property is made of: itself, or each of several kinds one is one of ("or:chat;chien")
    if ($Atom.StartsWith('or:')) { return @($Atom.Substring(3) -split '[;&]' | Where-Object { $_ }) }
    return @($Atom)
}

function ConvertTo-LambekCategoryClause {
    param([string[]] $Atoms, [scriptblock] $Index, [switch] $Not)

    # What a term says, as clauses that must all hold: each property alone ("chat", "noir": one clause each), and one of
    # several kinds, "or:chat;chien", as one clause that one of them holds (with a kind of several words, chat&noir, one
    # clause for each way of taking one word from each). Said not: one clause that one of its properties does not hold,
    # one of several kinds taken as none of them
    $plain = [System.Collections.Generic.List[int]]::new()
    $either = [System.Collections.Generic.List[object]]::new()
    foreach ($atom in $Atoms) {
        if ("$atom".StartsWith('or:')) { $either.Add(@("$atom".Substring(3) -split ';' | ForEach-Object { , [int[]] @($_ -split '&' | ForEach-Object { & $Index $_ }) })) }
        else { $plain.Add((& $Index $atom)) }
    }
    # (one clause for each way of taking one from each list: "a or b" with "c or d" is four clauses... of one
    # literal from each)
    $product = {
        param([object[]] $lists)
        $out = [System.Collections.Generic.List[int[]]]::new()
        $out.Add([int[]] @())
        foreach ($list in $lists) {
            $next = [System.Collections.Generic.List[int[]]]::new()
            foreach ($done in $out) { foreach ($more in $list) { $next.Add([int[]] (@($done) + @($more) | Select-Object -Unique)) } }
            $out = $next
        }
        , $out.ToArray()
    }
    if (-not $Not) {
        $clauses = [System.Collections.Generic.List[int[]]]::new()
        foreach ($literal in $plain) { $clauses.Add([int[]] @($literal)) }
        foreach ($alternatives in $either) {
            foreach ($clause in (& $product @(foreach ($alternative in $alternatives) { , [object[]] @($alternative | ForEach-Object { , [int[]] @($_) }) }))) { $clauses.Add($clause) }
        }
        return , $clauses.ToArray()
    }
    # Not: one of the properties fails. Each part as clauses of its own (a property: one clause, its opposite; one of
    # several kinds: none of them, one clause each), then one clause for each way of taking one clause from each part
    $parts = [System.Collections.Generic.List[object]]::new()
    foreach ($literal in $plain) { $parts.Add([object[]] @(, [int[]] @(- $literal))) }
    foreach ($alternatives in $either) { $parts.Add([object[]] @(foreach ($alternative in $alternatives) { , [int[]] @($alternative | ForEach-Object { - $_ }) })) }
    return , (& $product $parts.ToArray())
}

function ConvertTo-LambekCategoryStatement {
    param([pscustomobject] $Item, [hashtable] $Atoms)

    # A sentence as clauses (see Category.cs): every one of a kind, one named, or one imagined for "certains"
    $table = $Atoms
    $index = { param($atom) if (-not $table.ContainsKey($atom)) { $table[$atom] = $table.Count + 1 }; [int] $table[$atom] }
    $s = @(); if ($Item.Subject) { $s = @($Item.Subject.Atoms | ForEach-Object { & $index $_ }) }
    $notS = @($s | ForEach-Object { - $_ })
    $p = ConvertTo-LambekCategoryClause -Atoms @($Item.Predicate.Atoms) -Index $index
    $notP = ConvertTo-LambekCategoryClause -Atoms @($Item.Predicate.Atoms) -Index $index -Not
    $statement = [LambekCategoryStatement]::new()
    # (a rule that holds "normalement" is no clause: it is used only where nothing told says otherwise)
    if ($Item.PSObject.Properties['Default'] -and $Item.Default) { return $statement }
    switch ($Item.Kind) {
        'all' { foreach ($clause in $p) { $statement.AddEvery([int[]] (@($notS) + @($clause))) } }
        'no' { foreach ($clause in $notP) { $statement.AddEvery([int[]] (@($notS) + @($clause))) } }
        'some' { $w = $statement.AddWitness(); foreach ($atom in $s) { $statement.AddToWitness($w, [int[]] @($atom)) }; foreach ($clause in $p) { $statement.AddToWitness($w, $clause) } }
        'somenot' { $w = $statement.AddWitness(); foreach ($atom in $s) { $statement.AddToWitness($w, [int[]] @($atom)) }; foreach ($clause in $notP) { $statement.AddToWitness($w, $clause) } }
        { $_ -in 'is', 'does' } { foreach ($clause in $p) { $statement.AddNamed($Item.Individual.Key, $clause) } }
        { $_ -in 'isnot', 'doesnot' } { foreach ($clause in $notP) { $statement.AddNamed($Item.Individual.Key, $clause) } }
    }
    return $statement
}

function Get-LambekCategoryOpposite {
    param([pscustomobject] $Item, [hashtable] $Atoms, [string] $Individual, [switch] $No)

    # What would make the answer wrong, as clauses: for "yes", that it does not hold; for "no", that it does.
    # "Minou est-il noir ?": yes when Minou not noir cannot be; no when Minou noir cannot be
    $table = $Atoms
    $index = { param($atom) if (-not $table.ContainsKey($atom)) { $table[$atom] = $table.Count + 1 }; [int] $table[$atom] }
    $s = @(); if ($Item.Subject) { $s = @($Item.Subject.Atoms | ForEach-Object { & $index $_ }) }
    $notS = @($s | ForEach-Object { - $_ })
    $p = ConvertTo-LambekCategoryClause -Atoms @($Item.Predicate.Atoms) -Index $index
    $notP = ConvertTo-LambekCategoryClause -Atoms @($Item.Predicate.Atoms) -Index $index -Not
    $o = [LambekCategoryStatement]::new()
    $witness = { param([int[]] $units, [object[]] $clauses) $w = $o.AddWitness(); foreach ($atom in $units) { $o.AddToWitness($w, [int[]] @($atom)) }; foreach ($clause in $clauses) { $o.AddToWitness($w, [int[]] $clause) } }
    $every = { param([object[]] $clauses) foreach ($clause in $clauses) { $o.AddEvery([int[]] (@($notS) + @($clause))) } }
    $kind = $Item.Kind
    if ($kind -in 'askis', 'askdoes', 'askwho') {
        # (each clause whole: one of several kinds asked is one clause, never one for each)
        $clauses = $notP
        if ($No) { $clauses = $p }
        foreach ($clause in $clauses) { $o.AddNamed($Individual, [int[]] $clause) }
    }
    elseif ($kind -eq 'askall') {
        if ($No) { & $every $p } else { & $witness $s $notP }
    }
    elseif ($kind -eq 'asksome') {
        if ($No) { & $witness $s $p } else { & $every $notP }
    }
    elseif ($kind -eq 'asksomenot') {
        if ($No) { & $witness $s $notP } else { & $every $p }
    }
    elseif ($kind -eq 'askno') {
        if ($No) { & $every $notP } else { & $witness $s $p }
    }
    return $o
}

function Get-LambekCategorySentence {
    param(
        [pscustomobject] $Item,
        [string] $Shape,
        [string] $Language,
        [string] $Subject = '',
        # Which shapes: the sentences of answers, or the questions Lambek asks ("Asks")
        [string] $Shapes = 'Sentences',
        # Said from the user's side, as it is kept when told: "ma soeur", "je"
        [switch] $Plain
    )

    # The sentence of an answer, made with the user's own words of the question, then said from the other side:
    # "Minou est-il noir ?" gives "Minou est noir", "suis-je mortel ?" gives "vous etes mortel". Nothing when the
    # language has no sentence for it
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $sentences = $(if ($Shapes -eq 'Imagine') { $data['Imagine']['Sentences'] } else { $data[$Shapes] })
    $who = $(if ($Subject) { $Subject } else { $Item.Written.Subject })
    $key = $Shape
    if ($Item.Verb) { $key = $(switch ($Shape) { 'is' { 'does' } 'isnot' { 'doesnot' } default { "$($Shape)do" } }) }
    elseif ($Item.PSObject.Properties['Member'] -and $Item.Member -and $Shape -in 'is', 'isnot') { $key = $(if ($Shape -eq 'is') { 'member' } else { 'notmember' }) }
    $candidates = @()
    # ("qui vole ?" is answered with its own verb: "Tweety vole", "Tweety flies")
    # ("qui vole ?" is answered with its own verb: "Tweety vole", "Tweety flies"; a language that learned no sentence
    # of its own for it says a doing the way it says any other, "Rex blaft")
    if ($Item.Kind -eq 'askwho' -and $Item.Verb -and $Shape -eq 'is') { $candidates += 'whodo' }
    if ($Item.Quantifier) { $candidates += "$key|$($Item.Quantifier)" }
    $speaker = $Item.Individual -and $Item.Individual.Key -eq 'speaker' -and -not $Subject
    if ($speaker) { $candidates += "$key|$(@($data['Speaker'])[0])" }
    if ($Shape -in 'is', 'isnot' -or $key -in 'member', 'notmember') { $candidates += $key }
    $template = $null
    foreach ($candidate in $candidates) { if ($sentences.Contains($candidate) -and "$($sentences[$candidate])") { $template = $sentences[$candidate]; break } }
    if (-not $template) { return $null }
    # (a verb that changes what is said, or helps another into a past, is said as it was, without the word the language
    # says "does" with: "Klaus can travel", not "Klaus does can travel"; "Tom has eaten"; and what says not after it:
    # "Tom has not eaten")
    if ($Item.Verb -and $key -in 'does', 'doesnot') {
        $model = Get-LambekFormModel -Language $Language
        $said = "$($Item.Written.Predicate)".Trim()
        if ($model -and $said -and $said -notmatch '\s') {
            # (read with the first word of what follows it: "can travel" is said so, "have a sensor" is not)
            $next = @("$($Item.Written.Object)".Trim() -split '\s+' | Where-Object { $_ } | Select-Object -First 1)
            $reading = @($model.Read([string[]] (@($said) + $next)))
            $support = @(Get-LambekCategorySupport -Language $Language)
            if ($next.Count -eq 1 -and $reading.Count -eq 2 -and "$($reading[0].Upos)" -eq 'AUX' -and $support.Count -gt 0 -and
                "|$($reading[1].Feats)|" -match '\|VerbForm=(Inf|Part)\|' -and
                (ConvertTo-LambekNormalizedText -Text "$($reading[0].Lemma)") -notin $support) {
                # (the words before the verb: those of the helper "does" go, the others, "not", come after it)
                $between = [regex]::Match($template, '\{0\}(?<w>.*?)\{1\}')
                if ($between.Success) {
                    $kept = @(foreach ($word in @($between.Groups['w'].Value.Trim() -split '\s+' | Where-Object { $_ })) {
                            $lemma = @($model.Read([string[]] @($word)))
                            if ($lemma.Count -eq 1 -and (ConvertTo-LambekNormalizedText -Text "$($lemma[0].Lemma)") -in $support) { continue }
                            $word
                        })
                    $template = $template.Substring(0, $between.Index) + '{0} {1}' + $(if ($kept.Count -gt 0) { ' ' + ($kept -join ' ') } else { '' }) + $template.Substring($between.Index + $between.Length)
                }
            }
        }
    }
    $object = "$($Item.Written.Object)"
    # (what is not done to takes the article the language puts after a negation, learned: "n'a pas de poils")
    if ($Item.Verb -and $key -match 'not' -and $object.Trim()) { $object = ConvertTo-LambekNegatedObject -Object $object -Language $Language }
    $built = $template -f $who, $Item.Written.Predicate, $object
    foreach ($rule in @($data['Elide'])) { $built = [regex]::Replace($built, $rule[0], $rule[1]) }
    if ($Plain) { return $built }
    $turned = ConvertTo-LambekOtherSide -Text $built -Language $Language -Register 'vous'
    if (-not $turned) { return $built }
    if ($Shapes -ne 'Asks') { $turned = $turned.TrimEnd('.') }
    # (a sentence made with a small word first says it small; a name keeps its capital)
    if ($built -cmatch '^\p{Ll}') { $turned = $turned.Substring(0, 1).ToLowerInvariant() + $turned.Substring(1) }
    return $turned
}

function ConvertTo-LambekNegatedObject {
    # What is done to, after a negation: its indefinite article (DET, Definite=Ind) becomes the one the language was seen
    # to put after a negation, cut before the letters it was seen cut before ("des poils": "de poils", "des ailes":
    # "d'ailes"). As it was when the language learned none ("does not have a tail")
    param([string] $Object, [string] $Language)

    $logic = Get-LambekLogicWord -Language $Language
    $model = Get-LambekFormModel -Language $Language
    if (-not $logic -or -not $logic.Negated -or -not $model) { return $Object }
    $found = [regex]::Match($Object, '^(?<space>\s*)(?<article>\S+)\s+(?<rest>\S.*)$')
    if (-not $found.Success) { return $Object }
    # (the words as they are written: "des" read whole, not cut as "de les")
    $words = @($model.Read([string[]] @("$($found.Groups['article'].Value) $($found.Groups['rest'].Value)" -split '\s+')))
    if ($words.Count -lt 2) { return $Object }
    $first = $words[0]
    if ($first.Upos -ne 'DET' -or "|$($first.Feats)|" -notlike '*|Definite=Ind|*') { return $Object }
    $rest = $found.Groups['rest'].Value
    $letter = $rest.Substring(0, 1).ToLowerInvariant()
    if ($logic.Elided.ContainsKey($letter)) { return $found.Groups['space'].Value + $logic.Elided[$letter] + $rest }
    return $found.Groups['space'].Value + $logic.Negated + ' ' + $rest
}

function Resolve-LambekCategoryMessage {
    param(
        [object[]] $Sentences,
        [string] $Language,
        # What is told with the question is said back first ("C'est note. Tom est un chat."), then the answer
        [switch] $Noted
    )

    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $say = (Get-LambekLexicon -Language $Language).Dialogue.Say
    $quantified = 'all', 'no', 'some', 'somenot'
    # Nothing general, here or before: the sentences are for the rest of Lambek
    $shapes = @(foreach ($sentence in $Sentences) { (Read-LambekCategorySentence -Sentence $sentence.Text -Language $Language -Question:$sentence.Question -Shape).Kind })
    $asks = @($shapes | Where-Object { "$_".StartsWith('ask') })
    if ($asks.Count -gt 1) { return $null }
    $general = @($shapes | Where-Object { $_ -in $quantified }).Count -gt 0
    # (one question whether someone is something may be answered from what was told of that one alone: "Tom est-il un chat ?")
    $individual = $asks.Count -eq 1 -and $asks[0] -eq 'askis'
    # A language whose dialogue is learned has no memory of its own yet: what is told of someone is kept here, for the
    # rules told after it ("Rex ist ein Hund", then "jeder Hund ist ein Tier")
    if ((Get-LambekLexicon -Language $Language).Dialogue['Learned']) { $individual = $true }
    # (what is told in the place of something told before is about what was told, whatever rules there are)
    $correcting = @($Sentences | Where-Object { $_.PSObject.Properties['Correcting'] -and $_.Correcting }).Count -gt 0
    if ($correcting) { $individual = $true }
    # (several things told in one message, and nothing asked: each read here, as nothing else reads them together)
    $several = @($Sentences).Count -gt 1 -and $asks.Count -eq 0
    if ($several) { $individual = $true }
    # (one of several kinds said, "Rex est un chien ou un chat": read here, as nothing else reads it)
    $or = @(Get-LambekDisjunctionWord -Language $Language)
    if ($or.Count -gt 0 -and @($Sentences | Where-Object { @("$($_.Text)" -split '\s+' | Where-Object { (ConvertTo-LambekNormalizedText -Text $_) -in $or }).Count -gt 0 }).Count -gt 0) { $individual = $true }
    if (-not $general -and -not $individual -and @(Get-LambekCategoryKnown -Language $Language -Shape | Where-Object { $_.Item.Kind -in $quantified }).Count -eq 0) { return $null }

    # Each sentence read, with the dictionary: every one must read, or nothing is taken. A pronoun stands for one told
    # of before it, here or before
    $script:CategoryMessage = [System.Collections.Generic.List[object]]::new()
    try {
        $items = @(foreach ($sentence in $Sentences) {
                $read = Read-LambekCategorySentence -Sentence $sentence.Text -Language $Language -Question:$sentence.Question
                if (-not $read) { return $null }
                $entry = [pscustomobject]@{ Sentence = $sentence; Item = $read; Fact = $sentence }
                if (-not "$($read.Kind)".StartsWith('ask')) { $script:CategoryMessage.Add($entry) }
                $entry
            })
    }
    finally { $script:CategoryMessage = $null }
    $known = @(Get-LambekCategoryKnown -Language $Language)
    # (the shape of a sentence only said what it may be: what it is read as says whether it is general)
    $general = @($items | Where-Object { $_.Item.Kind -in $quantified }).Count -gt 0
    # Without any general rule, only a question whether someone is a kind of thing ("Tom est-il un chat ?"), about someone
    # something was told of. How someone is ("Minou est-il noir ?") is left to the memory, which says what was told
    $about = $false
    $asked = @($items | Where-Object { $_.Item.Kind -eq 'askis' -and $_.Item.Individual })
    $kind = @($asked | Where-Object { @("$($_.Item.Written.Predicate)".Trim() -split '\s+')[0] -in @($data['Articles']) })
    if ($asked.Count -eq 1 -and $kind.Count -eq 1) {
        $who = $asked[0].Item.Individual.Key
        $about = @(@($known) + @($items) | Where-Object { $_.Item.Kind -in 'is', 'isnot' -and $_.Item.Individual -and $_.Item.Individual.Key -eq $who }).Count -gt 0
    }
    # (and how someone is, when what was told of that one was kept here, told with other things in one message: the
    # memory holds it only as one of them)
    if ($asked.Count -eq 1 -and -not $about) {
        $who = $asked[0].Item.Individual.Key
        $about = @($known | Where-Object { "$($_.Fact.Action)" -eq 'verb:category' -and $_.Item.Individual -and $_.Item.Individual.Key -eq $who }).Count -gt 0
    }
    # (in a dialogue learned, about anything told before or now: a question alone, with nothing told, is not one)
    if ((Get-LambekLexicon -Language $Language).Dialogue['Learned'] -and (@($known).Count -gt 0 -or @($items | Where-Object { -not $_.Item.Kind.StartsWith('ask') }).Count -gt 0)) { $about = $true }
    # (a correction is about something only when something was told of the same one before)
    if ($correcting) {
        foreach ($entry in @($items | Where-Object { $_.Sentence.PSObject.Properties['Correcting'] -and $_.Sentence.Correcting -and $_.Item.Individual })) {
            if (@($known | Where-Object { $_.Item.Kind -in 'is', 'isnot' -and $_.Item.Individual -and $_.Item.Individual.Key -eq $entry.Item.Individual.Key }).Count -gt 0) { $about = $true }
        }
    }
    if ($several) { $about = $true }
    # (one said to be one of several kinds, "Rex est un chien ou un chat": kept here, as nothing else reads it)
    if (@($items | Where-Object { $_.Item.Predicate -and @($_.Item.Predicate.Atoms | Where-Object { "$_".StartsWith('or:') }).Count -gt 0 }).Count -gt 0) { $about = $true }
    if (-not $general -and -not $about -and @($known | Where-Object { $_.Item.Kind -in $quantified }).Count -eq 0) { return $null }
    # A message with no general rule is taken only when it is about what a rule told is about: "all dogs are animals"
    # was told, "Rex is a dog" and "is Rex an animal?" are for it, "my cat is called Luna" and "do I take the bus?" are
    # for the memory, which keeps what was told as it was said (and the rules told with "if")
    if (-not $general -and -not $about) {
        $ruled = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($entry in @($known | Where-Object { $_.Item.Kind -in $quantified })) {
            foreach ($part in $entry.Item.Subject, $entry.Item.Predicate) { if ($part) { foreach ($atom in @($part.Atoms)) { foreach ($one in (Get-LambekCategoryAtomPart -Atom "$atom")) { [void] $ruled.Add($one) } } } }
        }
        foreach ($entry in $items) {
            $atoms = @(foreach ($part in $entry.Item.Subject, $entry.Item.Predicate) { if ($part) { $part.Atoms } })
            # (what is known of the one it is about counts too: "Rex is a dog" told, "does Rex bark?" is about a dog)
            if ($entry.Item.Individual) {
                $atoms += @($known | Where-Object { $_.Item.Individual -and $_.Item.Individual.Key -eq $entry.Item.Individual.Key -and $_.Item.Predicate } | ForEach-Object { $_.Item.Predicate.Atoms })
            }
            if (@($atoms | ForEach-Object { Get-LambekCategoryAtomPart -Atom "$_" } | Where-Object { $ruled.Contains("$_") }).Count -eq 0) { return $null }
        }
    }

    # What is told in the message is kept as told
    $facts = @(foreach ($entry in $items) { if (-not $entry.Item.Kind.StartsWith('ask')) { ConvertTo-LambekCategoryFact -Sentence $entry.Sentence -Item $entry.Item -Language $Language } })
    $premises = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $known) { $premises.Add($entry) }
    $k = 0
    foreach ($entry in $items) { if (-not $entry.Item.Kind.StartsWith('ask')) { $premises.Add([pscustomobject]@{ Fact = $facts[$k]; Item = $entry.Item }); $k++ } }
    # What the words say by themselves: "le cerisier" is a cerisier, "this shape" a shape. Never told, so never cited
    # as told: a proof keeps it apart, as what the answer assumes
    foreach ($implied in @(Get-LambekCategoryImplied -Items (@($premises | ForEach-Object { $_.Item }) + @($items | ForEach-Object { $_.Item })) -Language $Language)) {
        $premises.Add([pscustomobject]@{ Fact = $null; Item = $implied })
    }
    # What the dictionary says one word is a kind of, so a rule about chats reaches a siamois. Never told either, and
    # said with the dictionary named, so it can be seen and gainsaid
    foreach ($circle in @(Get-LambekCategoryCircle -Items (@($premises | ForEach-Object { $_.Item }) + @($items | ForEach-Object { $_.Item })) -Language $Language)) {
        $premises.Add([pscustomobject]@{ Fact = $null; Item = $circle })
    }
    # What a correction takes back ("non, en fait Tom est un chien") no longer counts, nor anything that follows from it:
    # the answers are worked out again from what is still told. The journal keeps both, and it is said what was replaced
    $takenBack = [System.Collections.Generic.List[string]]::new()
    if ($correcting) {
        $gone = @(Find-LambekCategoryTakenBack -Premises $premises -Items $items -Facts $facts -Language $Language)
        foreach ($taken in $gone) { Set-LambekToldReplaced -Fact $premises[$taken.Index].Fact -By $taken.By }
        if ($gone.Count -gt 0) {
            # (a language that has learned no words for it names the sentences alone)
            if ($data['Replaced']) { $takenBack.Add($data['Replaced']) }
            foreach ($taken in @($gone | Sort-Object Index)) { $takenBack.Add("- $(Format-LambekFact -Fact $premises[$taken.Index].Fact -Language $Language -Register 'vous' -Bare)") }
            foreach ($taken in @($gone | Sort-Object Index -Descending)) { $premises.RemoveAt($taken.Index) }
        }
    }
    $atoms = @{}
    $statements = [LambekCategoryStatement[]] @($premises | ForEach-Object { ConvertTo-LambekCategoryStatement -Item $_.Item -Atoms $atoms })
    # What was told comes before what the dictionary says: a kind it gives that makes the sentences told contradict each
    # other is left out ("Nemo est un dauphin", "Nemo n'est pas un poisson": a dauphin is a poisson in one sense only)
    while (-not [LambekCategories]::Satisfiable($statements)) {
        $book = @([LambekCategories]::Smallest($statements, $null) | Where-Object { -not $premises[$_].Fact -and $premises[$_].Item.PSObject.Properties['Circle'] -and $premises[$_].Item.Circle } | Sort-Object -Descending)
        if ($book.Count -eq 0) { break }
        foreach ($i in $book) { $premises.RemoveAt($i) }
        $atoms = @{}
        $statements = [LambekCategoryStatement[]] @($premises | ForEach-Object { ConvertTo-LambekCategoryStatement -Item $_.Item -Atoms $atoms })
    }
    $listed = { param([int[]] $indices) @(foreach ($i in $indices) { if ($premises[$i].Fact) { "- $(Format-LambekFact -Fact $premises[$i].Fact -Language $Language -Register 'vous' -Bare)" } }) }
    # What the dictionary says is no thing told: it is said after them, on its own, so nothing is put in the user's mouth
    $saidOf = { param($item) $item.PSObject.Properties['Circle'] -and $item.Circle }
    $read = { param([int[]] $indices) @(foreach ($i in $indices) { if (-not $premises[$i].Fact -and (& $saidOf $premises[$i].Item)) { Format-LambekCategoryCircle -Circle $premises[$i].Item.Circle -Language $Language } }) }
    # Where each thing assumed comes from: the dictionary, by its name, or the words themselves ("le cerisier")
    $from = {
        param([int[]] $indices)
        foreach ($i in $indices) {
            if ($premises[$i].Fact) { continue }
            $item = $premises[$i].Item
            if (& $saidOf $item) { [pscustomobject]@{ Kind = 'dictionary'; Name = (Get-LambekDictionarySource -Language $Language); Id = "$($item.Circle.Under)<$($item.Circle.Above)" } }
            else { [pscustomobject]@{ Kind = 'words'; Name = ''; Id = '' } }
        }
    }
    # What an answer rests on, for a "pourquoi ?" and the checker: the things told, as the reasoning read them, and
    # what the words said by themselves apart
    $proof = {
        param([int[]] $indices, [string[]] $concluded)
        $told = @($indices | Where-Object { $premises[$_].Fact })
        Set-LambekLastProof -Facts @($told | ForEach-Object { $premises[$_].Fact }) -Conclusion $concluded `
            -Forms @($told | ForEach-Object { "category($(Get-LambekCategorySignature -Item $premises[$_].Item))" }) `
            -Assumed @($indices | Where-Object { -not $premises[$_].Fact } | ForEach-Object { "category($(Get-LambekCategorySignature -Item $premises[$_].Item))" }) `
            -Consulted @(& $read $indices) -AssumedFrom @(& $from $indices) -Least $least
    }
    # The fewest sentences an answer rests on, the same whatever order they were told in (what each says is its key),
    # and whether no fewer could give it
    $least = $null
    $lines = [System.Collections.Generic.List[string]]::new()

    $question = @($items | Where-Object { $_.Item.Kind.StartsWith('ask') })
    if ($question.Count -eq 0) {
        # Told: said back, and said at once when it cannot be true with what was told before
        $shape = 'Noted'
        if ($script:Incognito) { $shape += 'Here' }
        # (what was told in one sentence of several names is said back once, in that sentence)
        $said = [System.Collections.Generic.List[string]]::new()
        $joined = $null
        foreach ($fact in $facts) {
            if ($fact.PSObject.Properties['Joined'] -and $fact.Joined) {
                if ($fact.Joined -eq $joined) { continue }
                $joined = $fact.Joined
            }
            $said.Add((Format-LambekFact -Fact $fact -Language $Language -Register 'vous'))
        }
        $lines.Add(($say[$shape] -f ($said -join ' ')))
        foreach ($line in $takenBack) { $lines.Add($line) }
        if (-not [LambekCategories]::Satisfiable($statements)) {
            # Naskh: what is told now and cannot be true with what was told before replaces the last thing told about
            # the same one. The general rules stay, the journal keeps both, and it is said which sentence was replaced
            $gone = Find-LambekCategoryReplaced -Premises $premises -Statements $statements -Facts $facts
            if ($null -ne $gone) {
                $goneFact = $premises[$gone].Fact
                Set-LambekToldReplaced -Fact $goneFact -By $facts[0]
                $premises.RemoveAt($gone)
                $atoms = @{}
                $statements = [LambekCategoryStatement[]] @($premises | ForEach-Object { ConvertTo-LambekCategoryStatement -Item $_.Item -Atoms $atoms })
                # (a language that has learned no words for it names the sentence alone)
                if ($data['Replaced']) { $lines.Add($data['Replaced']) }
                $lines.Add("- $(Format-LambekFact -Fact $goneFact -Language $Language -Register 'vous' -Bare)")
            }
            elseif (-not [LambekCategories]::Satisfiable($statements)) {
                $lines.Add($data['Clash'])
                $smallest = [LambekCategories]::Smallest($statements, $null)
                foreach ($line in & $listed $smallest) { $lines.Add($line) }
                foreach ($line in & $read $smallest) { $lines.Add($line) }
            }
        }
        Set-LambekLastProof
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }

    # What was told cannot all be true: nothing follows from it, and it is said which sentences
    if (-not [LambekCategories]::Satisfiable($statements)) {
        $lines.Add($data['Contradiction'])
        $smallest = [LambekCategories]::Smallest($statements, $null)
        foreach ($line in & $listed $smallest) { $lines.Add($line) }
        foreach ($line in & $read $smallest) { $lines.Add($line) }
        Set-LambekLastProof
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
    }

    $ask = $question[0].Item
    if ($Noted -and @($facts).Count -gt 0) {
        $shape = 'Noted'
        if ($script:Incognito) { $shape += 'Here' }
        # (what was told in one sentence of several names is said back once, in that sentence)
        $said = [System.Collections.Generic.List[string]]::new()
        $joined = $null
        foreach ($fact in $facts) {
            if ($fact.PSObject.Properties['Joined'] -and $fact.Joined) {
                if ($fact.Joined -eq $joined) { continue }
                $joined = $fact.Joined
            }
            $said.Add((Format-LambekFact -Fact $fact -Language $Language -Register 'vous'))
        }
        $lines.Add(($say[$shape] -f ($said -join ' ')))
    }
    foreach ($line in $takenBack) { $lines.Add($line) }
    $because = {
        param([int[]] $indices)
        # (a language that has learned no words for it lists what it rests on alone)
        if ($data['Because']) { $lines.Add($data['Because']) }
        foreach ($line in & $listed $indices) { $lines.Add($line) }
        foreach ($line in & $read $indices) { $lines.Add($line) }
        & $proof $indices @()
    }

    # "qui est noir ?": every one named that it follows of, each with what it rests on
    if ($ask.Kind -eq 'askwho') {
        $named = [System.Collections.Generic.List[object]]::new()
        foreach ($premise in $premises) {
            $one = $premise.Item.Individual
            if ($one -and @($named | Where-Object { $_.Key -eq $one.Key }).Count -eq 0) { $named.Add($one) }
        }
        $found = [System.Collections.Generic.List[object]]::new()
        $used = [System.Collections.Generic.SortedSet[int]]::new()
        foreach ($one in $named) {
            $opposite = Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $one.Key
            $support = [LambekCategories]::Smallest($statements, $opposite)
            if ($null -eq $support) { continue }
            $found.Add($one)
            foreach ($i in $support) { [void] $used.Add($i) }
        }
        if ($found.Count -eq 0) { Set-LambekLastProof; return [pscustomobject]@{ Language = $Language; Reply = $data['WhoUnknown']; Facts = $facts } }
        if ($found.Count -eq 1) {
            $only = Get-LambekCategorySentence -Item $ask -Shape 'is' -Language $Language -Subject $found[0].Written
            if ($found[0].Key -eq 'speaker') {
                $speaking = $ask.PSObject.Copy(); $speaking.Individual = $found[0]
                $only = Get-LambekCategorySentence -Item $speaking -Shape 'is' -Language $Language
            }
            $lines.Add("$($only.Substring(0, 1).ToUpperInvariant())$($only.Substring(1)).")
        }
        else {
            $names = @($found | ForEach-Object { Get-LambekProblemShown -Holder ([pscustomobject]@{ Key = $(if ($_.Key -eq 'speaker') { 'speaker' } else { "other:$($_.Key)" }); Written = $_.Written }) -Language $Language })
            $list = "$(($names[0..($names.Count - 2)]) -join ', ') $($data['And']) $($names[-1])"
            $lines.Add("$($list.Substring(0, 1).ToUpperInvariant())$($list.Substring(1)).")
        }
        & $because ([int[]] @($used))
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts; Settled = $true }
    }

    $individual = ''
    if ($ask.Individual) { $individual = $ask.Individual.Key }
    $keys = [string[]] @($premises | ForEach-Object { Get-LambekCategorySignature -Item $_.Item })
    $least = [LambekCategories]::Shortest($statements, (Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $individual), $keys, [LambekCategories]::DefaultBudget)
    $yes = $null
    if ($least) { $yes = $least.Indices }
    $no = $null
    if ($null -eq $yes) {
        $least = [LambekCategories]::Shortest($statements, (Get-LambekCategoryOpposite -Item $ask -Atoms $atoms -Individual $individual -No), $keys, [LambekCategories]::DefaultBudget)
        if ($least) { $no = $least.Indices }
    }
    $answers = @{
        askis      = @('is', 'isnot')
        askdoes    = @('is', 'isnot')
        askall     = @('all', 'notall')
        asksome    = @('some', $null)
        asksomenot = @('somenot', 'notsomenot')
        askno      = @('no', $null)
    }
    $pair = $answers[$ask.Kind]
    # Nothing follows for sure: what holds "normalement" may say what to suppose
    if ($null -eq $yes -and $null -eq $no -and $ask.Kind -in 'askis', 'askdoes') {
        $usual = Resolve-LambekCategoryUsual -Ask $ask -Premises $premises.ToArray() -Statements $statements -Atoms $atoms -Language $Language
        if ($usual) {
            foreach ($line in $usual.Lines) { $lines.Add($line) }
            $concluded = $(if ($usual.PSObject.Properties['Shape'] -and $usual.Shape) { Get-LambekCategoryConclusion -Item $ask -Shape $usual.Shape -Usual } else { @() })
            # (rules that contradict each other conclude nothing: only what they rest on is kept)
            $forms = $(if ($usual.PSObject.Properties['Forms']) { $usual.Forms } else { @() })
            $assumed = $(if ($usual.PSObject.Properties['Assumed']) { $usual.Assumed } else { @() })
            Set-LambekLastProof -Facts $usual.Facts -Conclusion $concluded -Forms $forms -Assumed $assumed
            return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts; Settled = $true }
        }
    }
    if ($null -ne $yes -or $null -ne $no) {
        $answer = $(if ($null -ne $yes) { 'Yes' } else { 'No' })
        $shape = $(if ($null -ne $yes) { $pair[0] } else { $pair[1] })
        $sentence = $null
        if ($shape) { $sentence = Get-LambekCategorySentence -Item $ask -Shape $shape -Language $Language }
        $support = [int[]] $(if ($null -ne $yes) { $yes } else { $no })
        $concluded = @(if ($shape) { Get-LambekCategoryConclusion -Item $ask -Shape $shape })
        # Said in a sentence of its own, read back by a second Lambek; else in lines, as told
        $spoken = $null
        if ($sentence) { $spoken = ConvertTo-LambekSpeech -Verdict $answer.ToLowerInvariant() -Conclusion $sentence -Premises @($support | Where-Object { $premises[$_].Fact } | ForEach-Object { $premises[$_] }) -Language $Language }
        if ($spoken) {
            $lines.Add($spoken.Text)
            & $proof $support $concluded
            return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts; Settled = $true }
        }
        if ($sentence) { $lines.Add(($data[$answer] -f $sentence)) }
        elseif ($answer -eq 'No' -and $ask.Kind -eq 'asksome') { $lines.Add($data['NoneThere']) }
        else { $lines.Add($data["$($answer)Short"]) }
        & $because $support
        if ($concluded.Count -gt 0) { & $proof $support $concluded }
        return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts; Settled = $true }
    }

    # Neither follows: it is said, with what was told that may look as if it did
    $sentence = Get-LambekCategorySentence -Item $ask -Shape $pair[0] -Language $Language
    if (-not $sentence) { $sentence = $question[0].Sentence.Original.TrimEnd('?').Trim() }
    $lines.Add(($data['Unknown'] -f ($say['Quote'] -f $sentence)))
    $asked = @($ask.Predicate.Atoms)
    foreach ($premise in $premises) {
        if ($premise.Item.Kind -notin 'some', 'somenot') { continue }
        if (@($premise.Item.Predicate.Atoms | Where-Object { $_ -in $asked }).Count -eq 0) { continue }
        # (said back as everything told is: "<<Certains chats sont gris>> ne dit pas lesquels")
        $said = Get-LambekFactSentence -Fact $premise.Fact -Register 'vous'
        $quoted = $(if ($said) { $say['Quote'] -f $said.Trim().TrimEnd('.') } else { $say['Quote'] -f "$($premise.Fact.Text)".Trim().TrimEnd('.') })
        $lines.Add(($data['Which'] -f $quoted))
    }
    # "certains chats sont-ils noirs ?" when all of them are, but nothing says there are any
    $exists = $null
    if ($ask.Kind -eq 'asksome') { $exists = [pscustomobject]@{ Kind = 'askall'; Subject = $ask.Subject; Predicate = $ask.Predicate } }
    if ($ask.Kind -eq 'asksomenot') { $exists = [pscustomobject]@{ Kind = 'askno'; Subject = $ask.Subject; Predicate = $ask.Predicate } }
    if ($exists -and $null -ne [LambekCategories]::Smallest($statements, (Get-LambekCategoryOpposite -Item $exists -Atoms $atoms -Individual ''))) {
        $lines.Add(($data['Exist'] -f $ask.Written.Subject))
    }
    # The question that would settle it, kept until the next message: "oui" or "non" is then its answer
    $decide = Find-LambekCategoryQuestion -Ask $ask -Premises $premises.ToArray() -Statements $statements -Atoms $atoms -Language $Language
    if ($decide) {
        foreach ($line in $decide.Lines) { $lines.Add($line) }
        Set-LambekCategoryPending -Pending ([pscustomobject]@{ Language = $Language; Question = $question[0].Sentence.Original; Yes = $decide.Yes; No = $decide.No })
    }
    Set-LambekLastProof
    return [pscustomobject]@{ Language = $Language; Reply = ($lines -join "`n"); Facts = $facts }
}
