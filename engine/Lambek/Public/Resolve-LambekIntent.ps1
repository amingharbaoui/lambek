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
        [pscustomobject] $Request,

        # The parameters of the step before, for a pronoun
        [System.Collections.IDictionary] $Referent
    )

    process {
        $evidence = Get-LambekIntentEvidence -Request $Request
        $scoring = Get-LambekScoring
        New-LambekIntentCard -Evidence $evidence -Scoring $scoring -Adapted (Get-LambekAdaptedScoring -Scoring $scoring) -Referent $Referent
    }
}
