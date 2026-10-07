function Clear-LambekTrash {
    <#
    .SYNOPSIS
        Empties Lambek's trash: the deletions older than the number of days kept, or all of them.
    .EXAMPLE
        Clear-LambekTrash -All
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [ValidateRange(0, 3650)]
        [int] $OlderThanDays = $script:TrashDays,

        [switch] $All
    )

    if (-not (Test-Path -LiteralPath $script:TrashPath -PathType Container)) { return }

    # Each deletion is a folder named by its time: yyyyMMdd-HHmmss
    $limit = [datetime]::Now.AddDays(-$OlderThanDays)
    foreach ($batch in Get-ChildItem -LiteralPath $script:TrashPath -Directory) {
        $when = [datetime]::MinValue
        $isBatch = [datetime]::TryParseExact($batch.Name, 'yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture, 'None', [ref] $when)
        if (-not $isBatch -or (-not $All -and $when -ge $limit)) { continue }
        if ($PSCmdlet.ShouldProcess($batch.FullName, 'Delete for good')) {
            Remove-Item -LiteralPath $batch.FullName -Recurse -Force
        }
    }
}
