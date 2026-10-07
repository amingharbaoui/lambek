function Get-LambekDialogueAct {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        [Parameter(Mandatory)]
        [pscustomobject] $Grammar
    )

    # What kind of message this is, before any action is chosen: an order to carry out (Order), something the user
    # tells (Report), a question about how things are (Question), or a sentence about something else (Other).
    # Only an order may become an action. The words that tell them apart are in the language file; without them, all is an order
    $lexicon = Get-LambekLexicon -Language $Request.Language
    $order = [pscustomobject]@{ Kind = 'Order'; Rule = $null; Say = $null; Subject = $null }
    $dialogue = $lexicon.Dialogue
    if (-not $dialogue) { return $order }

    $tokens = @($Request.Tokens)
    $words = @($Request.Words)
    if ($tokens.Count -eq 0 -or $tokens.Count -ne $words.Count) { return $order }

    $typed = @{}
    foreach ($item in @($Grammar.Assignment)) { $typed[[int] $item.Position] = "$($item.Type)" }
    # The verbs of the actions, where they stand: a question word read as a verb is not one of them
    $verbs = @($typed.Keys | Where-Object { $typed[$_] -match '(^|\s)s(\s|$)' -and $words[$_] -notin $lexicon.Interrogatives } | Sort-Object)
    $entities = @($Request.Entities | Where-Object { $_.Type -ne 'number' })
    $act = { param($kind, $rule, $subject) [pscustomobject]@{ Kind = $kind; Rule = $rule; Say = $dialogue.Say[$kind]; Subject = $subject } }

    # "how do I delete...", "what is a .log file": the sentence opens as a question about how things are
    $opening = $tokens -join ' '
    foreach ($phrase in @($dialogue['Questions'])) {
        if ($opening -eq $phrase -or $opening.StartsWith("$phrase ")) { return & $act 'Question' 'opening' }
    }

    foreach ($verb in $verbs) {
        # "yesterday I deleted...", "my boss moved...": the verb has a subject, and it is not Lambek.
        # Read back from the verb, as far as a noun or a place; "I want to...", "j'aimerais que tu..." stay orders
        $wish = $false
        for ($i = $verb - 1; $i -ge 0 -and $i -ge $verb - 5; $i--) {
            $token = $tokens[$i]
            if ($token -match '^_[a-z]+_$' -or ($typed.ContainsKey($i) -and $typed[$i] -notmatch '\^')) { break }
            if ($token -in @($dialogue['Addressee'])) { break }
            if ($token -in @($dialogue['Wishes'])) { $wish = $true; continue }
            if ($token -in @($dialogue['Speakers'])) {
                if (-not $wish) { return & $act 'Report' 'subject' ([pscustomobject]@{ Position = $i; Verb = $verb; Person = 'speaker'; Wish = $false }) }
                break
            }
            if ($token -in @($dialogue['Others'])) {
                # "from my desktop delete...": after a word of place, it is not the subject
                if ($i -gt 0 -and $typed.ContainsKey($i - 1) -and $typed[$i - 1] -match 'd\^l') { break }
                return & $act 'Report' 'subject' ([pscustomobject]@{ Position = $i; Verb = $verb; Person = 'other'; Wish = $wish })
            }
        }

        # "the delete key is broken", "la liste des courses": an article right before it makes the verb a noun
        if ($entities.Count -eq 0 -and $verb -gt 0) {
            $before = $tokens[$verb - 1]
            if ($before -in @($dialogue['Determiners']) -or ($verb -eq 1 -and $before -in @($dialogue['Articles']))) { return & $act 'Other' 'noun' }
        }
    }

    # "find me a good restaurant in Brussels": an order, but nothing in it is known to the packs:
    # no place, no file, no kind, no pronoun, and at least two words they have never seen
    if ($verbs.Count -gt 0 -and $entities.Count -eq 0) {
        $known = @($typed.Keys | Where-Object { $_ -notin $verbs -and $typed[$_] -notmatch '\^' })
        $pronoun = @($tokens | Where-Object { $_ -in @($lexicon.FollowUp['Pronouns']) })
        $strange = @(for ($i = 0; $i -lt $tokens.Count; $i++) {
                if ($typed.ContainsKey($i) -or $tokens[$i] -match '^_[a-z]+_$') { continue }
                if ($lexicon.StopWords.Contains($tokens[$i]) -or $lexicon.StopWords.Contains($words[$i])) { continue }
                $tokens[$i]
            })
        if ($known.Count -eq 0 -and $pronoun.Count -eq 0 -and $strange.Count -ge 2) { return & $act 'Other' 'nothing known' }
    }
    return $order
}
