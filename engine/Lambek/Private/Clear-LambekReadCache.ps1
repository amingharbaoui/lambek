function Clear-LambekReadCache {
    # What a message read is kept until the next message (the same sentence is read several times while it is
    # understood); a pack imported or a word learned changes how sentences read, so it forgets them too
    [CmdletBinding()]
    param()

    $script:ReadCache.Clear()
}

function Get-LambekReadCopy {
    # A reading kept for this message, as a copy its caller may add to (Corrections, Grammar); nothing when not kept
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Key
    )

    $kept = $null
    if (-not $script:ReadCache.TryGetValue($Key, [ref] $kept)) { return $null }
    return $kept.PSObject.Copy()
}
