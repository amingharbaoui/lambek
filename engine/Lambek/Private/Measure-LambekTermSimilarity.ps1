function Measure-LambekTermSimilarity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Terms,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $NGrams,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $ReferenceTerms,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $ReferenceNGrams,

        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    # Edit similarity (best match per term, then average)
    $editTotal = 0.0
    foreach ($term in $Terms) {
        $best = 0.0
        foreach ($candidate in $ReferenceTerms) {
            $score = (Measure-LambekEditDistance -Source $term -Target $candidate).Similarity
            if ($score -gt $best) { $best = $score }
        }
        $editTotal += $best
    }

    $editSimilarity = 0.0
    if ($Terms.Count -gt 0) {
        $editSimilarity = $editTotal / $Terms.Count
    }

    # Jaccard
    $wordJaccard = Measure-LambekJaccard -SetA $Terms -SetB $ReferenceTerms
    $nGramJaccard = Measure-LambekJaccard -SetA $NGrams -SetB $ReferenceNGrams

    # TF-IDF cosine
    $vectorA = ConvertTo-LambekTfIdfVector -Terms $Terms -Model $Model
    $vectorB = ConvertTo-LambekTfIdfVector -Terms $ReferenceTerms -Model $Model
    $cosine = Measure-LambekCosine -VectorA $vectorA -VectorB $vectorB

    return [pscustomobject]@{
        EditSimilarity = $editSimilarity
        WordJaccard    = $wordJaccard
        NGramJaccard   = $nGramJaccard
        Cosine         = $cosine
    }
}
