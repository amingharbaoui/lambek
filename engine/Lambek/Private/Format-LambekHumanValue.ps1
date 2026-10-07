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

    # Lists: ".log, .tmp and .bak"
    if ($Value -is [array]) {
        $items = @($Value | ForEach-Object { Format-LambekHumanValue -Name $Name -Value $_ -Units $Units })
        if ($items.Count -le 1) { return "$items" }
        $and = 'and'
        if ($Units.ContainsKey('and')) { $and = $Units['and'] }
        return ($items[0..($items.Count - 2)] -join ', ') + " $and " + $items[-1]
    }

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
                $text = $amount.ToString([cultureinfo]::InvariantCulture)
                if ($Units.ContainsKey('Decimal')) { $text = $text.Replace('.', $Units['Decimal']) }
                return "$text $($Units[$unit[0]])"
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
