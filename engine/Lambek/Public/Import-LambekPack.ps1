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

        # Required fields
        foreach ($key in 'Name', 'Version', 'Types', 'Words') {
            if (-not $data.ContainsKey($key)) {
                throw "Pack '$file' must contain $key."
            }
        }
        if ($data.Name -notmatch '^[a-z][a-z0-9-]*$') {
            throw "Pack name '$($data.Name)' must be lower case letters, digits, or dashes."
        }
        if (-not $data.ContainsKey('Entities')) { $data.Entities = @() }
        if (-not $data.ContainsKey('BaseForms')) { $data.BaseForms = @{} }
        if (-not $data.ContainsKey('Description')) { $data.Description = '' }

        # Types
        $knownBases = [System.Collections.Generic.HashSet[string]]::new()
        [void] $knownBases.Add('s')
        foreach ($pack in $script:Packs.Values) {
            if ($pack.Name -eq $data.Name) { continue }
            foreach ($base in $pack.Types.Keys) { [void] $knownBases.Add($base) }
        }
        foreach ($base in $data.Types.Keys) {
            if ($base -notmatch '^[a-z]+$' -or $base -eq 's') {
                throw "Pack '$($data.Name)': invalid type name '$base'."
            }
            [void] $knownBases.Add($base)
        }

        # Words
        foreach ($language in $data.Words.Keys) {
            foreach ($word in $data.Words[$language].Keys) {
                foreach ($type in $data.Words[$language][$word]) {
                    foreach ($simpleType in ConvertFrom-LambekType -Type $type) {
                        if (-not $knownBases.Contains($simpleType.Base)) {
                            throw "Pack '$($data.Name)': word '$word' uses unknown type '$($simpleType.Base)'."
                        }
                    }
                }
            }
        }

        # Entities
        foreach ($rule in $data.Entities) {
            if ($rule.Name -notmatch '^[a-z]+$') {
                throw "Pack '$($data.Name)': invalid entity name '$($rule.Name)'."
            }
            if ($rule.Kind -notin 'text', 'lower', 'number', 'unit', 'duration') {
                throw "Pack '$($data.Name)': entity '$($rule.Name)' has an unknown kind '$($rule.Kind)'."
            }
            if ($rule.Kind -in 'unit', 'duration' -and -not $rule.ContainsKey('Units')) {
                throw "Pack '$($data.Name)': entity '$($rule.Name)' needs Units."
            }
            try {
                [void] [regex]::new($rule.Pattern)
            }
            catch {
                throw "Pack '$($data.Name)': entity '$($rule.Name)' has an invalid pattern."
            }
        }

        # Actions
        if (-not $data.ContainsKey('Actions')) { $data.Actions = @() }
        foreach ($action in $data.Actions) {
            foreach ($key in 'Id', 'Risk', 'Title', 'Verbs', 'Examples', 'Parameters') {
                if (-not $action.ContainsKey($key)) {
                    throw "Pack '$($data.Name)': an action must contain $key."
                }
            }
            $idPattern = "^" + [regex]::Escape($data.Name) + "\.[a-z][a-z-]*$"
            if ($action.Id -notmatch $idPattern) {
                throw "Pack '$($data.Name)': action id '$($action.Id)' must start with '$($data.Name).'."
            }
            if ($action.Risk -notin 'low', 'medium', 'high') {
                throw "Pack '$($data.Name)': action '$($action.Id)' has an unknown risk '$($action.Risk)'."
            }
            if ($action.Examples.Count -eq 0) {
                throw "Pack '$($data.Name)': action '$($action.Id)' needs at least one example."
            }
            foreach ($parameter in $action.Parameters) {
                if ($parameter.Name -notmatch '^[A-Z][A-Za-z]*$') {
                    throw "Pack '$($data.Name)': action '$($action.Id)' has an invalid parameter name '$($parameter.Name)'."
                }
                if (-not $parameter.ContainsKey('Entities') -and -not $parameter.ContainsKey('Words')) {
                    throw "Pack '$($data.Name)': parameter '$($parameter.Name)' needs Entities or Words."
                }
            }
        }

        # Register
        $pack = [pscustomobject]@{
            Name        = $data.Name
            Version     = $data.Version
            Description = $data.Description
            Path        = (Resolve-Path -LiteralPath $file).Path
            Types       = $data.Types
            Words       = $data.Words
            Entities    = @($data.Entities)
            BaseForms   = $data.BaseForms
            Actions     = @($data.Actions)
        }

        $script:Packs[$data.Name] = $pack
        $script:LexiconCache.Clear()
        $script:ActionIndexCache.Clear()

        Get-LambekPack -Name $data.Name
    }
}
