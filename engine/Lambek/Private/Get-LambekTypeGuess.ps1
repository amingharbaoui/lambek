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

    # One equation, one unknown: a sentence with exactly one word the grammar does not know
    # ("get rid of" has two, so nothing can be solved from it)
    $unknown = @($Grammar.Unknown | Select-Object -Unique)
    if (($Grammar.IsSentence -and -not $Keeping) -or $unknown.Count -ne 1) { return $null }

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
