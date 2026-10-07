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

    # Edit similarity (best match per term, then average), word and n-gram Jaccard, TF-IDF cosine, in Native/Lambek.cs
    $scores = [LambekMeasure]::Similarity($Terms, $NGrams, $ReferenceTerms, $ReferenceNGrams, $Model.Idf, $Model.UnknownIdf)

    return [pscustomobject]@{
        EditSimilarity = $scores[0]
        WordJaccard    = $scores[1]
        NGramJaccard   = $scores[2]
        Cosine         = $scores[3]
    }
}
