function Get-LambekEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # Units
    $sizeUnits = @{
        'b' = 1L; 'byte' = 1L; 'bytes' = 1L; 'octet' = 1L; 'octets' = 1L
        'kb' = 1KB; 'ko' = 1KB
        'mb' = 1MB; 'mo' = 1MB
        'gb' = 1GB; 'go' = 1GB; 'giga' = 1GB; 'gigas' = 1GB
        'tb' = 1TB
    }

    $daysPerUnit = @{
        'day' = 1; 'days' = 1; 'jour' = 1; 'jours' = 1
        'week' = 7; 'weeks' = 7; 'semaine' = 7; 'semaines' = 7
        'month' = 30; 'months' = 30; 'mois' = 30
        'year' = 365; 'years' = 365; 'an' = 365; 'ans' = 365; 'annee' = 365; 'annees' = 365
    }
    $hourUnits = @('hour', 'hours', 'heure', 'heures')
    $minuteUnits = @('minute', 'minutes', 'min')

    # Rules (order matters)
    $rules = @(
        @{ Type = 'quoted'; Pattern = '"(?<v>[^"]+)"|\u00AB\s*(?<v>[^\u00BB]+?)\s*\u00BB|\u201C(?<v>[^\u201D]+)\u201D' }
        @{ Type = 'path'; Pattern = '(?<v>(?:[A-Za-z]:\\|\\\\)[^\s,;"]*|%[A-Za-z_]+%(?:\\[^\s,;"]*)?|\$env:[A-Za-z_]+(?:\\[^\s,;"]*)?)' }
        @{ Type = 'size'; Pattern = '(?i)\b(?<n>\d+(?:[.,]\d+)?)\s?(?<u>bytes?|octets?|gigas?|[kmgt]b|[kmg]o|b)\b' }
        @{ Type = 'duration'; Pattern = '(?i)\b(?<n>\d+)\s?(?<u>days?|jours?|weeks?|semaines?|months?|mois|years?|ann[e\u00E9]es?|ans?|hours?|heures?|minutes?|min)\b' }
        @{ Type = 'extension'; Pattern = '(?i)(?<![\w\\])\.(?<v>[a-z0-9]{1,5})\b' }
        @{ Type = 'number'; Pattern = '(?<![\w.])(?<v>\d+(?:[.,]\d+)?)(?![\w.])' }
    )

    $entities = [System.Collections.Generic.List[object]]::new()
    $remainder = $Text

    # Extraction
    foreach ($rule in $rules) {
        $found = [regex]::Matches($remainder, $rule.Pattern)

        for ($i = $found.Count - 1; $i -ge 0; $i--) {
            $match = $found[$i]
            $value = $null

            switch ($rule.Type) {
                'size' {
                    $number = ConvertTo-LambekNumber -Text $match.Groups['n'].Value
                    $unit = ConvertTo-LambekNormalizedText -Text $match.Groups['u'].Value
                    $value = [long] [math]::Round($number * $sizeUnits[$unit])
                }
                'duration' {
                    $number = [int] $match.Groups['n'].Value
                    $unit = ConvertTo-LambekNormalizedText -Text $match.Groups['u'].Value

                    if ($daysPerUnit.ContainsKey($unit)) {
                        $value = [timespan]::FromDays($number * $daysPerUnit[$unit])
                    }
                    elseif ($hourUnits -contains $unit) {
                        $value = [timespan]::FromHours($number)
                    }
                    elseif ($minuteUnits -contains $unit) {
                        $value = [timespan]::FromMinutes($number)
                    }
                }
                'number' {
                    $value = ConvertTo-LambekNumber -Text $match.Groups['v'].Value
                }
                'extension' {
                    $value = '.' + $match.Groups['v'].Value.ToLowerInvariant()
                }
                default {
                    $value = $match.Groups['v'].Value
                }
            }

            $entity = [pscustomobject]@{
                Type  = $rule.Type
                Raw   = $match.Value
                Value = $value
            }
            $entities.Insert(0, $entity)

            $tag = " _$($rule.Type)_ "
            $remainder = $remainder.Remove($match.Index, $match.Length).Insert($match.Index, $tag)
        }
    }

    # Result
    return [pscustomobject]@{
        Entities  = $entities.ToArray()
        Remainder = ($remainder -replace '\s+', ' ').Trim()
    }
}

function ConvertTo-LambekNumber {
    param([string] $Text)

    $clean = $Text -replace ',', '.'
    return [double]::Parse($clean, [cultureinfo]::InvariantCulture)
}
