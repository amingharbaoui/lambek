function ConvertTo-LambekCodeIdentifier {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        # snake_case (Python, Rust, Bash), camelCase (JavaScript) or PascalCase (classes, C#)
        [Parameter(Mandatory)]
        [ValidateSet('snake', 'camel', 'pascal')]
        [string] $Style
    )

    # Accents are dropped: "Resume" for a name typed with accents
    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $Name.Normalize([System.Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void] $builder.Append($character)
        }
    }

    # The words of the name: "Get-Report", "get_report", "getReport" and "get report" are all "get" + "report"
    $words = [System.Collections.Generic.List[string]]::new()
    foreach ($found in [regex]::Matches($builder.ToString(), '[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+')) {
        $words.Add($found.Value.ToLowerInvariant())
    }
    if ($words.Count -eq 0) {
        throw "'$Name' is not a valid name."
    }

    # Joined the way the language writes its names
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($word in $words) {
        $isFirst = $parts.Count -eq 0
        if ($Style -eq 'snake' -or ($Style -eq 'camel' -and $isFirst)) { $parts.Add($word) }
        else { $parts.Add($word.Substring(0, 1).ToUpperInvariant() + $word.Substring(1)) }
    }
    $separator = ''
    if ($Style -eq 'snake') { $separator = '_' }
    $identifier = $parts -join $separator

    # A name never starts with a digit, and is never a word one of the six languages keeps for itself
    if ($identifier -match '^[0-9]') { $identifier = "_$identifier" }
    $reserved = @(
        'abstract', 'and', 'as', 'assert', 'async', 'await', 'base', 'bool', 'break', 'byte', 'case', 'catch', 'char',
        'class', 'const', 'continue', 'crate', 'debugger', 'decimal', 'def', 'default', 'del', 'delegate', 'delete', 'do',
        'done', 'double', 'dyn', 'elif', 'else', 'enum', 'esac', 'event', 'except', 'explicit', 'export', 'extends',
        'extern', 'false', 'fi', 'finally', 'fixed', 'float', 'fn', 'for', 'foreach', 'from', 'function', 'global',
        'goto', 'if', 'impl', 'implicit', 'import', 'in', 'instanceof', 'int', 'interface', 'internal', 'is', 'lambda',
        'let', 'lock', 'long', 'loop', 'main', 'match', 'mod', 'move', 'mut', 'namespace', 'new', 'none', 'nonlocal',
        'not', 'null', 'object', 'operator', 'or', 'out', 'override', 'params', 'pass', 'private', 'protected', 'pub',
        'public', 'raise', 'readonly', 'ref', 'return', 'sbyte', 'sealed', 'select', 'self', 'short', 'sizeof',
        'stackalloc', 'static', 'string', 'struct', 'super', 'switch', 'test', 'then', 'this', 'throw', 'time', 'trait',
        'true', 'try', 'type', 'typeof', 'uint', 'ulong', 'unchecked', 'unsafe', 'until', 'use', 'ushort', 'using',
        'var', 'virtual', 'void', 'volatile', 'where', 'while', 'with', 'yield'
    )
    if ($identifier.ToLowerInvariant() -in $reserved) { $identifier = "${identifier}_" }
    return $identifier
}
