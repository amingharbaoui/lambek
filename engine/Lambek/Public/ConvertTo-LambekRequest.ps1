function ConvertTo-LambekRequest {
    <#
    .SYNOPSIS
        Converts a plain-language request into a structured Lambek request.
    .EXAMPLE
        ConvertTo-LambekRequest 'Delete the files older than 30 days in C:\Temp'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateLength(1, 2000)]
        [string] $Text,

        [ValidateSet('auto', 'en', 'fr')]
        [string] $Language = 'auto'
    )

    process {
        # Entities
        $composed = $Text.Normalize([System.Text.NormalizationForm]::FormC)
        $extraction = Get-LambekEntity -Text $composed

        # Normalization and tokens
        $normalized = ConvertTo-LambekNormalizedText -Text $extraction.Remainder
        $tokenization = Get-LambekToken -Text $normalized

        # Language
        $detectedLanguage = $Language
        if ($Language -eq 'auto') {
            $detectedLanguage = Get-LambekLanguage -Tokens $tokenization.Tokens
        }

        # Terms and n-grams
        $terms = @(Select-LambekTerm -Tokens $tokenization.Tokens -Language $detectedLanguage)
        $nGrams = @(Get-LambekCharNGram -Terms $terms)

        # Hash
        $canonical = $terms -join ' '
        $hash = Get-LambekHash -Text "$detectedLanguage|$canonical"

        [pscustomobject]@{
            PSTypeName = 'Lambek.Request'
            Original   = $Text
            Language   = $detectedLanguage
            Normalized = $normalized
            Tokenizer  = $tokenization.Tokenizer
            Tokens     = $tokenization.Tokens
            Terms      = $terms
            CharNGrams = $nGrams
            Entities   = $extraction.Entities
            Canonical  = $canonical
            Hash       = $hash
        }
    }
}
