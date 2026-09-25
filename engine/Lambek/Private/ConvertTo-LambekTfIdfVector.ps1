function ConvertTo-LambekTfIdfVector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Terms,

        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    $vector = @{}
    if ($Terms.Count -eq 0) {
        return $vector
    }

    # Term frequency
    $counts = @{}
    foreach ($term in $Terms) {
        if ($counts.ContainsKey($term)) {
            $counts[$term]++
        }
        else {
            $counts[$term] = 1
        }
    }

    # Weight = tf * idf
    foreach ($term in $counts.Keys) {
        $tf = $counts[$term] / $Terms.Count
        $idf = $Model.UnknownIdf
        if ($Model.Idf.ContainsKey($term)) {
            $idf = $Model.Idf[$term]
        }
        $vector[$term] = $tf * $idf
    }

    return $vector
}
