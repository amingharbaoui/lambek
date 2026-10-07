function ConvertFrom-LambekLogic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # Clauses end with a dot; % starts a comment; strings are in double quotes, "" for a quote inside
    # (no backslash escapes, so paths like "C:\Temp\" keep their backslashes)
    # The clauses are LambekClause objects, and the engine that runs them is LambekLogic (Native/Lambek.cs)
    $clauses = [System.Collections.Generic.List[LambekClause]]::new()
    $clean = [regex]::Replace($Text, '"(?:[^"]|"")*"|%[^\n]*', { param($m) if ($m.Value.StartsWith('%')) { '' } else { $m.Value } })
    foreach ($match in [regex]::Matches($clean, '(?s)((?:"(?:[^"]|"")*"|[^."])+)\.')) {
        $clause = $match.Groups[1].Value.Trim()
        if (-not $clause) { continue }
        $parts = $clause -split ':-', 2
        $head = ConvertFrom-LambekLiteral -Text $parts[0]
        $body = @()
        if ($parts.Count -gt 1) {
            $body = @(foreach ($literal in [regex]::Matches($parts[1], '(?:not\s+)?[a-z_][\w]*\s*\((?:"(?:[^"]|"")*"|[^)"])*\)')) { ConvertFrom-LambekLiteral -Text $literal.Value })
        }
        $clauses.Add([LambekClause]::new($head, [LambekLiteral[]] $body))
    }
    return , $clauses
}

function ConvertFrom-LambekLiteral {
    param([string] $Text)

    $text = $Text.Trim()
    $negated = $false
    if ($text -match '^not\s+') { $negated = $true; $text = $text -replace '^not\s+', '' }
    if ($text -notmatch '^(?<name>[a-z_][\w]*)\s*\((?<terms>.*)\)$') { throw "'$Text' is not a literal like name(A, ""b"")." }
    $name = $Matches['name']
    $terms = @(foreach ($term in [regex]::Matches($Matches['terms'], '"(?:[^"]|"")*"|[^,\s]+')) {
            $value = $term.Value
            if ($value.StartsWith('"')) { [string] [char] 0 + $value.Substring(1, $value.Length - 2).Replace('""', '"') }
            # An aggregate of the head: count<X>, sum<X>, min<X>, max<X>
            elseif ($value -match '^(?<op>count|sum|min|max)<(?<var>[A-Z_]\w*)>$') { "#$($Matches['op']):$($Matches['var'])" }
            elseif ([char]::IsUpper($value[0]) -or $value[0] -eq '_') { $value }
            else { [string] [char] 0 + $value }
        })
    return [LambekLiteral]::new($name, [string[]] $terms, $negated)
}
