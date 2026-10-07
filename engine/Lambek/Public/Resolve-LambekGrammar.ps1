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
        [int] $MaxCombinations = 4096,

        # Types to try for words the grammar does not know: @{ purge = @('s o^l') }
        [hashtable] $Hypothesis = @{},

        # Only say whether the words reduce to s: combinations that cannot are skipped without reducing them
        [switch] $SentenceOnly
    )

    process {
        $language = $Request.Language
        $lexicon = Get-LambekLexicon -Language $language
        $grammar = Get-LambekGrammarLexicon -Language $language

        # A word of another language keeps its types there: the types are the same in every language (s, o, d...)
        if ($Request.PSObject.Properties['Borrowed'] -and $Request.Borrowed -and $Request.Borrowed.Count -gt 0) {
            foreach ($word in @($Request.Borrowed.Keys)) {
                if ($grammar.Words.ContainsKey($word)) { continue }
                $other = Get-LambekGrammarLexicon -Language $Request.Borrowed[$word]
                if ($other.Words.ContainsKey($word)) { $grammar.Words[$word] = $other.Words[$word] }
            }
        }

        # Candidate types per word
        $typedWords = [System.Collections.Generic.List[object]]::new()
        $unknown = [System.Collections.Generic.List[string]]::new()

        for ($position = 0; $position -lt $Request.Words.Count; $position++) {
            $word = $Request.Words[$position]
            if ($grammar.Words.ContainsKey($word)) {
                $typedWords.Add([pscustomobject]@{ Word = $word; Position = $position; Candidates = $grammar.Words[$word].ToArray() })
            }
            elseif ($Hypothesis.ContainsKey($word)) {
                $typedWords.Add([pscustomobject]@{ Word = $word; Position = $position; Candidates = [string[]] @($Hypothesis[$word]) })
            }
            elseif (-not $lexicon.StopWords.Contains($word)) {
                $unknown.Add($word)
            }
        }

        # Every combination of candidate types at once, in one chart; the smallest choice wins among equals
        # First only the forms that can still become a sentence; without one, the shortest forms for the questions
        $root = Invoke-LambekChart -TypedWords $typedWords -Keep 4 -Fuel ([long] $MaxCombinations * 64) -SentenceOnly
        if (-not $root.ContainsKey('s|0') -and -not $SentenceOnly) {
            $root = Invoke-LambekChart -TypedWords $typedWords -Keep 1 -Fuel ([long] $MaxCombinations * 64) -Beam 6
        }
        $choice = [int[]] @()
        $readings = 0
        $sentence = $null
        $shortest = $null
        foreach ($form in $root.Keys) {
            $first = $root[$form][0]
            if ($form -ceq 's|0') {
                $sentence = $first
                $readings = $root[$form].Count
            }
            $size = Get-LambekFormCount -Form $form
            if ($null -eq $shortest -or $size -lt $shortest.Size -or ($size -eq $shortest.Size -and (Compare-LambekChoice -First $first -Second $shortest.Choice) -lt 0)) {
                $shortest = [pscustomobject]@{ Size = $size; Choice = $first }
            }
        }
        if ($sentence) { $choice = $sentence }
        elseif ($shortest) { $choice = $shortest.Choice }
        if ($SentenceOnly -and -not $sentence) {
            return [pscustomobject]@{ PSTypeName = 'Lambek.Grammar'; IsSentence = $false }
        }

        # The chosen reading, reduced once more to know which types cancel which
        $simpleTypes = [System.Collections.Generic.List[object]]::new()
        $owners = [System.Collections.Generic.List[int]]::new()
        for ($w = 0; $w -lt $typedWords.Count; $w++) {
            foreach ($simpleType in ConvertFrom-LambekType -Type $typedWords[$w].Candidates[$choice[$w]]) {
                $simpleTypes.Add($simpleType)
                $owners.Add($w)
            }
        }
        $reduction = Invoke-LambekReduction -SimpleTypes $simpleTypes.ToArray()
        $left = @($reduction.Leftover | ForEach-Object { $simpleTypes[$_] })

        # The head of the sentence: the word whose s is left once everything else cancels (the main verb).
        # A sentence modifier ("in C:\Logs, delete...": s s^l d^l) passes the s on: follow its s^l to the verb it takes.
        $head = $null
        if ($sentence) {
            $at = @($reduction.Leftover | Where-Object { $simpleTypes[$_].Base -eq 's' -and $simpleTypes[$_].Order -eq 0 })[0]
            for ($step = 0; $null -ne $at -and $step -lt $simpleTypes.Count; $step++) {
                $word = $owners[$at]
                $takes = @(for ($x = 0; $x -lt $simpleTypes.Count; $x++) {
                        if ($owners[$x] -eq $word -and $simpleTypes[$x].Base -eq 's' -and $simpleTypes[$x].Order -ne 0) { $x }
                    })
                $next = $null
                foreach ($pair in $reduction.Pairs) {
                    foreach ($index in $takes) {
                        if ($pair.Right -eq $index -and $simpleTypes[$pair.Left].Order -eq 0) { $next = $pair.Left }
                        if ($pair.Left -eq $index -and $simpleTypes[$pair.Right].Order -eq 0) { $next = $pair.Right }
                    }
                }
                if ($null -eq $next) {
                    $owner = $typedWords[$word]
                    $head = [pscustomobject]@{ Word = $owner.Word; Position = $owner.Position }
                    break
                }
                $at = $next
            }
        }
        $best = [pscustomobject]@{
            IsSentence  = [bool] $sentence
            Choice      = $choice
            SimpleTypes = $simpleTypes.ToArray()
            Owners      = $owners.ToArray()
            Reduction   = $reduction
            Left        = $left
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

        # Distance to a sentence: one missing s, or every type left besides one s
        $sentenceTypes = @($best.Left | Where-Object { $_.Base -eq 's' -and $_.Order -eq 0 }).Count
        $distance = @($best.Left).Count - [math]::Min($sentenceTypes, 1)
        if ($sentenceTypes -eq 0) { $distance++ }

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

        # The reduction as a diagram: the base of each simple type, the word it belongs to, the pairs that cancel,
        # and the s left open (the meaning is computed on it)
        $open = @($best.Reduction.Leftover | Where-Object { $best.SimpleTypes[$_].Base -eq 's' -and $best.SimpleTypes[$_].Order -eq 0 } | Select-Object -First 1)
        $linkage = [pscustomobject]@{
            Bases  = [string[]] @($best.SimpleTypes | ForEach-Object { $_.Base })
            Owners = [int[]] @($best.Owners)
            Pairs  = @($best.Reduction.Pairs | ForEach-Object { , [int[]] @($_.Left, $_.Right) })
            Output = $(if ($open.Count -gt 0) { [int] $open[0] } else { -1 })
        }

        [pscustomobject]@{
            PSTypeName = 'Lambek.Grammar'
            Canonical  = $Request.Canonical
            Language   = $language
            Words      = $Request.Words
            IsSentence = $best.IsSentence
            Readings   = $readings
            Head       = $head
            Distance   = $distance
            Assignment = @($assignment)
            Types      = Format-LambekType -SimpleTypes $best.SimpleTypes
            Steps      = @($steps)
            Links      = @($links)
            Leftover   = Format-LambekType -SimpleTypes $best.Left
            Missing    = $missing.ToArray()
            Questions  = @($questions)
            Unknown    = $unknown.ToArray()
            Linkage    = $linkage
        }
    }
}

function Test-LambekTypeCount {
    param([System.Collections.Generic.List[object]] $SimpleTypes)

    $count = @{}
    foreach ($simpleType in $SimpleTypes) {
        $sign = 1
        if ([math]::Abs($simpleType.Order) % 2 -eq 1) { $sign = -1 }
        $count[$simpleType.Base] = $count[$simpleType.Base] + $sign
    }
    foreach ($base in $count.Keys) {
        $expected = 0
        if ($base -eq 's') { $expected = 1 }
        if ($count[$base] -ne $expected) { return $false }
    }
    return $count.ContainsKey('s')
}
