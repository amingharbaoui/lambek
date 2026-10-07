function Get-LambekMemory {
    <#
    .SYNOPSIS
        Shows the requests Lambek remembers: the closest to a text, or the most active ones, and the proof of what it holds.
    .EXAMPLE
        Get-LambekMemory -Text 'supprime les fichiers temporaires'
    .EXAMPLE
        Get-LambekMemory -Integrity
    #>
    [CmdletBinding(DefaultParameterSetName = 'Recall')]
    param(
        [Parameter(ParameterSetName = 'Recall', Position = 0)]
        [AllowEmptyString()]
        [string] $Text = '',

        [Parameter(ParameterSetName = 'Recall')]
        [ValidateRange(1, 100)]
        [int] $First = 10,

        # How many requests it holds, and the Merkle root that changes when any of them changes
        [Parameter(Mandatory, ParameterSetName = 'Integrity')]
        [switch] $Integrity
    )

    $memory = Get-LambekMemoryStore
    if ($Integrity) {
        $pursuit = Get-LambekPursuitStore
        return [pscustomobject]@{
            Requests      = $memory.Count
            Uses          = [int] ($memory.Items | ForEach-Object { $_.Uses.Count } | Measure-Object -Sum).Sum
            Root          = $memory.Root()
            UnreadLines   = $memory.Broken
            WordsTried    = $pursuit.Words.Count
            Path          = $script:MemoryPath
        }
    }
    Find-LambekMemory -Text $Text -First $First -Memory $memory
}
