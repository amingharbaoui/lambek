function Resolve-LambekIntent {
    <#
    .SYNOPSIS
        Finds the action a request asks for and builds its Intent Card.
    .EXAMPLE
        ConvertTo-LambekRequest 'delete the .log files in C:\Temp' | Resolve-LambekIntent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Lambek.Request')]
        [pscustomobject] $Request
    )

    process {
        $evidence = Get-LambekIntentEvidence -Request $Request
        New-LambekIntentCard -Evidence $evidence -Scoring (Get-LambekScoring)
    }
}
