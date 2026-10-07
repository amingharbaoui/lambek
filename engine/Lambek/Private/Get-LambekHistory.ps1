function Get-LambekHistory {
    [CmdletBinding()]
    param()

    # What happened to past plans, one JSON line each, read once per session
    if ($null -ne $script:History) { return , $script:History }
    $entries = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $script:HistoryPath -PathType Leaf) {
        foreach ($line in [IO.File]::ReadLines($script:HistoryPath)) {
            if (-not $line.Trim()) { continue }
            try { $entries.Add(($line | ConvertFrom-Json -AsHashtable)) }
            catch { Write-Verbose "A line of the history could not be read: $($_.Exception.Message)" }
        }
    }
    $script:History = $entries
    return , $entries
}

function Add-LambekHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Step,

        [ValidateSet('done')]
        [string] $Outcome = 'done'
    )

    # Nothing is kept from an incognito chat
    if ($script:Incognito) { return }

    $action = (Get-LambekAction -Id $Step.Action).Action
    $habits = [ordered]@{}
    foreach ($parameter in $action.Parameters) {
        if ($parameter['Habit'] -and $Step.Parameters.Contains($parameter.Name)) { $habits[$parameter.Name] = Format-LambekValue -Value $Step.Parameters[$parameter.Name] }
    }
    $votes = $null
    if ($Step.PSObject.Properties['Votes']) { $votes = $Step.Votes }

    $entry = [ordered]@{ Time = [datetime]::UtcNow.ToString('o'); Action = $Step.Action; Outcome = $Outcome; Votes = $votes; Habits = $habits }
    $folder = Split-Path -Path $script:HistoryPath -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
    Add-Content -LiteralPath $script:HistoryPath -Value ($entry | ConvertTo-Json -Compress -Depth 4)
    (Get-LambekHistory).Add(($entry | ConvertTo-Json -Depth 4 | ConvertFrom-Json -AsHashtable))
}

function Get-LambekMemoryWeight {
    param([string] $Time, [datetime] $Now)

    # Old habits fade: an entry counts half after 30 days, a quarter after 60
    $age = ($Now - [datetime]::Parse($Time, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).TotalDays
    return [math]::Pow(0.5, [math]::Max($age, 0) / 30)
}

function Get-LambekAdaptedScoring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Scoring,

        [datetime] $Now = [datetime]::UtcNow
    )

    # Each scorer earns trust when its vote agreed with a plan the user ran (Laplace: (agree + 1) / (all + 2)).
    # The new weights move from the default ones as evidence builds up: lambda = n / (n + 20)
    $agree = @{}
    $all = @{}
    $count = 0.0
    $entries = Get-LambekHistory
    foreach ($entry in $entries) {
        if ($entry.Outcome -ne 'done' -or -not $entry.Votes) { continue }
        $weight = Get-LambekMemoryWeight -Time $entry.Time -Now $Now
        $count += $weight
        foreach ($name in $entry.Votes.Keys) {
            $vote = [double] $entry.Votes[$name]
            if ($vote -eq 0) { continue }
            $all[$name] = $all[$name] + $weight
            if ($vote -gt 0) { $agree[$name] = $agree[$name] + $weight }
        }
    }
    if ($count -lt 1) { return $null }

    $trusted = [ordered]@{}
    $total = 0.0
    foreach ($name in $Scoring.Weights.Keys) {
        $trust = ($agree[$name] + 1) / ($all[$name] + 2)
        $trusted[$name] = $Scoring.Weights[$name] * $trust
        $total += $trusted[$name]
    }
    $lambda = $count / ($count + 20)
    $weights = [ordered]@{}
    foreach ($name in $Scoring.Weights.Keys) {
        $weights[$name] = [math]::Round((1 - $lambda) * $Scoring.Weights[$name] + $lambda * $trusted[$name] / $total, 4)
    }

    [pscustomobject]@{
        Weights     = $weights
        Threshold   = $Scoring.Threshold
        Margin      = $Scoring.Margin
        Margins     = $Scoring.Margins
        Correlation = $Scoring.Correlation
        Evidence    = [math]::Round($count, 2)
    }
}

function Get-LambekHabit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ActionId,

        [Parameter(Mandatory)]
        [string] $Name,

        [datetime] $Now = [datetime]::UtcNow
    )

    # A value becomes a habit after about three recent uses, and only when it clearly beats every other value
    $counts = @{}
    $entries = Get-LambekHistory
    foreach ($entry in $entries) {
        if ($entry.Action -ne $ActionId -or -not $entry.Habits -or -not $entry.Habits.Contains($Name)) { continue }
        $value = [string] $entry.Habits[$Name]
        $counts[$value] = $counts[$value] + (Get-LambekMemoryWeight -Time $entry.Time -Now $Now)
    }
    $ranked = @($counts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key' })
    if ($ranked.Count -eq 0 -or $ranked[0].Value -lt 2.5) { return $null }
    if ($ranked.Count -gt 1 -and $ranked[0].Value -lt 2 * $ranked[1].Value) { return $null }
    return $ranked[0].Key
}
