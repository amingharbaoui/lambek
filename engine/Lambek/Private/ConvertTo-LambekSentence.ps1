function ConvertTo-LambekSentence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Template,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Parameters,

        [Parameter(Mandatory)]
        [hashtable] $Units,

        # Names and places between quotes, so the sentence reads back to the same values:
        # none, only those that need it (a space, a name that is not a path or a file), or all
        [ValidateSet('None', 'Needed', 'All')]
        [string] $Quote = 'None',

        # The parameters whose values are words of the pack, never quoted
        [string[]] $Plain = @()
    )

    $parts = [System.Collections.Generic.List[string]]::new()

    foreach ($fragment in $Template) {
        $text = $fragment

        # ?Name: keep only when Name is set, !Name: only when it is not, ?Name=value: only when Name is that value
        $keep = $true
        while ($text -match '^(?<sign>[?!])(?<name>[A-Za-z]+)(?:=(?<value>[\w.-]+))? (?<rest>.*)$') {
            $isSet = $Parameters.Contains($Matches['name'])
            if ($isSet -and $Matches['value']) { $isSet = [string] $Parameters[$Matches['name']] -eq $Matches['value'] }
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
                $raw = $Parameters[$name]
                if ($Quote -ne 'None' -and $name -notin $Plain) {
                    $all = $Quote -eq 'All'
                    if ($raw -is [array]) { $raw = @($raw | ForEach-Object { Add-LambekQuote -Value $_ -Units $Units -All:$all }) }
                    else { $raw = Add-LambekQuote -Value $raw -Units $Units -All:$all }
                }
                $value = Format-LambekHumanValue -Name $name -Value $raw -Units $Units
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

function Add-LambekQuote {
    param([object] $Value, [hashtable] $Units, [switch] $All)

    # Only text that is not a word of the language (an extension, a kind, "Directory") goes between quotes
    if ($Value -isnot [string] -or $Value.StartsWith('.') -or $Units.ContainsKey($Value)) { return $Value }
    # Unless all are asked: a path or a file name without a space reads back as it is
    $clean = $Value -notmatch '[\s;$`''"]'
    $path = $Value -match '^(?:[A-Za-z]:\\|\\\\|~?/|\.{1,2}[\\/])' -or $Value -match '^[\w-]+\.[A-Za-z][A-Za-z0-9]{0,4}$'
    if (-not $All -and $clean -and $path) { return $Value }
    $open = '"'
    $close = '"'
    if ($Units.ContainsKey('Quotes')) { $open = $Units['Quotes'][0]; $close = $Units['Quotes'][1] }
    return "$open$Value$close"
}
