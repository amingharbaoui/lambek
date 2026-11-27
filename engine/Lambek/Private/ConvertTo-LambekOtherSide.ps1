function ConvertTo-LambekOtherSide {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # What the user said
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Language,

        # How Lambek speaks to the user in French: "tu" or "vous"
        [string] $Register = 'vous'
    )

    # The same sentence said from the other side: "I bought a car" is "you bought a car" when Lambek says it back.
    # Only the words that point at the speaker change (I, my, je, mon), and the verb that agrees with them,
    # conjugated by the dictionary. Places, names and values are never touched. Nothing is said when a verb
    # cannot be conjugated: the caller then says the plain form
    $lexicon = Get-LambekLexicon -Language $Language
    $side = $null
    if ($lexicon.Dialogue -and $lexicon.Dialogue['General']) { $side = $lexicon.Dialogue['General']['OtherSide'] }
    # (a language with no words written for it turns round by what its treebanks tag: ConvertTo-LambekOtherSideLearned)
    # (a learned dialogue keeps the keys of OtherSide with no words in them)
    if (-not $side -or -not $side['Words'] -or @($side['Words'].Values | Where-Object { $_ }).Count -eq 0) { return ConvertTo-LambekOtherSideLearned -Text $Text -Language $Language }
    $words = $side['Words']
    if ($side.Contains("Words-$Register")) { $words = $side["Words-$Register"] }
    $person = '2p'
    if ($Language -eq 'fr' -and $Register -eq 'tu') { $person = '2s' }
    $dictionary = Get-LambekDictionary -Language $Language

    # What is never rewritten: a path, a name between quotes, a file name
    $kept = [System.Collections.Generic.List[int[]]]::new()
    foreach ($match in [regex]::Matches($Text, '"[^"]*"|\u00AB[^\u00BB]*\u00BB|(?i)(?<![\w])[a-z]:[\\/][^\s"]*|\\\\[^\s"]+|(?<![\w/:.~])(?:~|\.{1,2})?/[^\s"]+|\S+\.\w{1,5}(?!\w)')) { $kept.Add([int[]] @($match.Index, ($match.Index + $match.Length))) }

    # "tu sais, hier j'ai...": a sentence that already speaks to Lambek cannot be turned round, "tu" would be the user
    $spoken = @([regex]::Matches($Text, "[\p{L}]+") | ForEach-Object { ConvertTo-LambekNormalizedText -Text $_.Value })
    if (@($spoken | Where-Object { $_ -in @($side['Second']) }).Count -gt 0) { return $null }

    $result = [System.Text.StringBuilder]::new()
    $from = 0
    # The subject just changed: its verb is the next verb, after the small words that may stand between them
    $waits = $null
    $to = $person
    $failed = $false
    foreach ($match in [regex]::Matches($Text, "[\p{L}]+['\u2019]?")) {
        if (@($kept | Where-Object { $match.Index -ge $_[0] -and $match.Index -lt $_[1] }).Count -gt 0) { continue }
        $written = $match.Value
        $elided = $written -match "['\u2019]$"
        $plain = ConvertTo-LambekNormalizedText -Text ($written -replace "['\u2019]$", '')
        $with = $null

        if ($waits -and $plain -in @($side['Between'])) {
            # "je m'appelle": the small word between the subject and its verb follows the subject
            if ($words.Contains($plain)) { $with = $words[$plain] }
        }
        elseif ($waits) {
            $agreed = $null
            if ($side.Contains('Agree') -and $side['Agree'].Contains($plain)) { $agreed = $side['Agree'][$plain] }
            elseif ($dictionary -and $side['Conjugate']) {
                # The form of the same verb, in the same tense, for the one spoken to
                # ("suis" is "etre" before it is "suivre": the verbs that help the others come first)
                $known = @($dictionary.Lemmas($plain, $Language) | Where-Object { $_.Pos -eq 'v' -or $_.Pos -like 'aux*' })
                foreach ($lemma in @($known | Where-Object { $_.Pos -like 'aux*' }) + @($known | Where-Object { $_.Pos -notlike 'aux*' })) {
                    $tag = "$($lemma.Tag)"
                    if ($tag -notmatch $waits) { continue }
                    $mood = @('P', 'I', 'F', 'C', 'J', 'S', 'T' | Where-Object { $tag.Contains($_) })[0]
                    if (-not $mood) { continue }
                    $forms = @($dictionary.Forms($lemma.Lemma, $Language, $lemma.Pos, "$mood$to"))
                    if ($forms.Count -gt 0) { $agreed = $forms[0]; break }
                }
                if (-not $agreed) { $failed = $true }
            }
            if ($agreed) { $with = $agreed }
            $waits = $null
        }
        elseif ($words.Contains($plain)) {
            $with = $words[$plain]
            if ($side['Subjects'].Contains($plain)) {
                $waits = $side['Subjects'][$plain]
                # "nous" becomes "vous" whoever is spoken to, and "vous" takes its own form of the verb
                $to = $person
                if ($with -in @($side['Plural'])) { $to = '2p' }
            }
        }

        if ($null -eq $with) { continue }
        # A word that lost its apostrophe needs its space back; one that keeps it (t') stays against the next word
        $next = $Text.Substring($match.Index + $match.Length)
        if ($with -match "'$") {
            if ($next -notmatch '^[aeiouyh\u00E0-\u00FF]') { $with = $with.TrimEnd("'") + 'e ' }
        }
        elseif ($elided) { $with += ' ' }
        [void] $result.Append($Text.Substring($from, $match.Index - $from)).Append($with)
        $from = $match.Index + $match.Length
    }
    if ($failed) { return $null }
    [void] $result.Append($Text.Substring($from))
    # ("me voit" turned is "te voit", once: the space the word had and the one it got are one)
    $said = ($result.ToString() -replace ' {2,}', ' ').Trim()
    if (-not $said) { return $null }
    # ("je ne suis pas" turned is "vous n'etes pas": a small word before a verb that now starts with a vowel loses its own)
    foreach ($rule in @($side['Elide'])) { if ($rule) { $said = [regex]::Replace($said, "$($rule[0])", "$($rule[1])") } }
    $said = $said.Substring(0, 1).ToUpper([cultureinfo]::InvariantCulture) + $said.Substring(1)
    if ($said -notmatch '[.!?]$') { $said += '.' }
    return $said
}

function ConvertTo-LambekOtherSideLearned {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Language,

        # Turned back: what Lambek says of the user, said as the user says it ("eres un estudiante" is "soy un
        # estudiante"), to be read as he would read it; said as it is when nothing in it is of either side
        [switch] $Back
    )

    # The same sentence said from the other side, in a language whose dialogue Lambek learned ("yo soy un estudiante"
    # is "eres un estudiante" when Lambek says it back), by what its forms model reads, nothing written by hand. A word that points
    # at the speaker (a pronoun or a possessive tagged Person=1) becomes the word its treebanks tag the same way for the
    # one spoken to (Person=2), among the words the language learned for him (Addressee), the one tagged most like it
    # ("io" -> "tu", never "te"); in a language that leaves the subject out (Get-LambekSubjectDropped) the subject
    # goes ("eres"); the verb conjugated for the speaker is conjugated for the one spoken to (Inflect). Nothing is said
    # when one of them cannot be found, or when the verb does not say its person ("ik werk"); a sentence that already
    # speaks to Lambek is not turned; one with nothing of either side in it is said as it is
    $model = Get-LambekFormModel -Language $Language
    if (-not $model) { return $null }
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    # (the person turned from, the one turned to, and the words the language learned for the one turned to)
    $from = $(if ($Back) { '2' } else { '1' })
    $to = $(if ($Back) { '1' } else { '2' })
    $theirs = @($data[$(if ($Back) { 'Speaker' } else { 'Addressee' })] | Where-Object { $_ } | ForEach-Object { ConvertTo-LambekNormalizedText -Text "$_" })
    if ($theirs.Count -eq 0) { return $null }
    $words = @([regex]::Matches($Text, '[\p{L}]+') | ForEach-Object { $_ })
    if ($words.Count -eq 0) { return $null }
    $tags = @($model.Read([string[]] @($words | ForEach-Object { $_.Value })))
    if ($tags.Count -ne $words.Count) { return $null }
    # (the tags each form was seen with, read from the treebanks: "tu" is a pronoun of the one spoken to)
    $seen = { param($form) $found = $null; if ($model.Tags.TryGetValue("$form".ToLowerInvariant(), [ref] $found)) { @($found) } else { @() } }
    if (@($words | Where-Object { @(& $seen $_.Value | Where-Object { $_ -match "\|Person=$to(\||$)" }).Count -gt 0 -and (ConvertTo-LambekNormalizedText -Text $_.Value) -in $theirs }).Count -gt 0) { return $null }
    $dropped = Get-LambekSubjectDropped -Language $Language
    $changes = [System.Collections.Generic.List[object]]::new()
    $waits = $false
    $number = ''
    for ($i = 0; $i -lt $words.Count; $i++) {
        $upos = "$($tags[$i].Upos)"
        $feats = "|$($tags[$i].Feats)|"
        if ($upos -in 'PRON', 'DET' -and $feats -match "\|Person=$from\|") {
            $subject = $upos -eq 'PRON' -and ($feats -match '\|Case=([\w,]*\b)?Nom\b' -or $feats -notmatch '\|Case=') -and $feats -notmatch '\|(Poss=Yes|Clitic=Yes|Reflex=Yes)\|'
            if ($subject) {
                $waits = $true
                # (the number the subject says, which its verb agrees with: "io", one)
                $number = $(if ($feats -match '\|Number=(\w+)\|') { $Matches[1] } else { '' })
            }
            if ($subject -and $dropped) { $changes.Add(@($i, '')); continue }
            # (the same tags but for the other one, among the words learned for him, tagged most like this one)
            $wanted = "$upos$($feats.TrimEnd('|') -replace "Person=$from", "Person=$to")"
            $mine = @(& $seen $words[$i].Value | ForEach-Object { $_ -replace "Person=$from", "Person=$to" })
            $best = $null
            $score = -1.0
            foreach ($candidate in $theirs) {
                $tagged = @(& $seen $candidate)
                if (@($tagged | Where-Object { $_ -ceq $wanted }).Count -eq 0) { continue }
                $both = @($tagged | Where-Object { $_ -in $mine }).Count
                $either = @(@($tagged) + @($mine) | Select-Object -Unique).Count
                $like = $(if ($either -gt 0) { $both / $either } else { 0 })
                if ($like -gt $score -or ($like -eq $score -and [string]::CompareOrdinal($candidate, $best) -lt 0)) { $best = $candidate; $score = $like }
            }
            if (-not $best) { return $null }
            # (written as the treebanks write it, with its accent: "tu" learned is "tu" written)
            $written = @($model.Tags.Keys | Where-Object { (ConvertTo-LambekNormalizedText -Text $_) -eq $best -and @(& $seen $_ | Where-Object { $_ -ceq $wanted }).Count -gt 0 } | Select-Object -First 1)
            $changes.Add(@($i, $(if ($written.Count -gt 0) { $written[0] } else { $best })))
            continue
        }
        $lemma = "$($tags[$i].Lemma)"
        # (right after the one turned said as the subject, or first in a sentence where no verb was read, the verb its
        # dictionary, then its treebanks, then how its forms end conjugate for him, when the tagger read the word
        # otherwise or as the treebanks never saw it: "io lavoro", "lavoro" read as the noun; "ich arbeite", read as a
        # past; "Trabajas", read as a noun)
        $verbless = $i -eq 0 -and @($tags | Where-Object { "$($_.Upos)" -in 'VERB', 'AUX' }).Count -eq 0
        $attestedHere = $upos -in 'VERB', 'AUX' -and @(& $seen $words[$i].Value | Where-Object { $_ -ceq "$upos|$($tags[$i].Feats)" }).Count -gt 0
        # (and a verb read for him with tags its treebanks never saw on it: "Sono" read as the plural)
        $unseen = $upos -in 'VERB', 'AUX' -and $feats -match "\|Person=$from\|" -and -not $attestedHere
        if (($waits -or $verbless -or $unseen) -and -not $attestedHere) {
            $form = $words[$i].Value.ToLowerInvariant()
            $readings = [System.Collections.Generic.List[object]]::new()
            $entries = $null
            if ($model.Lexicon -and $model.Lexicon.TryGet($form, [ref] $entries)) { foreach ($entry in @($entries)) { $readings.Add(@("$($entry.Upos)", "$($entry.Lemma)", "$($entry.Feats)")) } }
            # (then as its treebanks tagged it, with the lemma read for that tag)
            foreach ($tag in @(& $seen $form)) { $readings.Add(@($tag.Substring(0, $tag.IndexOf('|')), $model.LemmaFor($form, $tag), $tag.Substring($tag.IndexOf('|') + 1))) }
            # (how its letters end, only for the first word of a sentence where no verb was read: "Trabajas")
            if ($verbless) { foreach ($entry in @($model.Analyze($form))) { $readings.Add(@("$($entry.Upos)", "$($entry.Lemma)", "$($entry.Feats)")) } }
            $conjugated = @($readings | Where-Object {
                    $own = "|$($_[2])|"
                    $_[0] -in 'VERB', 'AUX' -and $own -match "\|Person=$from\|" -and $own -notmatch '\|VerbForm=(Inf|Part|Ger)\|' -and
                    (-not $number -or $own -notmatch '\|Number=' -or $own -match "\|Number=$number\|")
                } | Select-Object -First 1)
            if ($conjugated.Count -gt 0) {
                $upos = $(if ($upos -eq 'AUX') { 'AUX' } else { "$($conjugated[0][0])" })
                $feats = "|$($conjugated[0][2])|"
                $lemma = "$($conjugated[0][1])"
            }
            # (a word read as a verb of his that nothing gives as one is not one: "Nemo", a name read as a verb)
            elseif ($unseen -and -not $waits) { continue }
        }
        if ($upos -in 'VERB', 'AUX' -and ($waits -or $feats -match "\|Person=$from\|")) {
            # (the verb of the one turned as the subject agrees with him: "yo es" made from a sentence said of anyone
            # is "eres"; one that does not say its person is not turned)
            if ($feats -notmatch '\|Person=\d\|') { if ($waits) { return $null } else { continue } }
            # (said of the one turned, the reading of it its treebanks saw for him, when there is one: "io sono", read
            # as "they are", is "I am")
            if ($waits -and $feats -notmatch "\|Person=$from\|") {
                $agreeing = @(& $seen $words[$i].Value | Where-Object {
                        ($_ -like 'VERB|*' -or $_ -like 'AUX|*') -and "|$_|" -match "\|Person=$from\|" -and (-not $number -or "|$_|" -match "\|Number=$number\|")
                    } | Select-Object -First 1)
                if ($agreeing.Count -gt 0) { $feats = "|$($agreeing[0].Substring($agreeing[0].IndexOf('|') + 1))|" }
            }
            $target = $feats.Trim('|') -replace 'Person=\d', "Person=$to"
            # (in the number of its subject: "yo es", made from a sentence said of anyone, is said of one)
            if ($waits -and $number) { $target = $target -replace 'Number=\w+', "Number=$number" }
            # (only forms its treebanks saw with this very lemma so: "eres", "sei", "bist"; a form made from the lemmas
            # that end like it may be wrong where the treebanks seldom speak to anyone, "legghi" for "leggi", "sos" for
            # "es", and is not said)
            $how = ''
            $forms = @($model.Inflect($lemma, $upos, $target, [ref] $how) | Where-Object { $_ })
            if ($forms.Count -eq 0 -or $how -ne 'seen') { return $null }
            # (among them, the one its treebanks saw tagged so, when there is one: "eres", not "eras")
            $attested = @($forms | Where-Object { @(& $seen $_ | Where-Object { $_ -ceq "$upos|$target" }).Count -gt 0 })
            $said = "$(@($(if ($attested.Count -gt 0) { $attested } else { $forms }))[0])"
            # (turned back, a verb of the one spoken to said without its subject is said with the user's own, as he
            # would say it to be read alone: "eres un estudiante" is "yo soy un estudiante")
            if ($Back -and -not $waits -and $dropped -and $feats -match "\|Person=$from\|") {
                $subject = Get-LambekSubjectWord -Language $Language
                if (-not $subject) { return $null }
                $said = "$subject $said"
            }
            $changes.Add(@($i, $said))
            $waits = $false
        }
    }
    # (a subject turned round whose verb was not: "io lavoro" with "lavoro" read as a noun says nothing)
    if ($waits) { return $null }
    # (nothing of either side in it: said as it is)
    if ($changes.Count -eq 0 -and $Back) { return $Text }
    $result = [System.Text.StringBuilder]::new()
    $at = 0
    foreach ($change in $changes) {
        $match = $words[$change[0]]
        $with = "$($change[1])"
        if ($match.Value -cmatch '^\p{Lu}' -and $with) { $with = $with.Substring(0, 1).ToUpperInvariant() + $with.Substring(1) }
        [void] $result.Append($Text.Substring($at, $match.Index - $at)).Append($with)
        $at = $match.Index + $match.Length
    }
    [void] $result.Append($Text.Substring($at))
    $said = ($result.ToString() -replace ' {2,}', ' ').Trim()
    if (-not $said) { return $null }
    $said = $said.Substring(0, 1).ToUpper([cultureinfo]::InvariantCulture) + $said.Substring(1)
    if ($said -notmatch '[.!?]$') { $said += '.' }
    return $said
}

function Test-LambekSaysSpeaker {
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $Text, [string] $Language)

    # Whether a sentence says something of the one who says it, as its forms model reads it: a pronoun, a possessive
    # or a verb tagged for the first person ("ik", "mein", "soy")
    $model = Get-LambekFormModel -Language $Language
    if (-not $model) { return $false }
    $words = @([regex]::Matches($Text, '[\p{L}]+') | ForEach-Object { $_.Value })
    if ($words.Count -eq 0) { return $false }
    # (a word read so that its treebanks never saw so is not taken for one: "Nemo", a name read as a verb)
    return @($model.Read([string[]] $words) | Where-Object {
            $found = $null
            "$($_.Upos)" -in 'PRON', 'DET', 'VERB', 'AUX' -and "|$($_.Feats)|" -match '\|Person=1\|' -and
            $model.Tags.TryGetValue("$($_.Form)".ToLowerInvariant(), [ref] $found) -and @($found | Where-Object { "|$_|" -match '\|Person=1\|' }).Count -gt 0
        }).Count -gt 0
}

function Test-LambekSaidBack {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The thing told
        [Parameter(Mandatory)]
        [pscustomobject] $Fact,

        # The sentence Lambek is about to say for it
        [Parameter(Mandatory)]
        [string] $Sentence
    )

    # The round trip: the sentence is read again as a listener would read it, and must give the thing told back.
    # The same verb, the same one who does it, the same complements; a sentence that reads otherwise is not said
    $language = $Fact.Language
    $plain = { param($text) ((ConvertTo-LambekNormalizedText -Text "$text") -replace '[^\p{L}\p{N}\\/:._-]+', ' ').Trim() }
    $general = (Get-LambekLexicon -Language $language).Dialogue['General']
    # "your sister" said back is "my sister" told: whose it is changes side, the rest must not
    $owner = { param($text) (((& $plain $text) -split ' ') | ForEach-Object { if ($_ -in @($general['Owners'])) { '@' } else { $_ } }) -join ' ' }
    try { $request = ConvertTo-LambekRequest -Text $Sentence -Language $language } catch { return $false }

    if ("$($Fact.Action)".StartsWith('verb:')) {
        $reading = Get-LambekGeneralReading -Request $request -Listener
        if (-not $reading -or $reading.Kind -ne 'statement') { return $false }
        if ("verb:$(& $plain $reading.Verb)" -ne (& $plain $Fact.Action)) { return $false }
        if ($reading.Agent -ne $Fact.Agent) { return $false }
        if ([bool] ($reading.PSObject.Properties['Negated'] -and $reading.Negated) -ne [bool] ($Fact.PSObject.Properties['Negated'] -and $Fact.Negated)) { return $false }
        if ($Fact.Agent -ne 'speaker' -and (& $owner $reading.Name) -ne (& $owner $Fact.Name)) { return $false }
        if ($Fact.PSObject.Properties['Values']) { $roles = $Fact.Values } else { $roles = $Fact.Parameters }
        if (@($reading.Roles.Keys).Count -ne @($roles.Keys).Count) { return $false }
        # ("my boss calls me" said back is "your boss calls you": the one who speaks, on the other side)
        $me = { param($text, $words) $value = & $owner $text; if ($value -in @($words)) { '@me' } else { $value } }
        foreach ($name in $roles.Keys) {
            if (-not $reading.Roles.Contains($name)) { return $false }
            if ((& $me $reading.Roles[$name] (@($general['Addressee']))) -ne (& $me $roles[$name] (@($general['Me']) + @($general['Speakers'])))) { return $false }
        }
        return $true
    }

    # A thing told about an action of a pack: the sentence must still carry every value, and the verb of the action
    $told = ConvertTo-LambekRequest -Text $(if ($Fact.PSObject.Properties['Said'] -and $Fact.Said) { "$($Fact.Said)" } else { "$($Fact.Text)" }) -Language $language
    if (-not (Test-LambekSameEntity -Before $told -After $request) -or -not (Test-LambekSameEntity -Before $request -After $told)) { return $false }
    $verbs = @((Get-LambekAction -Id $Fact.Action).Action.Verbs)
    return @($request.Words | Where-Object { $_ -in $verbs }).Count -gt 0
}
