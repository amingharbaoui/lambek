function ConvertFrom-LambekInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Parameter,

        [Parameter(Mandatory)]
        [string] $Value
    )

    $text = $Value.Trim()
    if ($text.Length -eq 0) {
        throw "$($Parameter.Name) cannot be empty."
    }

    # Choices (Kind, Language...)
    if ($Parameter.ContainsKey('Words')) {
        $choices = @($Parameter.Words.Values | Select-Object -Unique)
        foreach ($choice in $choices) {
            if ($choice -eq $text) { return $choice }
        }
        throw "$($Parameter.Name) must be one of: $($choices -join ', ')."
    }

    $entities = @($Parameter.Entities)

    # Sizes: 5368709120 or 5 GB
    if ($entities -contains 'size') {
        if ($text -match '^\d+$') { return [long] $text }
        if ($text -match '^(?<n>\d+(?:[.,]\d+)?)\s*(?<u>B|KB|MB|GB|TB|Ko|Mo|Go|To)$') {
            $factor = @{ B = 1L; KB = 1KB; KO = 1KB; MB = 1MB; MO = 1MB; GB = 1GB; GO = 1GB; TB = 1TB; TO = 1TB }[$Matches['u'].ToUpperInvariant()]
            $number = [double]::Parse(($Matches['n'] -replace ',', '.'), [cultureinfo]::InvariantCulture)
            return [long] [math]::Round($number * $factor)
        }
        throw "$($Parameter.Name) must be a size, for example 5 GB."
    }

    # Durations: 2592000s or 30 days
    if ($entities -contains 'duration') {
        if ($text -match '^(?<n>\d+)s$') { return [timespan]::FromSeconds([double] $Matches['n']) }
        if ($text -match '^(?<n>\d+)\s*(?<u>minutes?|hours?|days?|weeks?|years?)$') {
            $seconds = @{ minute = 60; hour = 3600; day = 86400; week = 604800; year = 31536000 }[$Matches['u'].TrimEnd('s')]
            return [timespan]::FromSeconds([double] $Matches['n'] * $seconds)
        }
        throw "$($Parameter.Name) must be a duration, for example 30 days."
    }

    return $text
}
