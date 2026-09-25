function Test-LambekAudit {
    <#
    .SYNOPSIS
        Checks that no entry of the audit log was changed or removed.
    .EXAMPLE
        Test-LambekAudit -Path ./audit.jsonl
    #>
    [CmdletBinding()]
    param(
        [string] $Path = $script:AuditPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Audit log not found: $Path"
    }

    $previousHash = ''
    $number = 0
    $brokenAt = $null

    foreach ($line in Get-Content -LiteralPath $Path) {
        if (-not $line) { continue }
        $number++

        # Recompute the hash of the entry without its own hash
        $entry = $line | ConvertFrom-Json -AsHashtable
        $expected = [ordered]@{}
        foreach ($key in 'Time', 'Event', 'PlanHash', 'Step', 'Action', 'Detail', 'User', 'Machine', 'PreviousHash') {
            $expected[$key] = $entry[$key]
        }
        $hash = Get-LambekHash -Text ($expected | ConvertTo-Json -Compress)

        if ($entry.PreviousHash -ne $previousHash -or $entry.Hash -ne $hash) {
            $brokenAt = $number
            break
        }
        $previousHash = $entry.Hash
    }

    [pscustomobject]@{
        PSTypeName = 'Lambek.AuditCheck'
        IsValid    = $null -eq $brokenAt
        Entries    = $number
        BrokenAt   = $brokenAt
    }
}
