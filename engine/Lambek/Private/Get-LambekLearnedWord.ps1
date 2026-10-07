function Get-LambekLearnedWord {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # Words taught by the user, by language: { "fr": { "purge": "supprimer" } }, read once
    if ($null -ne $script:LearnedWords) { return $script:LearnedWords }

    $words = @{}
    if (Test-Path -LiteralPath $script:LearnedPath -PathType Leaf) {
        try {
            $data = Get-Content -LiteralPath $script:LearnedPath -Raw | ConvertFrom-Json -AsHashtable
            foreach ($language in $data.Keys) {
                $words[$language] = @{}
                foreach ($word in $data[$language].Keys) { $words[$language][$word] = [string] $data[$language][$word] }
            }
        }
        catch {
            Write-Warning "The learned words in $script:LearnedPath could not be read: $($_.Exception.Message)"
        }
    }
    $script:LearnedWords = $words
    return $words
}
