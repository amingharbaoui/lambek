function New-LambekIntentCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory only.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Evidence,

        [Parameter(Mandatory)]
        [pscustomobject] $Scoring,

        [hashtable] $ParameterCache
    )

    $request = $Evidence.Request
    $grammar = $Evidence.Grammar
    $language = $request.Language
    $lexicon = Get-LambekLexicon -Language $language
    $selection = Select-LambekIntent -Evidence $Evidence -Scoring $Scoring
    $best = $selection.Best

    $status = 'Unknown'
    $parameters = [ordered]@{}
    $missing = @()
    $questions = [System.Collections.Generic.List[string]]::new()

    # Decision
    if ($selection.Status -eq 'Unknown') {
        $questions.Add($lexicon.SentenceQuestion)
    }
    elseif ($selection.Status -eq 'Ambiguous') {
        $status = 'Ambiguous'
        $first = Get-LambekTitle -Action $selection.Ranked[0].Action -Language $language
        $second = Get-LambekTitle -Action $selection.Ranked[1].Action -Language $language
        $questions.Add(($lexicon.AmbiguityQuestion -f $first, $second))
    }
    else {
        # Parameters (cached when the same request is scored many times)
        $id = $best.Action.Id
        if ($null -ne $ParameterCache -and $ParameterCache.ContainsKey($id)) {
            $filled = $ParameterCache[$id]
        }
        else {
            $filled = Get-LambekParameter -Action $best.Action -Request $request -Grammar $grammar
            if ($null -ne $ParameterCache) { $ParameterCache[$id] = $filled }
        }

        $parameters = $filled.Values
        $missing = $filled.Missing

        foreach ($question in $grammar.Questions) {
            if ($question -ne $lexicon.SentenceQuestion) { $questions.Add($question) }
        }
        foreach ($question in $filled.Questions) {
            if (-not $questions.Contains($question)) { $questions.Add($question) }
        }

        # Safety guards: never act on a negation or an exclusion, never ignore a value
        $hasNegation = @($request.Words | Where-Object { $_ -in $lexicon.Negations }).Count -gt 0
        $hasExclusion = @($request.Words | Where-Object { $_ -in $lexicon.Exclusions }).Count -gt 0

        if ($hasNegation) {
            $questions.Insert(0, $lexicon.NegationQuestion)
        }
        if ($hasExclusion) {
            $questions.Insert(0, $lexicon.ExclusionQuestion)
        }
        if ($filled.Unused.Count -gt 0) {
            $questions.Add(($lexicon.UnusedQuestion -f ($filled.Unused -join ', ')))
        }

        $status = 'Ready'
        if (-not $grammar.IsSentence -or $missing.Count -gt 0 -or $hasNegation -or $hasExclusion -or $filled.Unused.Count -gt 0) {
            $status = 'NeedsInput'
        }
        if ($status -eq 'NeedsInput' -and $questions.Count -eq 0) {
            $questions.Add($lexicon.RephraseQuestion)
        }
    }

    # Card hash: action and parameters only, so it does not depend on wording or language
    $cardHash = $null
    if ($status -eq 'Ready') {
        $parts = foreach ($name in ($parameters.Keys | Sort-Object)) {
            "$name=$(Format-LambekValue -Value $parameters[$name])"
        }
        $cardHash = Get-LambekHash -Text "$($best.Action.Id)|$($parts -join ';')"
    }

    # Intent Card
    $actionId = $null
    $title = $null
    $risk = $null
    $pack = $null
    $confidence = 0.0
    if ($null -ne $best) {
        $actionId = $best.Action.Id
        $title = Get-LambekTitle -Action $best.Action -Language $language
        $risk = $best.Action.Risk
        $pack = $best.Pack
        $confidence = [math]::Round($best.Score, 4)
    }

    $top = foreach ($candidate in ($selection.Ranked | Select-Object -First 3)) {
        [pscustomobject]@{
            Action  = $candidate.Action.Id
            Score   = [math]::Round($candidate.Score, 4)
            Grammar = $candidate.Grammar
            Text    = [math]::Round($candidate.Text, 4)
        }
    }

    [pscustomobject]@{
        PSTypeName  = 'Lambek.IntentCard'
        Status      = $status
        Action      = $actionId
        Title       = $title
        Pack        = $pack
        Risk        = $risk
        Confidence  = $confidence
        Parameters  = $parameters
        Missing     = @($missing)
        Questions   = $questions.ToArray()
        Language    = $language
        Original    = $request.Original
        IsSentence  = $grammar.IsSentence
        Types       = $grammar.Types
        Candidates  = @($top)
        RequestHash = $request.Hash
        CardHash    = $cardHash
    }
}
