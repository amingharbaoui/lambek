function ConvertTo-LambekTfIdfModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Documents
    )

    # Document frequency
    $documentFrequency = @{}
    foreach ($document in $Documents) {
        $uniqueTerms = @($document) | Select-Object -Unique
        foreach ($term in $uniqueTerms) {
            if ($documentFrequency.ContainsKey($term)) {
                $documentFrequency[$term]++
            }
            else {
                $documentFrequency[$term] = 1
            }
        }
    }

    # Smoothed IDF: ln((1 + N) / (1 + df)) + 1
    $n = $Documents.Count
    $idf = @{}
    foreach ($term in $documentFrequency.Keys) {
        $idf[$term] = [math]::Log((1 + $n) / (1 + $documentFrequency[$term])) + 1
    }

    return [pscustomobject]@{
        DocumentCount = $n
        Idf           = $idf
        UnknownIdf    = [math]::Log(1 + $n) + 1
    }
}
