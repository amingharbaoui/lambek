function Resolve-LambekCalculation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # A question Lambek answers by calculating, never by acting: arithmetic and equations (exact, in fractions),
    # a conversion between units, days between dates or the day of a date. Nothing else is taken for one
    $plain = ConvertTo-LambekNormalizedText -Text $Text
    $words = @($plain -split '[^\p{L}]+' | Where-Object { $_ })

    # The language whose words start the question ("combien font", "solve"), else the language of the words
    $language = $null
    $spaced = " $($plain -replace '\s+', ' ') "
    foreach ($candidate in Get-LambekAvailableLanguage) {
        $calculate = (Get-LambekLexicon -Language $candidate).Calculate
        if ($calculate -and @($calculate.Phrases | Where-Object { $spaced.StartsWith(" $_ ") }).Count -gt 0) { $language = $candidate; break }
    }
    if (-not $language) {
        $language = 'en'
        if ($words.Count -gt 0) { $language = Get-LambekLanguage -Tokens $words }
    }
    $calculate = (Get-LambekLexicon -Language $language).Calculate
    if (-not $calculate) { return $null }

    foreach ($try in 'Dates', 'Convert', 'Function', 'Expression') {
        $found = switch ($try) {
            'Dates' { Resolve-LambekDateQuestion -Text $plain -Calculate $calculate -Language $language }
            'Convert' { Resolve-LambekConversion -Text $plain -Calculate $calculate -Language $language }
            'Function' {
                # A named operation ("derivee de", "gcd of"): the language of the sentence first, then the others
                foreach ($tongue in @($language) + @(Get-LambekAvailableLanguage | Where-Object { $_ -ne $language })) {
                    $other = (Get-LambekLexicon -Language $tongue).Calculate
                    if (-not $other -or -not $other.ContainsKey('Functions')) { continue }
                    $said = Resolve-LambekMathFunction -Plain $plain -Calculate $other -Language $tongue
                    if ($said) { $language = $tongue; $said; break }
                }
            }
            'Expression' { Resolve-LambekExpression -Text $Text -Plain $plain -Calculate $calculate -Language $language }
        }
        if ($found) { return [pscustomobject]@{ Language = $language; Answer = (@($found) -join "`n") } }
    }
    return $null
}

function Format-LambekNumber {
    param([string] $Number, [string] $Language)

    # The decimal sign of the language ("0,3" in French)
    $decimal = (Get-LambekLexicon -Language $Language).Answer.Units['Decimal']
    return $Number.Replace('.', $decimal)
}

function Resolve-LambekExpression {
    param([string] $Text, [string] $Plain, [hashtable] $Calculate, [string] $Language)

    # "combien font 3/7 + 2/5", "solve x^2 - 5x + 6 = 0", or the expression alone ("2^10 - 1")
    $expression = $null
    $words = " $($Plain -replace '\s+', ' ') "
    foreach ($phrase in @($Calculate.Phrases | Sort-Object Length -Descending)) {
        if ($words.StartsWith(" $phrase ")) { $expression = $words.Substring($phrase.Length + 2); break }
    }
    # "trouve x tel que 4x - 7 = 9", "find x such that 2x = 6": the equation after the unknown it names
    $such = @($Calculate['SuchThat'] | Where-Object { $_ } | ForEach-Object { [regex]::Escape((ConvertTo-LambekNormalizedText -Text $_)) }) -join '|'
    if ($null -eq $expression -and $such) {
        $named = [regex]::Match($Plain.Trim(), "^(?:\p{L}+\s+)?\p{L}\s+(?:$such)\s+(?<equation>[^=]+=[^=]+)$")
        if ($named.Success) { $expression = $named.Groups['equation'].Value }
    }
    $alone = $Text -match '^[\s\d.,+\-*/^()=%!xX\u00D7\u00F7\u00B2\u00B3\u221A]+$' -and $Text -match '[\d]' -and $Text -match '[+\-*/^=%!\u00D7\u00F7\u00B2\u00B3\u221A]'
    if ($null -eq $expression -and -not $alone) { return $null }
    if ($null -eq $expression) { $expression = $Text }

    # Numbers written in words become digits ("trois plus quatre"), then words that mean an operation,
    # then the question marks and the small words around it go (an exclamation mark right after a number is a factorial)
    $expression = [LambekNumberWords]::Digitize($expression, $Language)
    $expression = $expression.Trim() -replace '(?<![\d)])[?.!\s]+$', '' -replace '\s*[?.]+$', ''
    foreach ($pair in $Calculate.Operators.GetEnumerator()) { $expression = [regex]::Replace($expression, "(?i)(?<!\p{L})$([regex]::Escape($pair.Key))(?!\p{L})", $pair.Value) }
    $expression = $expression -replace '(?<=\d)\s*%\s*(?:de|of)\s+', '% * '
    $expression = $expression -replace '^\s*(?:[:=]\s*)', ''
    $lexicon = Get-LambekLexicon -Language $Language
    $expression = [regex]::Replace($expression, '(?<![\p{L}])\p{L}{2,}(?![\p{L}])', { param($word) if ($lexicon.StopWords.Contains($word.Value.ToLowerInvariant()) -or $word.Value -in 'sqrt') { if ($word.Value -eq 'sqrt') { 'sqrt' } else { '' } } else { $word.Value } })
    if ($expression -notmatch '\d' -or $expression -match '(?!sqrt)[\p{L}]{2,}' -and $expression -notmatch '^[^\p{L}]*(?:sqrt[^\p{L}]*)+$') { return $null }

    # Where the decimal sign is a dot, a comma between digits groups thousands ("1,000 * 3")
    if ($lexicon.Answer.Units['Decimal'] -eq '.') { $expression = $expression -replace '(?<=\d),(?=\d{3}(?!\d))', '' }

    $answer = $lexicon.Answer.Math
    # One equation with two unknowns or more ("x + y = 10"): a family of solutions, each unknown by the others
    if ($expression -match '^[^=]+=[^=]+$') {
        try {
            $sides = $expression -split '='
            $letters = @([LambekAlgebra]::Letters([LambekAlgebra]::Parse("($($sides[0])) - ($($sides[1]))")))
            if ($letters.Count -gt 1) {
                $system = [LambekLinear]::Solve([string[]] @($expression))
                if ($system.Kind -eq 'none') { return $answer.SystemNone }
                $pairs = for ($k = 0; $k -lt $system.Letters.Count; $k++) { if ($system.Values[$k] -ne $system.Letters[$k]) { "$($system.Letters[$k]) = $($system.Values[$k])" } }
                return $answer.SystemMany -f ($pairs -join ', '), ($system.Free -join ', ')
            }
        }
        catch { Write-Verbose "Not one linear equation: $($_.Exception.Message)" }
    }
    try { $result = [LambekMath]::Evaluate($expression) }
    catch {
        $message = $_.Exception.Message
        if ($_.Exception.InnerException) { $message = $_.Exception.InnerException.Message }
        return $answer.Error -f $message
    }
    if ($result.Kind -eq 'equation') {
        if ($result.Note -eq 'always') { return $answer.Always }
        if ($result.Note -eq 'never') { return $answer.Never }
        if ($result.Note -eq 'complex') { return $answer.Complex }
        # Roots found only by Sturm's theorem come as "~1.3247": said apart, as certified approximations
        $close = @($result.Roots | Where-Object { $_.StartsWith('~') } | ForEach-Object { Format-LambekNumber -Number $_.Substring(1) -Language $Language })
        if ($close.Count -gt 0 -and $close.Count -eq @($result.Roots).Count) {
            return Format-LambekPlural -Template $answer.RootsAbout -Language $Language -Values @($close.Count, $result.Exact, ($close -join $answer.Separator))
        }
        $roots = @($result.Roots | ForEach-Object { if ($_.StartsWith('~')) { "$([char] 0x2248) " + (Format-LambekNumber -Number $_.Substring(1) -Language $Language) } else { Format-LambekNumber -Number $_ -Language $Language } })
        # "a +- b" is two roots
        $count = $roots.Count + @($roots | Where-Object { $_ -match '\u00B1' }).Count
        $said = Format-LambekPlural -Template $answer.Roots -Language $Language -Values @($count, $result.Exact, ($roots -join $answer.Separator))
        if ($result.Note) { $said += ' ' + ($answer.About -f (Format-LambekNumber -Number ($result.Note -replace '^\u2248 ', '') -Language $Language)) }
        # Each exact root put back in the equation: the answer is checked, not believed
        $checks = @(foreach ($root in @($result.Roots)) {
                if ($root -notmatch '^-?\d+(?:/\d+)?$') { continue }
                Get-LambekEquationCheck -Expression $expression -Values @{ $result.Exact = $root } -Language $Language
            })
        if ($answer.Check -and $checks.Count -gt 0 -and $checks.Count -eq @($result.Roots).Count -and $checks -notcontains $null) { $said += "`n" + ($answer.Check -f ($checks -join ' ; ')) }
        return $said
    }
    # The calculation said back as it was read, then its value
    $said = (($expression -replace '\s+', '' -replace '\u00D7', '*') -replace '\*', " $([char] 0x00D7) " -replace '(?<=[\d)])([+\-/])(?=[\d(s])', ' $1 ' -replace 'sqrt', [string] [char] 0x221A).Trim()
    $said = Format-LambekNumber -Number $said -Language $Language
    $exact = Format-LambekNumber -Number $result.Exact -Language $Language
    $decimal = Format-LambekNumber -Number $result.Decimal -Language $Language
    if ($result.Exact -eq $result.Decimal) { return $answer.Value -f $said, $exact }
    if ($result.DecimalIsExact) { return $answer.ValueExact -f $said, $exact, $decimal }
    return $answer.ValueAbout -f $said, $exact, $decimal
}

function Get-LambekEquationCheck {
    param([string] $Expression, [hashtable] $Values, [string] $Language)

    # "3x + 5 = 20" with x = 5: "3 x 5 + 5 = 20", each side worked out again; nothing when the sides differ
    $times = [char] 0x00D7
    $sides = @($Expression -split '=' | ForEach-Object { $_.Trim() })
    if ($sides.Count -ne 2) { return $null }
    $shown = foreach ($side in $sides) {
        foreach ($letter in $Values.Keys) {
            $put = "$($Values[$letter])"
            if ($put -match '[-/]') { $put = "($put)" }
            $pattern = "(?<![\p{L}])$([regex]::Escape($letter))(?![\p{L}])"
            $side = [regex]::Replace($side, "(?<=[\d)])\s*$pattern", " * $put")
            $side = [regex]::Replace($side, $pattern, $put)
        }
        $side
    }
    try {
        $left = [LambekMath]::Evaluate($shown[0]).Exact
        $right = [LambekMath]::Evaluate($shown[1]).Exact
    }
    catch { return $null }
    if ($left -ne $right) { return $null }
    $said = foreach ($side in $shown) {
        $side = ($side -replace '\s+', '' -replace '\*', " $times " -replace '(?<=[\d)])([+\-/])(?=[\d(])', ' $1 ').Trim()
        Format-LambekNumber -Number $side -Language $Language
    }
    return "$($said[0]) = $($said[1]) $([char] 0x2713)"
}

function Resolve-LambekConversion {
    param([string] $Text, [hashtable] $Calculate, [string] $Language)

    # "convertis 12 km en miles", "100 F in celsius", "3 Go en Mo"
    $units = $Calculate.Units
    $names = ($units.Keys | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
    # The whole question is the conversion ("convert 12 km to miles?"), never a part of a request on files
    # ("older than 30 days in C:\Temp" is not days into Celsius)
    $asks = @($Calculate.Phrases) + @('convert', 'converts', 'convertis', 'convertir', 'conversion', 'de') | ForEach-Object { [regex]::Escape($_) }
    $pattern = "^\s*(?:(?:$($asks -join '|'))\s+)*(?<n>-?\d+(?:[.,]\d+)?)\s*(?<from>$names)\s+(?:$($Calculate.Into -join '|'))\s+(?<to>$names)\s*[?.!]*\s*$"
    $match = [regex]::Match(($Text -replace '\u00B0\s*', ''), "(?i)$pattern")
    if (-not $match.Success) { return $null }
    $from = $units[$match.Groups['from'].Value.ToLowerInvariant()]
    $to = $units[$match.Groups['to'].Value.ToLowerInvariant()]
    $answer = (Get-LambekLexicon -Language $Language).Answer.Math
    $amount = [double]::Parse($match.Groups['n'].Value.Replace(',', '.'), [cultureinfo]::InvariantCulture)
    try { $value = [LambekMath]::Convert($amount, $from, $to) }
    catch { return $answer.Error -f $_.Exception.InnerException.Message }
    $shown = Format-LambekNumber -Number ([math]::Round($value, 4).ToString('0.####', [cultureinfo]::InvariantCulture)) -Language $Language
    # Symbols for the units that have one ("C" with its degree sign, "Go"), the user's words for the others
    $symbols = $answer.Symbols
    $first = $match.Groups['from'].Value
    $second = $match.Groups['to'].Value
    if ($symbols.ContainsKey($from)) { $first = $symbols[$from] }
    if ($symbols.ContainsKey($to)) { $second = $symbols[$to] }
    return $answer.Converted -f (Format-LambekNumber -Number $match.Groups['n'].Value -Language $Language), $first, $shown, $second
}

function Resolve-LambekDateQuestion {
    param([string] $Text, [hashtable] $Calculate, [string] $Language)

    # "combien de jours entre le 12 mars et le 3 octobre", "quel jour de la semaine etait le 1 janvier 2000",
    # "quelle date dans 45 jours"; a date without a year is in the current year
    $answer = (Get-LambekLexicon -Language $Language).Answer.Math
    $culture = [cultureinfo]::GetCultureInfo((Get-LambekLexicon -Language $Language).Answer.Files.Culture)
    $format = $answer.DateFormat
    $today = [datetime]::Today
    $dates = @(Get-LambekDateInText -Text $Text -Months $Calculate.Months -Today $today)

    if ([regex]::IsMatch($Text, $Calculate.Between) -and $dates.Count -ge 2) {
        $days = [LambekMath]::DaysBetween($dates[0], $dates[1])
        return Format-LambekPlural -Template $answer.Days -Language $Language -Values @([math]::Abs($days), $dates[0].ToString($format, $culture), $dates[1].ToString($format, $culture))
    }
    if ([regex]::IsMatch($Text, $Calculate.Weekday) -and $dates.Count -ge 1) {
        return $answer.Weekday -f $dates[0].ToString($format, $culture), $dates[0].ToString('dddd', $culture)
    }
    $later = [regex]::Match($Text, $Calculate.InDays)
    if ($later.Success) {
        $when = $today.AddDays([int] $later.Groups['n'].Value)
        return $answer.Later -f $later.Groups['n'].Value, $when.ToString("dddd $format", $culture)
    }
    return $null
}

function Get-LambekDateInText {
    param([string] $Text, [hashtable] $Months, [datetime] $Today)

    # "12 mars 2026", "march 12", "2026-03-12", "12/03/2026" (day first), "1er janvier"
    $names = ($Months.Keys | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $pattern = "(?<iso>\b\d{4}-\d{2}-\d{2}\b)|(?<dmy>\b\d{1,2}/\d{1,2}/\d{4}\b)|\b(?<d>\d{1,2})(?:er|st|nd|rd|th)?\s+(?<m>$names)(?:\s+(?<y>\d{4}))?\b|\b(?<m2>$names)\s+(?<d2>\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(?<y2>\d{4}))?\b"
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        try {
            if ($match.Groups['iso'].Success) { [datetime]::ParseExact($match.Value, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture); continue }
            if ($match.Groups['dmy'].Success) { [datetime]::ParseExact($match.Value, 'd/M/yyyy', [cultureinfo]::InvariantCulture); continue }
            $day = if ($match.Groups['d'].Success) { [int] $match.Groups['d'].Value } else { [int] $match.Groups['d2'].Value }
            $month = if ($match.Groups['m'].Success) { $Months[$match.Groups['m'].Value] } else { $Months[$match.Groups['m2'].Value] }
            $year = $Today.Year
            if ($match.Groups['y'].Success) { $year = [int] $match.Groups['y'].Value }
            elseif ($match.Groups['y2'].Success) { $year = [int] $match.Groups['y2'].Value }
            [datetime]::new($year, $month, $day)
        }
        catch { Write-Verbose "Not a date: $($match.Value)" }
    }
}

function Resolve-LambekMathFunction {
    param([string] $Plain, [hashtable] $Calculate, [string] $Language)

    # The operation named by the longest phrase of the question, as whole words; what follows it is its argument
    $text = ($Plain -replace '\s+', ' ').Trim()
    $best = $null
    foreach ($entry in $Calculate.Functions.GetEnumerator()) {
        foreach ($phrase in @($entry.Value)) {
            $match = [regex]::Match($text, "(?<![\p{L}\d])$([regex]::Escape($phrase))(?![\p{L}\d])")
            if (-not $match.Success) { continue }
            if (-not $best -or $phrase.Length -gt $best.Phrase.Length) { $best = [pscustomobject]@{ Operation = $entry.Key; Phrase = $phrase; At = $match.Index } }
        }
    }
    if (-not $best) { return $null }
    $before = $text.Substring(0, $best.At).Trim()
    $after = $text.Substring($best.At + $best.Phrase.Length).Trim()
    # The small words of the question around it ("quelle est la", "of", "de") go
    $lead = @($Calculate.Lead | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $after = ($after -replace "^(?:(?:$lead)\s+)+", '' -replace '\s*[?]+\s*$', '').Trim()
    $before = ($before -replace "^(?:(?:$lead)\s+)+", '' -replace "(?:\s+(?:$lead))+$", '').Trim()
    # A file request is never a calculation ("supprime les fichiers en double")
    if ("$before $after" -match '(?i)\b[a-z]:[\\/]|\\\\|(?<!\w)/\w+/') { return $null }
    $after = [LambekNumberWords]::Digitize($after, $Language)
    $before = [LambekNumberWords]::Digitize($before, $Language)
    $answer = (Get-LambekLexicon -Language $Language).Answer.Math
    $and = @($Calculate.And | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $numbers = @([regex]::Matches("$before $after", '-?\d+') | ForEach-Object { [System.Numerics.BigInteger]::Parse($_.Value) })

    try {
        switch ($best.Operation) {
            { $_ -in 'derivative', 'integral', 'simplify', 'expand' } {
                $expression = $after
                $letter = $null
                $respect = [regex]::Match(" $expression", $Calculate.Respect)
                if ($respect.Success) { $letter = $respect.Groups['v'].Value; $expression = (" $expression").Remove($respect.Index, $respect.Length).Trim() }
                $bounds = $null
                if ($_ -eq 'integral') {
                    $range = [regex]::Match(" $expression", $Calculate.Range)
                    if ($range.Success) { $bounds = @($range.Groups['a'].Value, $range.Groups['b'].Value); $expression = (" $expression").Substring(0, $range.Index).Trim() }
                }
                $expression = ($expression -replace '\s+d([a-z])\s*$', '').Trim()
                if (-not $expression -or $expression -notmatch '[a-z\d]') { return $null }
                $parsed = [LambekAlgebra]::Parse($expression)
                $letters = @([LambekAlgebra]::Letters($parsed))
                if (-not $letter) { $letter = $(if ('x' -in $letters) { 'x' } elseif ($letters.Count -gt 0) { $letters[0] } else { 'x' }) }
                $shown = [LambekAlgebra]::Show([LambekAlgebra]::Simplify($parsed))
                if ($_ -eq 'derivative') { return $answer.Derivative -f $letter, $shown, [LambekAlgebra]::Show([LambekAlgebra]::Derive($parsed, $letter)) }
                if ($_ -eq 'expand') { return $answer.Equal -f $shown, [LambekAlgebra]::Show([LambekAlgebra]::Expand($parsed)) }
                if ($_ -eq 'simplify') {
                    # A quotient of polynomials loses its common factor; any other expression is folded and collected
                    $reduced = [LambekAlgebra]::ReduceFraction($parsed, $letter)
                    if ($null -eq $reduced) { $reduced = [LambekAlgebra]::Simplify($parsed) }
                    return $answer.Equal -f $expression, [LambekAlgebra]::Show($reduced)
                }
                if ($bounds) {
                    $exact = $false
                    $value = [LambekAlgebra]::Definite($parsed, $letter, [LambekAlgebra]::Parse($bounds[0]), [LambekAlgebra]::Parse($bounds[1]), [ref] $exact)
                    $value = $value -replace '^\u2248 ', "$([char] 0x2248) "
                    if ($value -notmatch '^\u2248') { $value = "= $value" }
                    return ($answer.Definite -f $letter, $bounds[0], $bounds[1], $shown, $value) -replace '= =', '=' -replace '= \u2248', "$([char] 0x2248)"
                }
                $primitive = [LambekAlgebra]::Integrate($parsed, $letter)
                if ($null -eq $primitive) { return $answer.NoPrimitive -f $shown }
                return $answer.Primitive -f $letter, $shown, [LambekAlgebra]::Show($primitive)
            }
            'factor' {
                # A whole number into primes, or a polynomial into its rational roots and what is left
                if ($after -match '^\s*(\d+)\s*$') {
                    $n = [System.Numerics.BigInteger]::Parse($Matches[1])
                    return $answer.Factors -f $n, (([LambekNumbers]::Factor($n)) -join " $([char] 0x00D7) ")
                }
                if (-not $after) { return $null }
                $parsed = [LambekAlgebra]::Parse($after)
                $letters = @([LambekAlgebra]::Letters($parsed))
                if ($letters.Count -ne 1) { return $null }
                return $answer.Equal -f [LambekAlgebra]::Show([LambekAlgebra]::Simplify($parsed)), [LambekMath]::FactorPolynomial([LambekAlgebra]::ToPolynomial($parsed, $letters[0]), $letters[0])
            }
            'prime' {
                if ($numbers.Count -ne 1) { return $null }
                $n = $numbers[0]
                $certain = $false
                if ([LambekNumbers]::IsPrime($n, [ref] $certain)) { if ($certain) { return $answer.Prime -f $n } else { return $answer.ProbablePrime -f $n } }
                if ($n -lt 2) { return $answer.NotPrime -f $n, $n }
                return $answer.NotPrime -f $n, (([LambekNumbers]::Factor($n)) -join " $([char] 0x00D7) ")
            }
            { $_ -in 'gcd', 'lcm' } {
                if ($numbers.Count -lt 2) { return $null }
                $value = if ($_ -eq 'gcd') { [LambekNumbers]::Gcd([System.Numerics.BigInteger[]] $numbers) } else { [LambekNumbers]::Lcm([System.Numerics.BigInteger[]] $numbers) }
                $template = if ($_ -eq 'gcd') { $answer.Gcd } else { $answer.Lcm }
                return $template -f ($numbers -join ', '), $value
            }
            'base' {
                # "255 en binaire", "ff en base 10" (a number written in a base: "0x", "0b", or "de base 16")
                $target = $null
                foreach ($word in $Calculate.Bases.Keys) { if ($best.Phrase.EndsWith($word) -or $after -match "^$word\b") { $target = [int] $Calculate.Bases[$word] } }
                if (-not $target -and $after -match '^(\d+)\b') { $target = [int] $Matches[1] }
                if (-not $target) { return $null }
                $source = $before -replace '^.*?(?:(?:convert\w*|ecris|schreibe|escribe|scrivi|schrijf|escreve)\s+)', ''
                $value = $null
                if ($source -match '^(?:0x)([0-9a-f]+)$') { $value = [LambekNumbers]::FromBase($Matches[1], 16) }
                elseif ($source -match '^(?:0b)([01]+)$') { $value = [LambekNumbers]::FromBase($Matches[1], 2) }
                elseif ($source -match '^(-?\d+)$') { $value = [System.Numerics.BigInteger]::Parse($Matches[1]) }
                if ($null -eq $value) { return $null }
                return $answer.Base -f $source, $target, [LambekNumbers]::ToBase($value, $target)
            }
            { $_ -in 'choose', 'arrange' } {
                if ($numbers.Count -ne 2) { return $null }
                # "3 parmi 10", "10 choose 3": the larger is n
                $n = [System.Numerics.BigInteger]::Max($numbers[0], $numbers[1])
                $k = [System.Numerics.BigInteger]::Min($numbers[0], $numbers[1])
                if ($_ -eq 'choose') { return $answer.Choose -f $n, $k, [LambekNumbers]::Choose($n, $k) }
                return $answer.Arrange -f $n, $k, [LambekNumbers]::Arrangements($n, $k)
            }
            { $_ -in 'mean', 'median', 'variance', 'stddev', 'statistics' } {
                $values = @([regex]::Matches($after, '-?\d+(?:[.,]\d+)?(?:/\d+)?(?=\s*(?:[;,]|\s|$))') | ForEach-Object {
                        $parts = $_.Value.Replace(',', '.').Split('/')
                        $q = [LambekRational]::Parse($parts[0])
                        if ($parts.Count -gt 1) { $q = $q / [LambekRational]::Parse($parts[1]) }
                        $q
                    })
                # Decimal commas: in a list "1,5; 2,5" the semicolon separates; "1, 2, 3" is three numbers
                if ($after -notmatch ';') {
                    $values = @([regex]::Matches($after, '-?\d+(?:\.\d+)?(?:/\d+)?') | ForEach-Object {
                            $parts = $_.Value.Split('/')
                            $q = [LambekRational]::Parse($parts[0])
                            if ($parts.Count -gt 1) { $q = $q / [LambekRational]::Parse($parts[1]) }
                            $q
                        })
                }
                if ($values.Count -eq 0) { return $null }
                $stats = [LambekNumbers]::Statistics([LambekRational[]] $values)
                $names = $answer.Statistics
                $keys = switch ($_) {
                    'mean' { @('mean') }
                    'median' { @('median') }
                    'variance' { @('variance', 'samplevariance') }
                    'stddev' { @('stddev', 'samplestddev') }
                    default { @('count', 'sum', 'mean', 'median', 'mode', 'min', 'max', 'range', 'variance', 'stddev', 'samplevariance', 'samplestddev') }
                }
                $lines = foreach ($key in $keys) {
                    if (-not $stats.ContainsKey($key)) { continue }
                    $value = $stats[$key]
                    # A fraction also as a decimal
                    if ($value -match '^-?\d+/\d+$') {
                        $exact = $false
                        $parts = $value.Split('/')
                        $decimal = ([LambekRational]::new([System.Numerics.BigInteger]::Parse($parts[0]), [System.Numerics.BigInteger]::Parse($parts[1]))).Decimal(10, [ref] $exact)
                        $value = "$value $([char] 0x2248) $(Format-LambekNumber -Number $decimal -Language $Language)"
                    }
                    elseif ($value -match '\u2248') { $value = $value -replace '(?<=\u2248 )(\S+)$', { Format-LambekNumber -Number $_.Value -Language $Language } }
                    $answer.Stat -f $names[$key], $value
                }
                return @($lines) -join "`n"
            }
            'words' {
                if ($numbers.Count -ne 1) { return $null }
                return $answer.Words -f $numbers[0], [LambekNumberWords]::Write($numbers[0], $Language)
            }
            'fibonacci' {
                if ($numbers.Count -ne 1) { return $null }
                return $answer.Fibonacci -f $numbers[0], [LambekNumbers]::Fibonacci([int] $numbers[0])
            }
            'totient' {
                if ($numbers.Count -ne 1) { return $null }
                return $answer.Totient -f $numbers[0], [LambekNumbers]::Totient($numbers[0])
            }
            'divisors' {
                if ($numbers.Count -ne 1 -or $numbers[0] -lt 1 -or $numbers[0] -gt 1000000000000) { return $null }
                $n = [long] $numbers[0]
                $small = [System.Collections.Generic.List[long]]::new()
                $large = [System.Collections.Generic.List[long]]::new()
                for ($d = 1L; $d * $d -le $n; $d++) { if ($n % $d -eq 0) { $small.Add($d); if ($d * $d -ne $n) { $large.Insert(0, $n / $d) } } }
                $all = @($small) + @($large)
                return $answer.Divisors -f $n, ($all -join ', '), $all.Count
            }
            'system' {
                # Equations separated by "," ";" or "and" in the language
                $equations = @(($after -split "\s*(?:[;,]|\b(?:$and)\b)\s*") | Where-Object { $_ -match '=' })
                if ($equations.Count -lt 1) { return $null }
                $result = [LambekLinear]::Solve([string[]] $equations)
                if ($result.Kind -eq 'none') { return $answer.SystemNone }
                $pairs = for ($k = 0; $k -lt $result.Letters.Count; $k++) { if ($result.Values[$k] -ne $result.Letters[$k]) { "$($result.Letters[$k]) = $($result.Values[$k])" } }
                if ($result.Kind -eq 'unique') {
                    # Every value put back in every equation
                    $values = @{}
                    for ($k = 0; $k -lt $result.Letters.Count; $k++) { $values[$result.Letters[$k]] = $result.Values[$k] }
                    $checks = @(foreach ($equation in $equations) { Get-LambekEquationCheck -Expression $equation -Values $values -Language $Language })
                    $said = $answer.SystemOne -f ($pairs -join ', ')
                    if ($answer.Check -and $checks.Count -gt 0 -and $checks -notcontains $null) { $said += "`n" + ($answer.Check -f ($checks -join ' ; ')) }
                    return $said
                }
                return $answer.SystemMany -f ($pairs -join ', '), ($result.Free -join ', ')
            }
            { $_ -in 'determinant', 'inverse', 'rank', 'eigen', 'transpose' } {
                # "inverse de 3 modulo 11" is modular arithmetic, not a matrix
                if ($_ -eq 'inverse' -and $after -match '^(-?\d+)\s+(?:mod|modulo|modulus)\s+(\d+)') {
                    return $answer.ModInverse -f $Matches[1], $Matches[2], [LambekNumbers]::ModInverse([System.Numerics.BigInteger]::Parse($Matches[1]), [System.Numerics.BigInteger]::Parse($Matches[2]))
                }
                if ($after -notmatch '[\[(;]|\d\s+\d') { return $null }
                $matrix = [LambekMatrix]::Parse(($after -replace '^[^\[(\d-]*', ''))
                switch ($_) {
                    'determinant' { return $answer.Determinant -f $matrix.Determinant().Exact() }
                    'inverse' { return $answer.Inverse -f $matrix.Inverse().Show() }
                    'rank' { return $answer.Rank -f $matrix.Rank() }
                    'transpose' { return $answer.Transpose -f $matrix.Transpose().Show() }
                    'eigen' {
                        $characteristic = $matrix.Characteristic()
                        $solved = [LambekMath]::Solve($characteristic, 'x')
                        $roots = @($solved.Roots | ForEach-Object { if ($_.StartsWith('~')) { "$([char] 0x2248) " + (Format-LambekNumber -Number $_.Substring(1) -Language $Language) } else { $_ } })
                        if ($solved.Note -eq 'complex' -or $roots.Count -eq 0) { $roots = @($answer.Complex) }
                        return $answer.Eigen -f ($roots -join ', '), [LambekPolynomials]::Show($characteristic, [char] 0x03BB)
                    }
                }
            }
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($_.Exception.InnerException) { $message = $_.Exception.InnerException.Message }
        return $answer.Error -f $message
    }
    return $null
}
