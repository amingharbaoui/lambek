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

        [ValidatePattern('^(auto|[a-z]{2})$')]
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
        elseif ($Language -notin (Get-LambekAvailableLanguage)) {
            throw "Language '$Language' is not available."
        }

        # Spelling
        $spelling = Repair-LambekSpelling -Tokens $tokenization.Tokens -Language $detectedLanguage

        # Words, terms, and n-grams
        $words = @(ConvertTo-LambekBaseForm -Tokens $spelling.Tokens -Language $detectedLanguage)
        $terms = @(Select-LambekTerm -Words $words -Language $detectedLanguage)
        $nGrams = @(Get-LambekCharNGram -Terms $terms)

        # Hash
        $canonical = $terms -join ' '
        $hash = Get-LambekHash -Text "$detectedLanguage|$canonical"

        [pscustomobject]@{
            PSTypeName  = 'Lambek.Request'
            Original    = $Text
            Language    = $detectedLanguage
            Normalized  = $normalized
            Tokenizer   = $tokenization.Tokenizer
            Tokens      = $tokenization.Tokens
            Corrections = @($spelling.Corrections)
            Words       = $words
            Terms       = $terms
            CharNGrams  = $nGrams
            Entities    = $extraction.Entities
            Canonical   = $canonical
            Hash        = $hash
        }
    }
}
