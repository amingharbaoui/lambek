function Format-LambekHumanValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [hashtable] $Units
    )

    # Durations: years, weeks, days, hours, or minutes
    if ($Value -is [timespan]) {
        $seconds = [long] $Value.TotalSeconds
        foreach ($unit in @(@('year', 31536000), @('week', 604800), @('day', 86400), @('hour', 3600), @('minute', 60))) {
            if ($seconds -ge $unit[1] -and $seconds % $unit[1] -eq 0) {
                $count = $seconds / $unit[1]
                $word = $Units[$unit[0]][1]
                if ($count -eq 1) { $word = $Units[$unit[0]][0] }
                return "$count $word"
            }
        }
        return "$seconds s"
    }

    # Sizes: the largest unit with at most one decimal
    if ($Name -match 'Size$' -and ($Value -is [long] -or $Value -is [int] -or $Value -is [double])) {
        $bytes = [double] $Value
        foreach ($unit in @(@('TB', 1TB), @('GB', 1GB), @('MB', 1MB), @('KB', 1KB))) {
            if ($bytes -ge $unit[1]) {
                $amount = [math]::Round($bytes / $unit[1], 1)
                return "$($amount.ToString([cultureinfo]::InvariantCulture)) $($Units[$unit[0]])"
            }
        }
        return "$bytes $($Units['B'])"
    }

    # Known words (folder, file...)
    if ($Value -is [string] -and $Units.ContainsKey($Value)) {
        return $Units[$Value]
    }

    return [string] $Value
}
