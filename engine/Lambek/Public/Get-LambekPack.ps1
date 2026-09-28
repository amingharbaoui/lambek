function Get-LambekPack {
    <#
    .SYNOPSIS
        Lists the DSL packs loaded in Lambek.
    .EXAMPLE
        Get-LambekPack
    #>
    [CmdletBinding()]
    param(
        [string] $Name = '*'
    )

    foreach ($pack in $script:Packs.Values) {
        if ($pack.Name -notlike $Name) { continue }

        $wordCount = 0
        foreach ($language in $pack.Words.Keys) {
            $wordCount += $pack.Words[$language].Count
        }

        [pscustomobject]@{
            PSTypeName  = 'Lambek.Pack'
            Name        = $pack.Name
            Version     = $pack.Version
            Description = $pack.Description
            Types       = @($pack.Types.Keys | Sort-Object)
            Words       = $wordCount
            Entities    = @($pack.Entities | ForEach-Object { $_.Name })
            Actions     = @($pack.Actions | ForEach-Object { $_.Id })
            Category    = $pack.Category
            Path        = $pack.Path
        }
    }
}
