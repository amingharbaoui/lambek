function ConvertTo-LambekCodeLiteral {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [ValidateSet('PowerShell', 'Python', 'JavaScript', 'CSharp', 'Rust', 'Bash')]
        [string] $Language
    )

    # A text that could not be written back safely is refused before any code is made
    $problem = Test-LambekCodeText -Value $Value
    if ($problem) {
        throw "This text cannot be written in code: $problem."
    }

    # Bash: single quotes keep every character as it is, only the single quote itself is closed and opened again
    if ($Language -eq 'Bash') {
        return "'" + $Value.Replace("'", "'\''") + "'"
    }

    # PowerShell: single quotes when no character needs an escape (the usual case), else double quotes
    if ($Language -eq 'PowerShell') {
        $plain = $true
        foreach ($rune in $Value.EnumerateRunes()) {
            if (Test-LambekCodeEscape -Rune $rune) { $plain = $false }
        }
        if ($plain) {
            return "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value) + "'"
        }
    }

    # The other languages (and PowerShell with control characters): double quotes with escapes
    $builder = [System.Text.StringBuilder]::new()
    [void] $builder.Append('"')
    foreach ($rune in $Value.EnumerateRunes()) {
        $text = $rune.ToString()
        $code = $rune.Value

        if (Test-LambekCodeEscape -Rune $rune) {
            # A control or invisible character is written by its number
            if ($Language -eq 'PowerShell') { [void] $builder.Append('`u{' + $code.ToString('X') + '}') }
            elseif ($Language -eq 'Python' -and $code -le 0xFFFF) { [void] $builder.Append('\u' + $code.ToString('x4')) }
            elseif ($Language -eq 'Python') { [void] $builder.Append('\U' + $code.ToString('x8')) }
            elseif ($Language -eq 'CSharp' -and $code -le 0xFFFF) { [void] $builder.Append('\u' + $code.ToString('x4')) }
            elseif ($Language -eq 'CSharp') { [void] $builder.Append('\U' + $code.ToString('x8')) }
            else { [void] $builder.Append('\u{' + $code.ToString('x') + '}') }
        }
        elseif ($Language -eq 'PowerShell') {
            # Inside double quotes PowerShell reads the backtick, the dollar and every kind of double quote
            if ($text -eq '`' -or $text -eq '$' -or $code -in 0x22, 0x201C, 0x201D, 0x201E) { [void] $builder.Append('`') }
            [void] $builder.Append($text)
        }
        else {
            # Python, JavaScript, C# and Rust all read the backslash and the double quote the same way
            if ($text -eq '\' -or $text -eq '"') { [void] $builder.Append('\') }
            [void] $builder.Append($text)
        }
    }
    [void] $builder.Append('"')
    return $builder.ToString()
}

function Test-LambekCodeEscape {
    param([System.Text.Rune] $Rune)

    # Control characters, invisible format characters (the ones that reorder text) and characters with no meaning
    $category = [System.Text.Rune]::GetUnicodeCategory($Rune)
    return $category -in @(
        [System.Globalization.UnicodeCategory]::Control
        [System.Globalization.UnicodeCategory]::Format
        [System.Globalization.UnicodeCategory]::LineSeparator
        [System.Globalization.UnicodeCategory]::ParagraphSeparator
        [System.Globalization.UnicodeCategory]::PrivateUse
        [System.Globalization.UnicodeCategory]::OtherNotAssigned
    )
}

function Test-LambekCodeText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    # A line break never belongs to a path or a name, and no shell or compiler agrees on how to write one
    if ($Value -match '[\r\n\u0085\u2028\u2029]') { return 'it contains a line break' }
    if ($Value.Contains([string] [char] 0)) { return 'it contains a null character' }

    # Half of a character pair cannot be saved in a source file
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $character = $Value[$i]
        if ([char]::IsHighSurrogate($character)) {
            if ($i + 1 -ge $Value.Length -or -not [char]::IsLowSurrogate($Value[$i + 1])) { return 'it is not valid Unicode text' }
            $i++
        }
        elseif ([char]::IsLowSurrogate($character)) { return 'it is not valid Unicode text' }
    }
    return $null
}

function ConvertTo-LambekCodeComment {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # A comment stays on its line and shows what it holds: line breaks become spaces, invisible characters a "?"
    $builder = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $character = $Text[$i]
        if ([char]::IsSurrogate($character)) {
            $paired = [char]::IsHighSurrogate($character) -and $i + 1 -lt $Text.Length -and [char]::IsLowSurrogate($Text[$i + 1])
            if (-not $paired) { [void] $builder.Append('?'); continue }
            $rune = [System.Text.Rune]::new($character, $Text[$i + 1])
            $i++
        }
        else { $rune = [System.Text.Rune]::new($character) }

        if ($rune.Value -in 9, 10, 13) { [void] $builder.Append(' ') }
        elseif (Test-LambekCodeEscape -Rune $rune) { [void] $builder.Append('?') }
        else { [void] $builder.Append($rune.ToString()) }
    }
    return ($builder.ToString() -replace ' {2,}', ' ').Trim()
}
