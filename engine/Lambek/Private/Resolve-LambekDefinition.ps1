function Resolve-LambekDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # "que veut dire purge ?", "what does relocate mean?": the dictionary answers, nothing is planned.
    # Small talk and requests about files come first: "qu'est-ce que tu sais faire", "what is in C:\Temp"
    $normalized = " $((ConvertTo-LambekNormalizedText -Text $Text) -replace '[^\p{L}\p{N}\s''-]', ' ' -replace '\s+', ' ') "
    foreach ($language in Get-LambekAvailableLanguage) {
        $lexicon = Get-LambekLexicon -Language $language
        $define = $lexicon.Define
        if (-not $define) { continue }
        $asked = @($define.Phrases | Where-Object { $normalized.StartsWith(" $_ ") } | Sort-Object Length -Descending | Select-Object -First 1)
        if ($asked.Count -eq 0) { continue }
        # "what does X mean", not "what do I like": a phrase that only opens the question needs its last word
        if ($define['Needs'] -and $define['Needs'].Contains($asked[0]) -and $normalized -notmatch " $([regex]::Escape($define['Needs'][$asked[0]])) ") { continue }
        if (Get-LambekTalk -Text $Text -Language $language) { return $null }
        if (@((Get-LambekEntity -Text $Text).Entities).Count -gt 0) { return $null }

        # The word: what is left once the question and its small words are gone
        $rest = @($normalized.Substring($asked[0].Length + 1).Trim() -split ' ' | Where-Object { $_ -and $_ -notin $define.Fillers -and -not $lexicon.StopWords.Contains($_) })
        if ($rest.Count -eq 0 -or $rest.Count -gt 3) { return $null }
        $word = $rest -join ' '

        # The language where the word is a lemma as written ("purge" in English, "fichier" in French),
        # the language of the question first on a tie
        $best = $null
        foreach ($in in @($language) + @(Get-LambekAvailableLanguage | Where-Object { $_ -ne $language })) {
            # (without a dictionary for that language, it has no sense to give)
            $senses = @(try { Find-LambekWord -Word $word -Language $in -First 3 -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message })
            if ($senses.Count -eq 0) { continue }
            $exact = @($senses | Where-Object { (ConvertTo-LambekNormalizedText -Text $_.Lemma) -eq ($word -replace ' ', '_') }).Count -gt 0
            if (-not $best -or ($exact -and -not $best.Exact)) { $best = [pscustomobject]@{ Word = $word; Language = $language; Of = $in; Senses = $senses; Exact = $exact } }
        }
        if ($best) { return $best }
        # ("c'est quoi la capitale de la France": several words no dictionary knows together are no word to define;
        # the message is left to the other readings)
        if ($rest.Count -gt 1) { return $null }
        return [pscustomobject]@{ Word = $word; Language = $language; Of = $language; Senses = @() }
    }
    return $null
}

function Format-LambekDefinition {
    param([pscustomobject] $Definition)

    # One line per sense: part of speech, definition, synonyms; WordNet defines in English
    $answer = (Get-LambekLexicon -Language $Definition.Language).Answer.Define
    if (@($Definition.Senses).Count -eq 0) { return $answer.Unknown -f $Definition.Word }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(($answer.Head -f $Definition.Senses[0].Lemma))
    $number = 1
    foreach ($sense in $Definition.Senses) {
        $line = "$number. ($($answer.Pos[$sense.Pos])) $($sense.Definition)"
        if (@($sense.Synonyms).Count -gt 0) { $line += ' ' + ($answer.Synonyms -f (@($sense.Synonyms | Select-Object -First 4) -join ', ')) }
        $lines.Add($line)
        $number++
    }
    $lines.Add(($answer.Source -f $(if ($Definition.Of -eq 'fr') { 'WOLF, WordNet' } else { 'WordNet' })))
    return $lines -join "`n"
}
