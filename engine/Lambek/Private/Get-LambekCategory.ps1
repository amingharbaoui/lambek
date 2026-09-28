function Get-LambekCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    foreach ($pack in $script:Packs.Values) {
        $texts = $null
        if ($pack.Category.ContainsKey($Language)) { $texts = $pack.Category[$Language] }
        elseif ($pack.Category.ContainsKey('en')) { $texts = $pack.Category['en'] }

        $title = $pack.Name
        $summary = $pack.Description
        $examples = @()
        if ($texts) {
            $title = $texts.Title
            $summary = $texts.Summary
            $examples = @($texts.Examples)
        }

        [pscustomobject]@{
            Pack     = $pack.Name
            Title    = $title
            Summary  = $summary
            Examples = $examples
            Actions  = @($pack.Actions | ForEach-Object { Get-LambekTitle -Action $_ -Language $Language })
        }
    }
}
