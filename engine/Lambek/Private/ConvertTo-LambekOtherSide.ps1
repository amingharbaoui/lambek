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
    if (-not $side) { return $null }
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
