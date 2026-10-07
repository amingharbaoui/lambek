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

        # Every token made only of letters, digits, or _: words, numbers, and keywords like "in" or "for"
        foreach ($token in $tokens) {
            if ($token.Text -match '^[\p{L}\p{N}_]+$') {
                $words.Add($token.Text)
            }
            # A word with the punctuation that ends a sentence glued to it ("why?", "ok!")
            elseif ($token.Text -match '^(?<word>[\p{L}\p{N}_]+)[?!.,;:]+$') {
                $words.Add($Matches['word'])
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
