function Clear-LambekHistory {
    <#
    .SYNOPSIS
        Forgets the plans you ran: the weights go back to the default ones, the habits and the memory of your requests disappear.
    .EXAMPLE
        Clear-LambekHistory
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess($script:HistoryPath, 'Forget the plans run')) {
        # The adapter of the proposer goes too: without it the proposer is its base again, exactly
        $adapter = Join-Path (Split-Path -Path $script:MemoryPath -Parent) 'proposer-adapter.json'
        foreach ($path in $script:HistoryPath, $script:MemoryPath, $script:PursuitPath, $script:DriftPath, $adapter) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
        }
        $script:History = $null
        $script:Memory = $null
        $script:Pursuit = $null
        $script:Fusion = $null
    }
}
