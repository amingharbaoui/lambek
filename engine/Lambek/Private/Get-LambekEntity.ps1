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
                default {
                    $value = $match.Groups['v'].Value
                }
            }

            $entity = [pscustomobject]@{
                Type  = $rule.Name
                Raw   = $match.Value
                Value = $value
            }
            $entities.Insert(0, $entity)

            # Replace with a tag
            $tag = " _$($rule.Name)_ "
            $remainder = $remainder.Remove($match.Index, $match.Length).Insert($match.Index, $tag)
        }
    }

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
