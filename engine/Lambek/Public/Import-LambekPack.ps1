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

        # Check and register
        $name = Register-LambekPack -Data $data -Source (Resolve-Path -LiteralPath $file).Path
        Get-LambekPack -Name $name
    }
}
