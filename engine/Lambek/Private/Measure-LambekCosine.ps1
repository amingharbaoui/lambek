function Measure-LambekCosine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $VectorA,

        [Parameter(Mandatory)]
        [hashtable] $VectorB
    )

    # Dot product
    $dot = 0.0
    foreach ($term in $VectorA.Keys) {
        if ($VectorB.ContainsKey($term)) {
            $dot += $VectorA[$term] * $VectorB[$term]
        }
    }

    # Norms
    $sumA = 0.0
    foreach ($weight in $VectorA.Values) { $sumA += $weight * $weight }

    $sumB = 0.0
    foreach ($weight in $VectorB.Values) { $sumB += $weight * $weight }

    $normA = [math]::Sqrt($sumA)
    $normB = [math]::Sqrt($sumB)

    if ($normA -eq 0 -or $normB -eq 0) {
        return 0.0
    }

    return [double] ($dot / ($normA * $normB))
}
