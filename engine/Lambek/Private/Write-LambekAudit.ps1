function Write-LambekAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateSet('Simulated', 'Approved', 'Refused', 'StepCompleted', 'StepFailed', 'Completed', 'Failed')]
        [string] $EventName,

        [string] $PlanHash = '',

        [int] $Step = 0,

        [string] $Action = '',

        [string] $Detail = ''
    )

    # Folder
    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    # Hash of the previous entry
    $previousHash = ''
    if (Test-Path -LiteralPath $Path) {
        $lastLine = Get-Content -LiteralPath $Path -Tail 1
        if ($lastLine) {
            $previousHash = ($lastLine | ConvertFrom-Json).Hash
        }
    }

    # Entry chained to the previous one
    $entry = [ordered]@{
        Time         = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss.fff') + ' UTC'
        Event        = $EventName
        PlanHash     = $PlanHash
        Step         = $Step
        Action       = $Action
        Detail       = $Detail
        User         = [Environment]::UserName
        Machine      = [Environment]::MachineName
        PreviousHash = $previousHash
    }
    $entry.Hash = Get-LambekHash -Text ($entry | ConvertTo-Json -Compress)

    Add-Content -LiteralPath $Path -Value ($entry | ConvertTo-Json -Compress)
}
