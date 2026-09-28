function ConvertTo-LambekSentence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Template,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Parameters,

        [Parameter(Mandatory)]
        [hashtable] $Units
    )

    $parts = [System.Collections.Generic.List[string]]::new()

    foreach ($fragment in $Template) {
        $text = $fragment

        # ?Name: keep only when Name is set, !Name: only when it is not (several conditions allowed)
        $keep = $true
        while ($text -match '^(?<sign>[?!])(?<name>[A-Za-z]+) (?<rest>.*)$') {
            $isSet = $Parameters.Contains($Matches['name'])
            if ($Matches['sign'] -eq '?' -and -not $isSet) { $keep = $false }
            if ($Matches['sign'] -eq '!' -and $isSet) { $keep = $false }
            $text = $Matches['rest']
        }
        if (-not $keep) { continue }

        # {Name} or {Name|lower}
        foreach ($placeholder in [regex]::Matches($text, '\{(?<name>[A-Za-z]+)(?<lower>\|lower)?\}')) {
            $name = $placeholder.Groups['name'].Value
            $value = ''
            if ($Parameters.Contains($name)) {
                $value = Format-LambekHumanValue -Name $name -Value $Parameters[$name] -Units $Units
            }
            if ($placeholder.Groups['lower'].Success) {
                $value = $value.ToLowerInvariant()
            }
            $text = $text.Replace($placeholder.Value, $value)
        }

        $parts.Add($text)
    }

    return (($parts -join ' ') -replace '\s+', ' ' -replace ' ,', ',').Trim()
}
