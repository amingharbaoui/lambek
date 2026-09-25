function Measure-LambekSimilarity {
    <#
    .SYNOPSIS
        Measures how close a request is to a reference phrase.
    .EXAMPLE
        Measure-LambekSimilarity -Request (ConvertTo-LambekRequest 'delet old fils') -Reference 'delete old files'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Lambek.Request')]
        [pscustomobject] $Request,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Reference,

        [string[]] $Corpus
    )

    $referenceRequest = ConvertTo-LambekRequest -Text $Reference -Language $Request.Language

    # TF-IDF model
    $documents = [System.Collections.Generic.List[object]]::new()
    if ($Corpus) {
        foreach ($phrase in $Corpus) {
            $documents.Add((ConvertTo-LambekRequest -Text $phrase -Language $Request.Language).Terms)
        }
    }
    else {
        $documents.Add($Request.Terms)
        $documents.Add($referenceRequest.Terms)
    }
    $model = ConvertTo-LambekTfIdfModel -Documents $documents.ToArray()

    # Scores
    $scores = Measure-LambekTermSimilarity -Terms $Request.Terms -NGrams $Request.CharNGrams `
        -ReferenceTerms $referenceRequest.Terms -ReferenceNGrams $referenceRequest.CharNGrams -Model $model

    [pscustomobject]@{
        Reference      = $Reference
        EditSimilarity = [math]::Round($scores.EditSimilarity, 4)
        WordJaccard    = [math]::Round($scores.WordJaccard, 4)
        NGramJaccard   = [math]::Round($scores.NGramJaccard, 4)
        Cosine         = [math]::Round($scores.Cosine, 4)
    }
}
