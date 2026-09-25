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

    # Lower case, apostrophes and spaces
    $result = $result.ToLowerInvariant()
    $result = $result -replace '[\u0027\u2019\u2018\u0060]', ' '
    $result = $result -replace '\s+', ' '

    return $result.Trim()
}
