function Resolve-LambekGrammar {
    <#
    .SYNOPSIS
        Types each word with Lambek pregroup grammar and checks that the request reduces to a sentence.
    .EXAMPLE
        ConvertTo-LambekRequest 'move the files to D:\Archive' | Resolve-LambekGrammar
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Lambek.Request')]
        [pscustomobject] $Request,

        [ValidateRange(1, 100000)]
        [int] $MaxCombinations = 4096
    )

    process {
        $language = $Request.Language
        $lexicon = Get-LambekLexicon -Language $language
        $grammar = Get-LambekGrammarLexicon -Language $language

        # Candidate types per word
        $typedWords = [System.Collections.Generic.List[object]]::new()
        $unknown = [System.Collections.Generic.List[string]]::new()

        for ($position = 0; $position -lt $Request.Words.Count; $position++) {
            $word = $Request.Words[$position]
            if ($grammar.Words.ContainsKey($word)) {
                $typedWords.Add([pscustomobject]@{ Word = $word; Position = $position; Candidates = $grammar.Words[$word].ToArray() })
            }
            elseif (-not $lexicon.StopWords.Contains($word)) {
                $unknown.Add($word)
            }
        }

        # Try every combination of candidate types, keep the best one
        $choice = [int[]]::new($typedWords.Count)
        $best = $null
        $tried = 0

        while ($tried -lt $MaxCombinations) {
            $tried++

            $simpleTypes = [System.Collections.Generic.List[object]]::new()
            $owners = [System.Collections.Generic.List[int]]::new()
            for ($w = 0; $w -lt $typedWords.Count; $w++) {
                $type = $typedWords[$w].Candidates[$choice[$w]]
                foreach ($simpleType in ConvertFrom-LambekType -Type $type) {
                    $simpleTypes.Add($simpleType)
                    $owners.Add($w)
                }
            }

            $reduction = Invoke-LambekReduction -SimpleTypes $simpleTypes.ToArray()
            $left = @($reduction.Leftover | ForEach-Object { $simpleTypes[$_] })
            $isSentence = $left.Count -eq 1 -and $left[0].Base -eq 's' -and $left[0].Order -eq 0

            $score = $left.Count
            if ($isSentence) { $score = 0 }

            if ($null -eq $best -or $score -lt $best.Score) {
                $best = [pscustomobject]@{
                    Score       = $score
                    IsSentence  = $isSentence
                    Choice      = [int[]] $choice.Clone()
                    SimpleTypes = $simpleTypes.ToArray()
                    Owners      = $owners.ToArray()
                    Reduction   = $reduction
                    Left        = $left
                }
            }
            if ($isSentence) { break }

            # Next combination (odometer)
            $position = $typedWords.Count - 1
            while ($position -ge 0) {
                $choice[$position]++
                if ($choice[$position] -lt $typedWords[$position].Candidates.Count) { break }
                $choice[$position] = 0
                $position--
            }
            if ($position -lt 0) { break }
        }

        # Assignment
        $assignment = for ($w = 0; $w -lt $typedWords.Count; $w++) {
            [pscustomobject]@{
                Word     = $typedWords[$w].Word
                Position = $typedWords[$w].Position
                Type     = $typedWords[$w].Candidates[$best.Choice[$w]]
            }
        }

        # Cancellations
        $links = foreach ($pair in $best.Reduction.Pairs) {
            $leftWord = $typedWords[$best.Owners[$pair.Left]]
            $rightWord = $typedWords[$best.Owners[$pair.Right]]
            [pscustomobject]@{
                LeftPosition  = $leftWord.Position
                RightPosition = $rightWord.Position
                LeftWord      = $leftWord.Word
                RightWord     = $rightWord.Word
                Type          = $best.SimpleTypes[$pair.Right].Base
            }
        }

        $steps = foreach ($pair in $best.Reduction.Pairs) {
            $leftType = Format-LambekType -SimpleTypes @($best.SimpleTypes[$pair.Left])
            $rightType = Format-LambekType -SimpleTypes @($best.SimpleTypes[$pair.Right])
            $leftWord = $typedWords[$best.Owners[$pair.Left]].Word
            $rightWord = $typedWords[$best.Owners[$pair.Right]].Word
            "$leftType $rightType -> 1 ($leftWord, $rightWord)"
        }

        # Missing parts and questions
        $missing = [System.Collections.Generic.List[string]]::new()
        $hasSentence = @($best.Left | Where-Object { $_.Base -eq 's' -and $_.Order -eq 0 }).Count -gt 0
        if (-not $hasSentence) {
            $missing.Add('s')
        }
        $left = @($best.Left)
        for ($k = 0; $k -lt $left.Count; $k++) {
            $simpleType = $left[$k]
            if ($simpleType.Order -eq 0 -or $missing.Contains($simpleType.Base)) { continue }

            # Present but blocked by another missing part ("move to D:\Archive" lacks the files, not the place)
            $partner = $simpleType.Order + 1
            $others = @(if ($simpleType.Order -lt 0) { $left | Select-Object -Skip ($k + 1) } else { $partner = $simpleType.Order - 1; $left | Select-Object -First $k })
            if (@($others | Where-Object { $_.Base -eq $simpleType.Base -and $_.Order -eq $partner }).Count -gt 0) { continue }

            $missing.Add($simpleType.Base)
        }

        $questions = foreach ($base in $missing) {
            if ($base -eq 's') {
                $lexicon.SentenceQuestion
            }
            elseif ($grammar.Questions.ContainsKey($base)) {
                $grammar.Questions[$base]
            }
            else {
                "Missing: $base"
            }
        }

        [pscustomobject]@{
            PSTypeName = 'Lambek.Grammar'
            Canonical  = $Request.Canonical
            Language   = $language
            Words      = $Request.Words
            IsSentence = $best.IsSentence
            Assignment = @($assignment)
            Types      = Format-LambekType -SimpleTypes $best.SimpleTypes
            Steps      = @($steps)
            Links      = @($links)
            Leftover   = Format-LambekType -SimpleTypes $best.Left
            Missing    = $missing.ToArray()
            Questions  = @($questions)
            Unknown    = $unknown.ToArray()
        }
    }
}
