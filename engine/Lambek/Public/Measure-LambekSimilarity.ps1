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

    # Edit similarity (best match per term, then average)
    $editTotal = 0.0
    foreach ($term in $Request.Terms) {
        $best = 0.0
        foreach ($candidate in $referenceRequest.Terms) {
            $score = (Measure-LambekEditDistance -Source $term -Target $candidate).Similarity
            if ($score -gt $best) { $best = $score }
        }
        $editTotal += $best
    }

    $editSimilarity = 0.0
    if ($Request.Terms.Count -gt 0) {
        $editSimilarity = $editTotal / $Request.Terms.Count
    }

    # Jaccard
    $wordJaccard = Measure-LambekJaccard -SetA $Request.Terms -SetB $referenceRequest.Terms
    $nGramJaccard = Measure-LambekJaccard -SetA $Request.CharNGrams -SetB $referenceRequest.CharNGrams

    # TF-IDF cosine
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
    $vectorA = ConvertTo-LambekTfIdfVector -Terms $Request.Terms -Model $model
    $vectorB = ConvertTo-LambekTfIdfVector -Terms $referenceRequest.Terms -Model $model
    $cosine = Measure-LambekCosine -VectorA $vectorA -VectorB $vectorB

    # Result
    [pscustomobject]@{
        Reference      = $Reference
        EditSimilarity = [math]::Round($editSimilarity, 4)
        WordJaccard    = [math]::Round($wordJaccard, 4)
        NGramJaccard   = [math]::Round($nGramJaccard, 4)
        Cosine         = [math]::Round($cosine, 4)
    }
}
