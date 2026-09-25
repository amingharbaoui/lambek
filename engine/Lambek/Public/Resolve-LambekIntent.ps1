function Resolve-LambekIntent {
    <#
    .SYNOPSIS
        Finds the action a request asks for and builds its Intent Card.
    .EXAMPLE
        ConvertTo-LambekRequest 'delete the .log files in C:\Temp' | Resolve-LambekIntent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Lambek.Request')]
        [pscustomobject] $Request
    )

    process {
        $language = $Request.Language
        $lexicon = Get-LambekLexicon -Language $language
        $scoring = Get-LambekScoring
        $weights = $scoring.Weights
        $grammar = Resolve-LambekGrammar -Request $Request
        $index = Get-LambekActionIndex -Language $language

        # Text score per action (best example)
        $textScores = @{}
        foreach ($entry in $index.Entries) {
            $similarity = Measure-LambekTermSimilarity -Terms $Request.Terms -NGrams $Request.CharNGrams `
                -ReferenceTerms $entry.Terms -ReferenceNGrams $entry.NGrams -Model $index.Model

            $text = $weights.Cosine * $similarity.Cosine
            $text += $weights.WordJaccard * $similarity.WordJaccard
            $text += $weights.NGramJaccard * $similarity.NGramJaccard
            $text += $weights.Edit * $similarity.EditSimilarity

            $id = $entry.Action.Id
            if (-not $textScores.ContainsKey($id) -or $text -gt $textScores[$id].Text) {
                $textScores[$id] = [pscustomobject]@{ Text = $text; Entry = $entry }
            }
        }

        # Grammar score: the verb of the action is typed by its own pack
        $candidates = foreach ($id in $textScores.Keys) {
            $entry = $textScores[$id].Entry
            $action = $entry.Action
            $pack = $entry.Pack

            $grammarScore = 0.0
            foreach ($item in $grammar.Assignment) {
                if ($item.Word -notin $action.Verbs) { continue }

                $packTypes = @()
                foreach ($key in '*', $language) {
                    if ($pack.Words.ContainsKey($key) -and $pack.Words[$key].ContainsKey($item.Word)) {
                        $packTypes += $pack.Words[$key][$item.Word]
                    }
                }

                # When the sentence is incomplete, every pack that knows the verb gets the same score
                if ($item.Type -in $packTypes -or (-not $grammar.IsSentence -and $packTypes.Count -gt 0)) {
                    $grammarScore = 1.0
                }
                elseif ($grammarScore -lt 0.5) {
                    $grammarScore = 0.5
                }
            }

            [pscustomobject]@{
                Action  = $action
                Pack    = $pack.Name
                Score   = $weights.Grammar * $grammarScore + $textScores[$id].Text
                Grammar = $grammarScore
                Text    = $textScores[$id].Text
            }
        }

        $ranked = @($candidates | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = { $_.Action.Id } })

        # Decision
        $status = 'Unknown'
        $best = $null
        $parameters = [ordered]@{}
        $missing = @()
        $questions = [System.Collections.Generic.List[string]]::new()

        if ($ranked.Count -gt 0 -and $ranked[0].Score -ge $scoring.Threshold) {
            $best = $ranked[0]
            $isAmbiguous = $ranked.Count -gt 1 -and ($ranked[0].Score - $ranked[1].Score) -lt $scoring.Margin

            if ($isAmbiguous) {
                $status = 'Ambiguous'
                $first = Get-LambekTitle -Action $ranked[0].Action -Language $language
                $second = Get-LambekTitle -Action $ranked[1].Action -Language $language
                $questions.Add(($lexicon.AmbiguityQuestion -f $first, $second))
            }
            else {
                $filled = Get-LambekParameter -Action $best.Action -Request $Request -Grammar $grammar
                $parameters = $filled.Values
                $missing = $filled.Missing

                foreach ($question in $grammar.Questions) {
                    if ($question -ne $lexicon.SentenceQuestion) { $questions.Add($question) }
                }
                foreach ($question in $filled.Questions) {
                    if (-not $questions.Contains($question)) { $questions.Add($question) }
                }

                $status = 'Ready'
                if (-not $grammar.IsSentence -or $missing.Count -gt 0) {
                    $status = 'NeedsInput'
                }
                if ($status -eq 'NeedsInput' -and $questions.Count -eq 0) {
                    $questions.Add($lexicon.RephraseQuestion)
                }
            }
        }
        else {
            $questions.Add($lexicon.SentenceQuestion)
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

        $top = foreach ($candidate in ($ranked | Select-Object -First 3)) {
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
            Original    = $Request.Original
            IsSentence  = $grammar.IsSentence
            Types       = $grammar.Types
            Candidates  = @($top)
            RequestHash = $Request.Hash
            CardHash    = $cardHash
        }
    }
}

function Get-LambekTitle {
    param(
        [hashtable] $Action,
        [string] $Language
    )

    if ($Action.Title.ContainsKey($Language)) {
        return $Action.Title[$Language]
    }
    return $Action.Title['en']
}
