function Get-LambekRequestFrame {
    # What sets a request in another frame than "do it, now, for me": a condition after its first word ("affiche les
    # fichiers ... seulement si la sauvegarde est verifiee"), a day that is not today ("hier", "demain", "last week"),
    # or someone else who does it, said before its verb ("Paul veut...", "my colleague wants to..."). The words that
    # do, as they were typed, or nothing
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        [pscustomobject] $Grammar
    )

    $lexicon = Get-LambekLexicon -Language $Request.Language
    $dialogue = $lexicon.Dialogue
    if (-not $dialogue) { return $null }
    $tokens = @($Request.Tokens)
    $original = "$($Request.Original)"
    if (-not $original) { $original = "$($Request.Text)" }

    # A condition after the first word (one at the start is read as a condition already: "s'il pleut, ...")
    $conditions = @($dialogue['General']['Conditions'] | ForEach-Object { (ConvertTo-LambekNormalizedText -Text "$_").TrimEnd("'") } | Where-Object { $_.Length -ge 2 })
    for ($i = 1; $i -lt $tokens.Count; $i++) {
        $word = $tokens[$i]
        # (the elided "s'" is "si" before "il" and "ils", but not in "s'il te plait")
        $elided = $word -eq 's' -and $i + 1 -lt $tokens.Count -and $tokens[$i + 1] -in 'il', 'ils' -and -not ($i + 3 -lt $tokens.Count -and $tokens[$i + 2] -in 'te', 'vous' -and $tokens[$i + 3] -like 'plai*')
        if ($word -in $conditions -or $elided) { return (Get-LambekSurface -Text $original -Words @($tokens[$i..($tokens.Count - 1)])) }
    }

    # A day that is not today
    $plain = " $($tokens -join ' ') "
    if ($dialogue['Times']) {
        foreach ($time in @($dialogue['Times'].Keys | Sort-Object { - "$_".Length })) {
            if ("$($dialogue['Times'][$time])" -match ':0$') { continue }
            if ($plain.Contains(" $time ")) { return (Get-LambekSurface -Text $original -Words @("$time" -split ' ')) }
        }
    }

    # Someone else, before the verb: a pronoun or a word of another person, or a name (a word with a capital after
    # the first one and small letters after it, that is not Lambek: a sentence in capitals names no one)
    $head = -1
    if ($Grammar -and $Grammar.PSObject.Properties['Head'] -and $Grammar.Head) { $head = [int] $Grammar.Head.Position }
    if ($head -gt 0) {
        $capitals = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $said = @([regex]::Matches($original, '\p{L}[\p{L}\p{M}]*'))
        for ($k = 1; $k -lt $said.Count; $k++) {
            if ($said[$k].Value.Length -gt 1 -and [char]::IsUpper($said[$k].Value[0]) -and [char]::IsLower($said[$k].Value[1])) { [void] $capitals.Add((ConvertTo-LambekNormalizedText -Text $said[$k].Value)) }
        }
        $others = @($dialogue['Others'])
        $before = @($tokens[0..([math]::Min($head, $tokens.Count) - 1)])
        $someone = @($before | Where-Object { $_ -in $others -or ($capitals.Contains($_) -and $_ -ne 'lambek') }).Count -gt 0
        # (a wish said with no "je", "tu" or "vous" before the verb is someone else's: "Paul veut afficher...")
        $me = @($before | Where-Object { $_ -in @($dialogue['Speakers']) -or $_ -in @($dialogue['Addressee']) }).Count -gt 0
        $wish = @($before | Where-Object { $_ -in @($dialogue['Wishes']) }).Count -gt 0
        if ($someone -or ($wish -and -not $me -and $before.Count -ge 2)) {
            return (Get-LambekSurface -Text $original -Words $before)
        }
    }
    return $null
}
