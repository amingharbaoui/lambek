function ConvertTo-LambekScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Template,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Parameters
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $Template) {
        $text = $line

        # ?Name: keep only when Name is set, !Name: only when it is not (several conditions allowed)
        $keep = $true
        while ($text -match '^(?<sign>[?!])(?<name>[A-Za-z]+) (?<rest>.*)$') {
            $isSet = $Parameters.Contains($Matches['name'])
            if ($Matches['sign'] -eq '?' -and -not $isSet) { $keep = $false }
            if ($Matches['sign'] -eq '!' -and $isSet) { $keep = $false }
            $text = $Matches['rest']
        }
        if (-not $keep) { continue }

        # {{Name!}}: raw identifier, {{Name}}: escaped literal
        foreach ($placeholder in [regex]::Matches($text, '\{\{(?<name>[A-Za-z]+)(?<raw>!?)\}\}')) {
            $name = $placeholder.Groups['name'].Value
            if (-not $Parameters.Contains($name)) {
                throw "The template needs the parameter '$name'."
            }

            $value = $Parameters[$name]
            if ($placeholder.Groups['raw'].Value -eq '!') {
                if ([string] $value -notmatch '^[A-Za-z_][A-Za-z0-9_-]*$') {
                    throw "'$value' is not a valid name."
                }
                $replacement = [string] $value
            }
            else {
                $replacement = ConvertTo-LambekLiteral -Value $value
            }

            $text = $text.Replace($placeholder.Value, $replacement)
        }

        $lines.Add($text)
    }

    return ($lines -join [Environment]::NewLine)
}
