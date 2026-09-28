function Get-LambekLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Tokens
    )

    # Words of each language in the text
    $scores = [ordered]@{}
    foreach ($language in Get-LambekAvailableLanguage) {
        $lexicon = Get-LambekLexicon -Language $language
        $score = 0
        foreach ($token in $Tokens) {
            if ($lexicon.Signals.Contains($token.ToLowerInvariant())) { $score++ }
        }
        $scores[$language] = $score
    }

    # One clear winner, otherwise the language of the chat, otherwise English
    $best = ($scores.Values | Measure-Object -Maximum).Maximum
    $winners = @($scores.Keys | Where-Object { $scores[$_] -eq $best })
    if ($best -gt 0 -and $winners.Count -eq 1) { return $winners[0] }
    if ($script:LanguageHint) { return $script:LanguageHint }
    if ($best -gt 0) { return $winners[0] }
    return 'en'
}

function Test-LambekLanguageSignal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # True when the words point to one language more than to the others
    $words = @((ConvertTo-LambekNormalizedText -Text $Text) -split '[^\p{L}\p{N}]+' | Where-Object { $_ })
    $scores = @(foreach ($language in Get-LambekAvailableLanguage) {
            $lexicon = Get-LambekLexicon -Language $language
            @($words | Where-Object { $lexicon.Signals.Contains($_) }).Count
        })
    $best = ($scores | Measure-Object -Maximum).Maximum
    return $best -gt 0 -and @($scores | Where-Object { $_ -eq $best }).Count -eq 1
}
