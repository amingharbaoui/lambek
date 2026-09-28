function Get-LambekEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $entities = [System.Collections.Generic.List[object]]::new()
    $remainder = $Text

    foreach ($rule in Get-LambekEntityRule) {
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
                'path' {
                    $value = Expand-LambekPath -Text $match.Groups['v'].Value
                }
                default {
                    $value = $match.Groups['v'].Value
                }
            }

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

    # Folder names like Desktop or Documents become the folder of the user
    $known = @{
        desktop = 'Desktop'; bureau = 'Desktop'
        documents = 'MyDocuments'
        pictures = 'MyPictures'; images = 'MyPictures'
        music = 'MyMusic'; musique = 'MyMusic'
        videos = 'MyVideos'
    }
    $name = ConvertTo-LambekNormalizedText -Text $path
    if ($known.ContainsKey($name)) {
        $folder = [Environment]::GetFolderPath($known[$name])
        if (-not $folder) { $folder = Join-Path $userFolder $known[$name].Replace('My', '') }
        return $folder
    }
    if ($name -in 'downloads', 'telechargements') {
        return Join-Path $userFolder 'Downloads'
    }
    return $path
}
