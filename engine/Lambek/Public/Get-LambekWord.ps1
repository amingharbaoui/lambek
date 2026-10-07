function Get-LambekWord {
    <#
    .SYNOPSIS
        Lists the words Lambek learned, and what each one means.
    .EXAMPLE
        Get-LambekWord -Language fr
    #>
    [CmdletBinding()]
    param(
        [ValidatePattern('^[a-z]{2}$')]
        [string] $Language
    )

    $learned = Get-LambekLearnedWord
    foreach ($key in @($learned.Keys | Sort-Object)) {
        if ($Language -and $key -ne $Language) { continue }
        foreach ($word in @($learned[$key].Keys | Sort-Object)) {
            [pscustomobject]@{ Language = $key; Word = $word; Meaning = $learned[$key][$word] }
        }
    }
}
