function Measure-LambekEditDistance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Source,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Target
    )

    # Damerau-Levenshtein (optimal string alignment), in Native/Lambek.cs
    $distance = [LambekMeasure]::EditDistance($Source, $Target)

    # Result
    $longest = [math]::Max($Source.Length, $Target.Length)
    $similarity = 1.0
    if ($longest -gt 0) { $similarity = 1.0 - ($distance / $longest) }

    return [pscustomobject]@{
        Distance   = $distance
        Similarity = [double] $similarity
    }
}
