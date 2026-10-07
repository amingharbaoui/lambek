function Get-LambekCodeHeader {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Model,

        # How the program is told to really do it: --apply, or -Apply in PowerShell
        [Parameter(Mandatory)]
        [string] $Switch,

        # What the program needs to run, said in one line
        [Parameter(Mandatory)]
        [string] $Needs,

        # One more line for what this language cannot do like the others
        [string[]] $Remark = @()
    )

    # The lines of the comment at the top of every program, without the comment sign
    $need = Get-LambekCodeNeed -Model $Model
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Written by Lambek from this request:')
    $lines.Add('  ' + (ConvertTo-LambekCodeComment -Text $Model.Original))
    foreach ($step in $Model.Steps) {
        $lines.Add("Step $($step.Step): " + (ConvertTo-LambekCodeComment -Text $step.Sentence))
    }
    $lines.Add('')
    if ($need.Changes) {
        $lines.Add("Dry run by default: it only prints what it would do. Add $Switch to really do it.")
        if ($need.Delete) { $lines.Add("With $Switch a deleted file is really deleted: no trash, no undo.") }
        if ($Model.Steps.Count -gt 1) { $lines.Add('In a dry run each step sees the disk as it is now, not as the steps before would leave it.') }
    }
    else {
        $lines.Add('It only reads: nothing is changed.')
    }
    if ($need.Select) { $lines.Add('Hidden files and folders are skipped, and a link to a folder is not followed.') }
    foreach ($line in $Remark) { $lines.Add($line) }
    $lines.Add($Needs)
    return $lines.ToArray()
}

function Get-LambekCodeNeed {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    # Which parts of the program the steps use, so a program only holds the functions it calls
    $operations = @($Model.Steps | ForEach-Object { $_.Operation })
    $need = @{
        List   = $operations -contains 'list'
        Delete = $operations -contains 'delete'
        Copy   = $operations -contains 'copy'
        Move   = $operations -contains 'move'
        Rename = $operations -contains 'rename'
        Create = $operations -contains 'create'
    }
    $need.Transfer = $need.Copy -or $need.Move
    $need.Select = $need.List -or $need.Delete -or $need.Transfer
    $need.Changes = $need.Delete -or $need.Transfer -or $need.Rename -or $need.Create
    return $need
}
