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

    # The files of the packs: the graph of meanings first, then the words of the language
    $names = [System.Collections.Generic.List[string]]::new()
    $names.Add('wordnet.dict.gz')
    if ($Language) { $names.Add("$Language.dict.gz") }
    if ($Glosses) { $names.Add('glosses.dict.gz') }
    $paths = foreach ($name in $names) {
        $path = Join-Path $script:DictionaryPath $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.Path]::GetFullPath($path) }
        elseif ($name -eq 'wordnet.dict.gz') { return $null }
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
    if ($Language -and -not $dictionary.Languages.Contains($Language)) { return $null }
    return $dictionary
}
