function Get-LambekTypeGuess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        [Parameter(Mandatory)]
        [pscustomobject] $Grammar,

        # The sentence already reduces: find the types that keep it a sentence (a word that narrows, like "temporary")
        [switch] $Keeping
    )

    # One equation, one unknown: a sentence with exactly one word the grammar does not know. Two unknowns are solved
    # together, each kept to the types the words of its part of speech take (Get-LambekTwoTypeGuess)
    $unknown = @($Grammar.Unknown | Select-Object -Unique)
    if ($Grammar.IsSentence -and -not $Keeping) { return $null }
    if ($unknown.Count -eq 2 -and -not $Keeping) { return Get-LambekTwoTypeGuess -Request $Request -Unknown $unknown }
    if ($unknown.Count -ne 1) { return $null }

    # Every type the lexicon gives a word: the only types a new word can take
    $lexicon = Get-LambekGrammarLexicon -Language $Request.Language
    $inventory = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($types in $lexicon.Words.Values) { foreach ($type in $types) { [void] $inventory.Add($type) } }

    # Count invariant first: the counts the other words can reach, so only a type T that completes one to s is reduced
    $reachable = [System.Collections.Generic.HashSet[string]]::new()
    [void] $reachable.Add('')
    foreach ($word in $Request.Words) {
        if (-not $lexicon.Words.ContainsKey($word)) { continue }
        $next = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($count in $reachable) {
            foreach ($type in $lexicon.Words[$word]) { [void] $next.Add((Get-LambekTypeCountKey -Count $count -Type $type)) }
        }
        $reachable = $next
    }

    # Solve the equation: which type T lets "... word ..." reduce to s
    foreach ($word in $unknown) {
        $solutions = foreach ($type in $inventory) {
            $times = @($Request.Words | Where-Object { $_ -eq $word }).Count
            $count = ''
            for ($k = 0; $k -lt $times; $k++) { $count = Get-LambekTypeCountKey -Count $count -Type $type }
            $fits = $false
            foreach ($other in $reachable) {
                if ((Get-LambekTypeCountKey -Count $other -Type '' -Add $count) -eq 's:1') { $fits = $true; break }
            }
            if (-not $fits) { continue }

            $trial = Resolve-LambekGrammar -Request $Request -Hypothesis @{ $word = @($type) } -SentenceOnly
            if ($trial.IsSentence) { $type }
        }
        if (@($solutions).Count -eq 0) { continue }

        # The word as it was typed, before its plural was cut
        $token = $word
        for ($i = 0; $i -lt $Request.Words.Count; $i++) {
            if ($Request.Words[$i] -eq $word) { $token = $Request.Tokens[$i]; break }
        }

        return [pscustomobject]@{
            Word     = $word
            Token    = $token
            Language = $Request.Language
            Types    = [string[]] @($solutions)
            IsAction = @($solutions | Where-Object { $_ -match '(^|\s)s(\s|$)' }).Count -gt 0
        }
    }
    return $null
}

function Get-LambekTypeCountKey {
    param([string] $Count, [string] $Type, [string] $Add = '')

    # A count as text, "o:0;s:1": for each base, even orders minus odd orders, zeros left out
    $total = @{}
    foreach ($part in @($Count, $Add)) {
        foreach ($item in $part -split ';' | Where-Object { $_ }) {
            $pair = $item -split ':'
            $total[$pair[0]] = $total[$pair[0]] + [int] $pair[1]
        }
    }
    if ($Type) {
        foreach ($simpleType in ConvertFrom-LambekType -Type $Type) {
            $sign = 1
            if ([math]::Abs($simpleType.Order) % 2 -eq 1) { $sign = -1 }
            $total[$simpleType.Base] = $total[$simpleType.Base] + $sign
        }
    }
    return (@($total.Keys | Where-Object { $total[$_] -ne 0 } | Sort-Object | ForEach-Object { "$($_):$($total[$_])" }) -join ';')
}

function Get-LambekTwoTypeGuess {
    param(
        [pscustomobject] $Request,
        [string[]] $Unknown
    )

    # Two words the grammar does not know ("zorglube les flurps dans C:\Temp"): one equation, two unknowns. The learned
    # forms say what each word is in this sentence (a verb, a noun), and a word may only take the types the words of
    # the lexicon with that part of speech take; every pair of such types that lets the sentence reduce to s is a
    # solution. The word that names an action is the one asked about; the other is said with it
    # Two unknowns need something to hold on to: a value the order is about ("C:\Temp", ".tmp"). Without one ("suprimer
    # fichers", "parles tu anglais"), the closest request or the small talk says it better than a guess
    if (@($Request.Entities).Count -eq 0) { return $null }
    $lexicon = Get-LambekGrammarLexicon -Language $Request.Language
    $byPart = Get-LambekPartType -Language $Request.Language
    $words = Get-LambekSentenceReading -Text "$($Request.Original)" -Language $Request.Language
    $candidates = @{}
    foreach ($word in $Unknown) {
        $token = $word
        for ($i = 0; $i -lt $Request.Words.Count; $i++) { if ($Request.Words[$i] -eq $word) { $token = $Request.Tokens[$i]; break } }
        $parts = @()
        if ($words) { $parts = @($words.Lemmas($token, $Request.Language) | ForEach-Object { $_.Pos } | Select-Object -Unique) }
        $types = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($part in $parts) { if ($byPart.ContainsKey($part)) { foreach ($type in $byPart[$part]) { [void] $types.Add($type) } } }
        if ($types.Count -eq 0) { return $null }
        $candidates[$word] = [pscustomobject]@{ Token = $token; Types = [string[]] @($types) }
    }

    # The counts the known words can reach, then the pairs of types that complete one to s
    $reachable = [System.Collections.Generic.HashSet[string]]::new()
    [void] $reachable.Add('')
    foreach ($word in $Request.Words) {
        if (-not $lexicon.Words.ContainsKey($word)) { continue }
        $next = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($count in $reachable) { foreach ($type in $lexicon.Words[$word]) { [void] $next.Add((Get-LambekTypeCountKey -Count $count -Type $type)) } }
        $reachable = $next
    }
    $first = $Unknown[0]
    $second = $Unknown[1]
    $times = @{}
    foreach ($word in $Unknown) { $times[$word] = @($Request.Words | Where-Object { $_ -eq $word }).Count }
    $solutions = [System.Collections.Generic.List[object]]::new()
    foreach ($one in $candidates[$first].Types) {
        foreach ($other in $candidates[$second].Types) {
            $count = ''
            for ($k = 0; $k -lt $times[$first]; $k++) { $count = Get-LambekTypeCountKey -Count $count -Type $one }
            for ($k = 0; $k -lt $times[$second]; $k++) { $count = Get-LambekTypeCountKey -Count $count -Type $other }
            $fits = $false
            foreach ($known in $reachable) { if ((Get-LambekTypeCountKey -Count $known -Type '' -Add $count) -eq 's:1') { $fits = $true; break } }
            if (-not $fits) { continue }
            $trial = Resolve-LambekGrammar -Request $Request -Hypothesis @{ $first = @($one); $second = @($other) } -SentenceOnly
            if ($trial.IsSentence) { $solutions.Add([pscustomobject]@{ $first = $one; $second = $other }) }
        }
    }
    if ($solutions.Count -eq 0) { return $null }

    # The word asked about: the one whose types name an action, the other said with what it is
    $action = { param($type) $type -match '(^|\s)s(\s|$)' }
    $asked = $first
    if (@($solutions | Where-Object { & $action $_.$second }).Count -gt @($solutions | Where-Object { & $action $_.$first }).Count) { $asked = $second }
    $with = @($Unknown | Where-Object { $_ -ne $asked })[0]
    $types = [string[]] @($solutions | ForEach-Object { $_.$asked } | Select-Object -Unique)
    return [pscustomobject]@{
        Word     = $asked
        Token    = $candidates[$asked].Token
        Language = $Request.Language
        Types    = $types
        IsAction = @($types | Where-Object { & $action $_ }).Count -gt 0
        Also     = [pscustomobject]@{ Word = $with; Token = $candidates[$with].Token; Types = [string[]] @($solutions | ForEach-Object { $_.$with } | Select-Object -Unique) }
    }
}

function Get-LambekPartType {
    param([string] $Language)

    # The types the words of the lexicon take, by their part of speech as the learned forms read them out of any
    # sentence ("fichiers": a noun, o; "supprime": a verb, s o^l): the only types a new word of that part may take
    if ($null -eq $script:PartTypes) { $script:PartTypes = @{} }
    $signature = "$Language|" + (@($script:Packs.Values | ForEach-Object { [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($_) }) -join ',')
    if ($script:PartTypes.ContainsKey($signature)) { return $script:PartTypes[$signature] }
    $byPart = @{}
    $model = Get-LambekFormModel -Language $Language
    if ($model) {
        $learned = [LambekLearnedWords]::new($model, $Language)
        $lexicon = Get-LambekGrammarLexicon -Language $Language
        foreach ($word in @($lexicon.Words.Keys | Sort-Object)) {
            # (only the words of one part: "liste" is a noun and a verb, it says nothing of either)
            $parts = @($learned.Lemmas($word, $Language) | ForEach-Object { $_.Pos } | Where-Object { $_ -in 'n', 'v', 'a' } | Select-Object -Unique)
            if ($parts.Count -ne 1) { continue }
            $part = $parts[0]
            if (-not $byPart.ContainsKey($part)) { $byPart[$part] = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal) }
            foreach ($type in $lexicon.Words[$word]) { [void] $byPart[$part].Add($type) }
        }
    }
    $script:PartTypes[$signature] = $byPart
    return $byPart
}
