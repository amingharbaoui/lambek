function Get-LambekCharNGram {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Terms,

        [ValidateRange(2, 6)]
        [int] $Size = 3
    )

    $nGrams = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($term in $Terms) {
        # Entity tags stay whole
        if ($term -match '^_[a-z]+_$') {
            [void] $nGrams.Add($term)
            continue
        }

        # Padding and sliding window
        $padded = "#$term#"
        if ($padded.Length -le $Size) {
            [void] $nGrams.Add($padded)
            continue
        }

        for ($i = 0; $i -le $padded.Length - $Size; $i++) {
            [void] $nGrams.Add($padded.Substring($i, $Size))
        }
    }

    return [string[]] @($nGrams)
}
