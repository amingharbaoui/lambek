function Get-LambekKnownFolder {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $system = Get-LambekSystemVocabulary
    if ($script:KnownFolderCache) { return $script:KnownFolderCache }

    # Folder names of the packs ("bureau", "telechargements"), then every special folder of this machine
    $folders = @{}
    foreach ($pack in $script:Packs.Values) {
        foreach ($name in $pack.Folders.Keys) { $folders[$name] = $pack.Folders[$name] }
    }

    # A system name made of small words ("send to") would catch ordinary sentences: it stays out
    $small = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($language in Get-LambekAvailableLanguage) {
        $small.UnionWith((Get-LambekLexicon -Language $language).StopWords)
        foreach ($pack in $script:Packs.Values) {
            if (-not $pack.Words.ContainsKey($language)) { continue }
            foreach ($word in $pack.Words[$language].Keys) {
                if (@($pack.Words[$language][$word]) -match '\^') { [void] $small.Add($word) }
            }
        }
    }
    $system = $system.Folders
    foreach ($name in $system.Keys) {
        if ($folders.ContainsKey($name)) { continue }
        if (@($name -split ' ' | Where-Object { $small.Contains($_) }).Count -gt 0) { continue }
        $folders[$name] = $system[$name]
    }

    $script:KnownFolderCache = $folders
    return $folders
}

function Get-LambekFolderPattern {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Every known folder name as one regex, longest first, with or without accents
    return ConvertTo-LambekWordPattern -Names @((Get-LambekKnownFolder).Keys)
}

function Get-LambekKindPattern {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Every word the packs give a kind of file ("photo", "musique", "picture"), singular or plural
    $names = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            foreach ($parameter in $action.Parameters) {
                if ($parameter.ContainsKey('Expand') -and $parameter.ContainsKey('Words')) { $names.UnionWith([string[]] @($parameter.Words.Keys)) }
            }
        }
    }
    if ($names.Count -eq 0) { return '(?!)' }
    return "(?:$(ConvertTo-LambekWordPattern -Names @($names)))s?"
}

function Get-LambekAccentClass {
    # Each letter with the accents it takes in the languages Lambek reads (French, Spanish, Portuguese, Italian, German, Dutch)
    return @{
        a = '[a\u00e0\u00e1\u00e2\u00e3\u00e4]'; e = '[e\u00e8\u00e9\u00ea\u00eb]'; i = '[i\u00ec\u00ed\u00ee\u00ef]'
        o = '[o\u00f2\u00f3\u00f4\u00f5\u00f6]'; u = '[u\u00f9\u00fa\u00fb\u00fc]'; c = '[c\u00e7]'; n = '[n\u00f1]'
    }
}

function ConvertTo-LambekWordPattern {
    param([string[]] $Names)

    # Longest first, each letter with or without its accents: "telechargements" also reads with its accents
    $accents = Get-LambekAccentClass
    $sorted = @($Names | Sort-Object @{ Expression = { $_.Length }; Descending = $true }, { $_ })
    $parts = foreach ($name in $sorted) {
        $builder = [System.Text.StringBuilder]::new()
        foreach ($character in $name.ToCharArray()) {
            $letter = [string] $character
            if ($letter -eq ' ') { [void] $builder.Append('\s+') }
            elseif ($accents.ContainsKey($letter)) { [void] $builder.Append($accents[$letter]) }
            else { [void] $builder.Append([regex]::Escape($letter)) }
        }
        $builder.ToString()
    }
    return ($parts -join '|')
}
