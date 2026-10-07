function Read-LambekRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Original,

        [string] $Language = 'auto'
    )

    # Entities
    $extraction = Get-LambekEntity -Text $Text

    # Normalization and tokens
    $normalized = ConvertTo-LambekNormalizedText -Text $extraction.Remainder
    $tokenization = Get-LambekToken -Text $normalized

    # Language
    $detectedLanguage = $Language
    if ($Language -eq 'auto') {
        $detectedLanguage = Get-LambekLanguage -Tokens $tokenization.Tokens
    }

    # Words of other languages inside the sentence, read in their own language
    $borrowed = Get-LambekBorrowedWord -Tokens $tokenization.Tokens -Language $detectedLanguage

    # Words, terms, and n-grams
    $words = @(ConvertTo-LambekBaseForm -Tokens $tokenization.Tokens -Language $detectedLanguage -Borrowed $borrowed)
    $origins = [ordered]@{}
    for ($i = 0; $i -lt $tokenization.Tokens.Count; $i++) {
        if ($borrowed.Contains($tokenization.Tokens[$i])) { $origins[$words[$i]] = $borrowed[$tokenization.Tokens[$i]] }
    }
    $terms = @(Select-LambekTerm -Words $words -Language $detectedLanguage)
    $nGrams = @(Get-LambekCharNGram -Terms $terms)

    # Hash
    $canonical = $terms -join ' '
    $hash = Get-LambekHash -Text "$detectedLanguage|$canonical"

    [pscustomobject]@{
        PSTypeName  = 'Lambek.Request'
        Original    = $Original
        Language    = $detectedLanguage
        Borrowed    = $origins
        Normalized  = $normalized
        Tokenizer   = $tokenization.Tokenizer
        Tokens      = $tokenization.Tokens
        Corrections = @()
        Words       = $words
        Terms       = $terms
        CharNGrams  = $nGrams
        Entities    = $extraction.Entities
        Canonical   = $canonical
        Hash        = $hash
    }
}
