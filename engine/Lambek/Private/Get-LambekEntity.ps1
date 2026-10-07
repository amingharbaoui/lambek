function Get-LambekEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $entities = [System.Collections.Generic.List[object]]::new()
    $remainder = $Text

    $numbersRead = $false
    $language = $null
    foreach ($rule in Get-LambekEntityRule) {
        # The rules of a language file only read a sentence of that language
        if ($rule.ContainsKey('Language')) {
            if ($null -eq $language) { $language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) }
            if ($rule['Language'] -ne $language) { continue }
        }
        # Numbers said in words ("deux jours", "three GB") are numbers for every rule that reads quantities
        if (-not $numbersRead -and $rule.Priority -ge 50) {
            $remainder = ConvertTo-LambekDigit -Text $remainder
            $numbersRead = $true
        }
        $found = [regex]::Matches($remainder, $rule.Pattern)

        for ($i = $found.Count - 1; $i -ge 0; $i--) {
            $match = $found[$i]

            # Value
            switch ($rule.Kind) {
                'number' {
                    $value = ConvertTo-LambekNumber -Text $match.Groups['v'].Value
                }
                'unit' {
                    $number = ConvertTo-LambekNumber -Text $match.Groups['n'].Value
                    $unit = ConvertTo-LambekNormalizedText -Text $match.Groups['u'].Value
                    $value = [long] [math]::Round($number * $rule.Units[$unit])
                }
                'duration' {
                    $number = ConvertTo-LambekNumber -Text $match.Groups['n'].Value
                    $unit = ConvertTo-LambekNormalizedText -Text $match.Groups['u'].Value
                    $value = [timespan]::FromSeconds($number * $rule.Units[$unit])
                }
                'lower' {
                    $value = $match.Groups['v'].Value.ToLowerInvariant()
                }
                'extension' {
                    # "pdf files", "les pdf": a word the machine knows as a file extension, and no word of the languages
                    $word = $match.Groups['v'].Value.ToLowerInvariant()
                    $value = ".$word"
                    if (-not (Test-LambekKnownExtension -Extension $value) -or (Test-LambekLanguageWord -Word $word)) { $value = $null }
                }
                'order' {
                    # "most recent", "plus recents": one of the orders the pack names (newest, oldest, largest...)
                    $said = (ConvertTo-LambekNormalizedText -Text $match.Groups['v'].Value) -replace '\s+', ' '
                    $value = $rule.Orders[$said]
                }
                'path' {
                    # A question mark or an exclamation mark after the path ends the sentence, not the path
                    $value = Expand-LambekPath -Text ($match.Groups['v'].Value -replace '(?<=.)[?!]+$', '')
                }
                default {
                    $value = $match.Groups['v'].Value
                }
            }

            # A match the rule turns down stays as text
            if ($null -eq $value) { continue }

            $entity = [pscustomobject]@{
                Type  = $rule.Name
                Raw   = $match.Value
                Value = $value
            }
            $entities.Add($entity)

            # Replace with a numbered mark first, so entities can be put back in text order
            $mark = " `u{1}$([char] (0xE000 + $entities.Count - 1))`u{1} "
            $remainder = $remainder.Remove($match.Index, $match.Length).Insert($match.Index, $mark)
        }
    }

    # Entities in the order they appear, then marks become tags like _path_
    $ordered = [System.Collections.Generic.List[object]]::new()
    foreach ($found in [regex]::Matches($remainder, "`u{1}(.)`u{1}")) {
        $ordered.Add($entities[[int] [char] $found.Groups[1].Value - 0xE000])
    }
    $remainder = [regex]::Replace($remainder, "`u{1}(.)`u{1}", {
            param($found)
            "_$($entities[[int] [char] $found.Groups[1].Value - 0xE000].Type)_"
        })

    return [pscustomobject]@{
        Entities  = $ordered.ToArray()
        Remainder = ($remainder -replace '\s+', ' ').Trim()
    }
}

function ConvertTo-LambekDigit {
    param([string] $Text)

    # The number words of every language, longest first ("dix-sept" before "dix")
    if (-not $script:NumberWords) {
        $words = @{}
        foreach ($language in Get-LambekAvailableLanguage) {
            $numbers = (Get-LambekLexicon -Language $language).Numbers
            if ($numbers) { foreach ($name in $numbers.Keys) { $words[$name] = [string] $numbers[$name] } }
        }
        $pattern = (@($words.Keys | Sort-Object @{ Expression = { $_.Length }; Descending = $true }, { $_ } | ForEach-Object { [regex]::Escape($_) }) -join '|')
        $script:NumberWords = [pscustomobject]@{ Values = $words; Pattern = "(?i)(?<![\p{L}\p{N}_\\/.-])($pattern)(?![\p{L}\p{N}_\\/.-])" }
    }
    if ($script:NumberWords.Values.Count -eq 0) { return $Text }
    return [regex]::Replace($Text, $script:NumberWords.Pattern, { param($match) $script:NumberWords.Values[$match.Value.ToLowerInvariant()] })
}

function ConvertTo-LambekNumber {
    param([string] $Text)

    $clean = $Text -replace ',', '.'
    return [double]::Parse($clean, [cultureinfo]::InvariantCulture)
}

function Expand-LambekPath {
    param([string] $Text)

    # %NAME%, $env:NAME, $HOME, and ~ become the real folder
    $userFolder = [Environment]::GetFolderPath('UserProfile')
    $path = [regex]::Replace($Text, '%(?<n>[A-Za-z_]+)%|\$env:(?<n>[A-Za-z_]+)', {
            param($found)
            $value = [Environment]::GetEnvironmentVariable($found.Groups['n'].Value)
            if ($value) { $value } else { $found.Value }
        })
    if ($path -match '^(\$HOME|~)(?=$|[\\/])') {
        $path = $userFolder + $path.Substring($Matches[1].Length)
    }
    # A drive written with forward slashes (C:/Temp) is the same folder as C:\Temp
    if ($path -match '^[A-Za-z]:/') { $path = $path.Replace('/', '\') }

    # Folder names like Desktop or Documents become the folder of the user
    $name = (ConvertTo-LambekNormalizedText -Text $path) -replace '\s+', ' '
    $known = Get-LambekKnownFolder
    if ($known.ContainsKey($name)) {
        $special = $known[$name]
        if ($special -eq 'Downloads') { return Join-Path $userFolder 'Downloads' }
        $folder = [Environment]::GetFolderPath($special, [Environment+SpecialFolderOption]::DoNotVerify)
        if (-not $folder) { $folder = Join-Path $userFolder $special.Replace('My', '') }
        return $folder
    }
    return $path
}

function Test-LambekKnownExtension {
    param([string] $Extension)

    # Extensions of every kind the machine or the packs know
    $system = Get-LambekSystemVocabulary
    if (-not $script:KnownExtensions) {
        $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($list in $system.Kinds.Values) { $known.UnionWith([string[]] $list) }
        foreach ($pack in $script:Packs.Values) { foreach ($list in $pack.Kinds.Values) { $known.UnionWith([string[]] @($list)) } }
        $script:KnownExtensions = $known
    }
    return $script:KnownExtensions.Contains($Extension)
}

function Test-LambekLanguageWord {
    param([string] $Word)

    # "les", "old", "one" are file extensions somewhere, but first words of a sentence
    foreach ($language in Get-LambekAvailableLanguage) {
        $lexicon = Get-LambekLexicon -Language $language
        if ($lexicon.Signals.Contains($Word) -or $lexicon.Vocabulary.Contains($Word)) { return $true }
    }
    return $false
}
