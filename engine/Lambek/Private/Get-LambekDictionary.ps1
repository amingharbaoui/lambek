function Get-LambekDictionary {
    [CmdletBinding()]
    param(
        # The words of a language (en, fr); without it, only the links between meanings
        [string] $Language,

        # The definitions too, read only when someone asks what a word means
        [switch] $Glosses,

        # Start loading in the background and return at once
        [switch] $Background
    )

    # Asked for many times by every message: once loaded, the same answer is given at once
    $cacheKey = "$script:DictionaryPath|$Language|$([bool] $Glosses)"
    if (-not $Background -and $script:Dictionaries.ContainsKey($cacheKey)) { return $script:Dictionaries[$cacheKey] }

    # The files of the packs: the graph of meanings first, then the words of the language. Without them, the words as
    # Lambek learned them
    $names = [System.Collections.Generic.List[string]]::new()
    $names.Add('wordnet.dict.gz')
    if ($Language) { $names.Add("$Language.dict.gz") }
    if ($Glosses) { $names.Add('glosses.dict.gz') }
    $paths = foreach ($name in $names) {
        $path = Join-Path $script:DictionaryPath $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.Path]::GetFullPath($path) }
        elseif ($name -eq 'wordnet.dict.gz' -or $name -eq "$Language.dict.gz") {
            # Without the dictionaries, the words of the language as Lambek learned them (Native/Words.cs): what a
            # word may be and how it is said, without the meanings
            $learned = $null
            if ($Language -and -not $Background) {
                $model = Get-LambekFormModel -Language $Language
                if ($model) { $learned = [LambekLearnedWords]::new($model, $Language) }
            }
            if (-not $Background) { $script:Dictionaries[$cacheKey] = $learned }
            return $learned
        }
    }

    if ($Background) {
        [void] [LambekDictionary]::Begin([string[]] @($paths))
        return
    }

    $dictionary = [LambekDictionary]::Shared
    try {
        foreach ($path in $paths) { [void] $dictionary.Ensure($path) }
    }
    catch {
        Write-Warning "The dictionary could not be read: $($_.Exception.Message)"
        return $null
    }
    if ($Language -and -not $dictionary.Languages.Contains($Language)) { $dictionary = $null }
    $script:Dictionaries[$cacheKey] = $dictionary
    return $dictionary
}
