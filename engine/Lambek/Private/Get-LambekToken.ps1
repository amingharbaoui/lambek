function Get-LambekToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [pscustomobject]@{ Tokens = [string[]] @(); Tokenizer = 'None' }
    }

    # PowerShell parser
    $tokens = $null
    $errors = $null
    [void] [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref] $tokens, [ref] $errors)

    if ($errors.Count -eq 0) {
        $words = [System.Collections.Generic.List[string]]::new()

        foreach ($token in $tokens) {
            $isWord = $token.Kind -in @('Identifier', 'Generic', 'Number')
            $isKeyword = $token.TokenFlags.HasFlag([System.Management.Automation.Language.TokenFlags]::Keyword)

            if (($isWord -or $isKeyword) -and $token.Text -match '^[\p{L}\p{N}_]+$') {
                $words.Add($token.Text)
            }
        }

        return [pscustomobject]@{ Tokens = $words.ToArray(); Tokenizer = 'PowerShellParser' }
    }

    # Fallback
    $fallback = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Text, '[\p{L}\p{N}_]+')) {
        $fallback.Add($match.Value)
    }

    return [pscustomobject]@{ Tokens = $fallback.ToArray(); Tokenizer = 'RegexFallback' }
}
