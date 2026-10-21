function Import-LambekPack {
    <#
    .SYNOPSIS
        Loads a DSL pack (vocabulary, grammar types, and entities) into Lambek.
    .EXAMPLE
        Import-LambekPack -Path ./dsl/files
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string] $Path
    )

    process {
        Clear-LambekReadCache
        # Find pack.json
        $file = $Path
        if (Test-Path -LiteralPath $Path -PathType Container) {
            $file = Join-Path $Path 'pack.json'
        }
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Pack file not found: $file"
        }

        # Read JSON
        try {
            $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            throw "Pack file is not valid JSON: $file"
        }

        # Its languages, one file each next to it (languages/nl.json)
        $folder = Join-Path (Split-Path -Path $file -Parent) 'languages'
        if (Test-Path -LiteralPath $folder -PathType Container) {
            foreach ($language in Get-ChildItem -LiteralPath $folder -Filter '*.json' | Sort-Object Name) {
                try { $overlay = Get-Content -LiteralPath $language.FullName -Raw | ConvertFrom-Json -AsHashtable }
                catch { throw "Language file is not valid JSON: $($language.FullName)" }
                $data = Merge-LambekPackLanguage -Data $data -Overlay $overlay -Source $language.FullName
            }
        }

        # Check and register
        $name = Register-LambekPack -Data $data -Source (Resolve-Path -LiteralPath $file).Path
        Get-LambekPack -Name $name
    }
}
