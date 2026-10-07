function Get-LambekStatement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        [Parameter(Mandatory)]
        [pscustomobject] $Grammar,

        # What kind of message it is, with the subject found before the verb
        [Parameter(Mandatory)]
        [pscustomobject] $Act,

        # The action the verb names, as it was chosen before the sentence was found not to be an order
        [Parameter(Mandatory)]
        [hashtable] $Action
    )

    # The meaning of a sentence that tells something: who, does what, to which objects, when (an event with its roles).
    # The verb and the objects are read as for an order, so the same words mean the same thing told or asked.
    # Nothing is said of a sentence only half read: every value the action needs must be there, and a place or a file named
    $dialogue = (Get-LambekLexicon -Language $Request.Language).Dialogue
    if ($Act.Kind -ne 'Report' -or -not $Act.Subject -or -not $dialogue) { return $null }
    if (@($Request.Entities | Where-Object { $_.Type -ne 'number' }).Count -eq 0) { return $null }
    $filled = Get-LambekParameter -Action $Action -Request $Request -Grammar $Grammar
    if (@($filled.Missing).Count -gt 0 -or $filled.Values.Count -eq 0) { return $null }

    $tokens = @($Request.Tokens)
    # The words as the user wrote them, with their accents and capitals
    $written = @{}
    foreach ($match in [regex]::Matches("$($Request.Original)", '[\p{L}\p{N}]+')) {
        $plain = ConvertTo-LambekNormalizedText -Text $match.Value
        if (-not $written.ContainsKey($plain)) { $written[$plain] = $match.Value }
    }
    $say = { param($words) (@($words | ForEach-Object { if ($written.ContainsKey($_)) { $written[$_] } else { $_ } }) -join ' ') }

    # Who: the speaker, or the words from the subject to the verb that are not the wish or small words
    $typed = @{}
    foreach ($item in @($Grammar.Assignment)) { $typed[[int] $item.Position] = $true }
    $agent = 'speaker'
    $name = $null
    if ($Act.Subject.Person -ne 'speaker') {
        $agent = 'other'
        $lexicon = Get-LambekLexicon -Language $Request.Language
        $kept = @(for ($i = $Act.Subject.Position; $i -lt $Act.Subject.Verb; $i++) {
                if ($i -ne $Act.Subject.Position -and ($typed.ContainsKey($i) -or $tokens[$i] -in @($dialogue['Wishes']) -or $lexicon.StopWords.Contains($tokens[$i]))) { continue }
                $tokens[$i]
            })
        $name = & $say $kept
    }

    # When: the longest words of time in the sentence
    $when = $null
    $text = " $($tokens -join ' ') "
    foreach ($phrase in @($dialogue['Times']) | Sort-Object { -$_.Length }, { $_ }) {
        if ($text.Contains(" $phrase ")) { $when = & $say @($phrase -split ' '); break }
    }

    # The same term as the plan of an order, with the roles around it
    $step = [pscustomobject]@{ Action = $Action.Id; Parameters = $filled.Values; Output = $Action['Output'] }
    $roles = @((Get-LambekLogicalForm -Step $step), "agent($agent)")
    if ($when) { $roles += "time(""$when"")" }
    $form = "told($($roles -join ', '))"
    if ($Act.Subject.Wish) { $form = "told(wish($($roles -join ', ')))" }

    [pscustomobject]@{
        Action     = $Action.Id
        Parameters = $filled.Values
        Agent      = $agent
        Name       = $name
        Wish       = [bool] $Act.Subject.Wish
        Time       = $when
        Form       = $form
    }
}
