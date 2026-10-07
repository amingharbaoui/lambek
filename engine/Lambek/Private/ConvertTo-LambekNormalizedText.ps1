function ConvertTo-LambekNormalizedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # Remove accents
    $decomposed = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = [System.Text.StringBuilder]::new()

    foreach ($character in $decomposed.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void] $builder.Append($character)
        }
    }

    $result = $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC)

    # Lower case, apostrophes and spaces; a pronoun joined to its verb stands alone ("deplace-les" is "deplace les")
    $result = $result.ToLowerInvariant().Replace([string] [char] 0x00DF, 'ss')
    $result = $result -replace '(?<=\p{L})-(?=(?:les|le|la|lui|leur|moi|toi|nous|vous|en|y|them|it|os|as|o|a|lhes?|los|las|lo)\b)', ' '
    $result = $result -replace '[\u0027\u2019\u2018\u0060]', ' '
    $result = $result -replace '\s+', ' '

    return $result.Trim()
}
