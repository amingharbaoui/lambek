function ConvertTo-LambekMcpPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Server,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Tools
    )

    $packName = 'mcp-' + (($Server.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
    $actions = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()
    $words = @{}
    $ids = @{}
    # Requests are read in base forms (search -> find), so actions know both
    $baseForms = (Get-LambekLexicon -Language 'en').BaseForms

    foreach ($tool in $Tools) {
        $name = [string] $tool.name
        $parts = @(Split-LambekMcpName -Name $name)
        $id = "$packName." + (($parts -join '-') -replace '^[^a-z]+', '')
        if ($parts.Count -eq 0 -or $id -notmatch '\.[a-z][a-z0-9-]*$' -or $ids.ContainsKey($id)) {
            $skipped.Add([pscustomobject]@{ Tool = $name; Reason = 'name cannot be used' })
            continue
        }

        # Parameters from the input schema
        $schema = @{}
        if ($tool.Contains('inputSchema') -and $tool.inputSchema -is [System.Collections.IDictionary]) { $schema = $tool.inputSchema }
        $required = @()
        if ($schema.Contains('required')) { $required = @($schema.required) }
        $properties = @{}
        if ($schema.Contains('properties') -and $schema.properties -is [System.Collections.IDictionary]) { $properties = $schema.properties }

        $parameters = [System.Collections.Generic.List[object]]::new()
        $reason = $null
        $names = @{}
        $ordered = @($properties.Keys | Where-Object { $_ -in $required }) + @($properties.Keys | Where-Object { $_ -notin $required })
        foreach ($property in $ordered) {
            $parameter = ConvertTo-LambekMcpParameter -Property $property -Schema $properties[$property] -Required ($property -in $required)
            if ($null -eq $parameter -or $names.ContainsKey($parameter.Name)) {
                if ($property -in $required) { $reason = "parameter '$property' has a type Lambek cannot fill yet" }
                continue
            }
            $names[$parameter.Name] = $true
            $parameters.Add($parameter)
            $type = 'o^r o'
            $parameter.Definition.After = @(Get-LambekMcpForm -Words $parameter.After -BaseForms $baseForms)
            foreach ($word in $parameter.Definition.After) { Add-LambekMcpWord -Words $words -Word $word -Type $type }
        }
        foreach ($property in $required) {
            if (-not $properties.Contains($property)) { $reason = "parameter '$property' has no schema" }
        }
        if ($reason) {
            $skipped.Add([pscustomobject]@{ Tool = $name; Reason = $reason })
            continue
        }

        # Risk from the annotations: read-only is low, non-destructive is medium, the rest is high
        $annotations = @{}
        if ($tool.Contains('annotations') -and $tool.annotations -is [System.Collections.IDictionary]) { $annotations = $tool.annotations }
        $risk = 'high'
        if ($annotations.Contains('readOnlyHint') -and $annotations.readOnlyHint -eq $true) { $risk = 'low' }
        elseif ($annotations.Contains('destructiveHint') -and $annotations.destructiveHint -eq $false) { $risk = 'medium' }

        # Words: the first part is the verb, the others name the object
        $verbs = @(Get-LambekMcpForm -Words $parts[0] -BaseForms $baseForms)
        foreach ($verb in $verbs) { Add-LambekMcpWord -Words $words -Word $verb -Type 's o^l' }
        for ($i = 1; $i -lt $parts.Count; $i++) {
            $type = 'o o^l'
            if ($i -eq $parts.Count - 1) { $type = 'o' }
            # Singular and plural: note, notes
            $forms = @(Get-LambekMcpForm -Words $parts[$i] -BaseForms $baseForms)
            if ($parts[$i].Length -gt 4 -and $parts[$i].EndsWith('s')) { $forms += $parts[$i].Substring(0, $parts[$i].Length - 1) }
            elseif (-not $parts[$i].EndsWith('s')) { $forms += $parts[$i] + 's' }
            foreach ($form in $forms) { Add-LambekMcpWord -Words $words -Word $form -Type $type }
        }

        $phrase = $parts -join ' '
        $title = $phrase.Substring(0, 1).ToUpperInvariant() + $phrase.Substring(1)
        if ($tool.Contains('title') -and $tool.title) { $title = [string] $tool.title }
        $description = ''
        if ($tool.Contains('description') -and $tool.description) { $description = [string] $tool.description }

        $examples = [System.Collections.Generic.List[string]]::new()
        $examples.Add($phrase)
        if ($title.ToLowerInvariant() -ne $phrase) { $examples.Add($title.ToLowerInvariant()) }
        $sentence = (($description -split '(?<=[.!?])\s|\n')[0] -split '\s+' | Select-Object -First 10) -join ' '
        if ($sentence) { $examples.Add($sentence.TrimEnd('.').ToLowerInvariant()) }

        $say = [System.Collections.Generic.List[string]]::new()
        $say.Add($phrase)
        foreach ($parameter in $parameters) {
            $value = "{$($parameter.Name)}"
            if ($parameter.Schema.Type -eq 'string' -and -not $parameter.Definition.ContainsKey('Words')) { $value = """{$($parameter.Name)}""" }
            $say.Add("?$($parameter.Name) , $($parameter.After -join ' ') $value")
        }

        $toolHash = Get-LambekMcpToolHash -Tool $tool
        $actions.Add(@{
                Id          = $id
                Risk        = $risk
                Title       = @{ en = $title; fr = $title }
                Description = $description
                Verbs       = $verbs
                Examples    = @{ en = @($examples | Select-Object -Unique) }
                Parameters  = @($parameters | ForEach-Object { $_.Definition })
                Output      = 'mcp'
                Reads       = @()
                Writes      = @()
                Say         = @{ en = $say.ToArray() }
                Mcp         = @{ Server = $Server; Tool = $name; Hash = $toolHash; Schema = $schema; Map = @($parameters | ForEach-Object { @{ Name = $_.Name; Property = $_.Property; Type = $_.Schema.Type } }) }
            })
        $ids[$id] = $true
    }

    # Parameter words and values refine the object: notes, query "budget"
    $data = @{
        Name        = $packName
        Version     = '1.0.0'
        Description = "Tools of the MCP server $Server."
        Types       = @{
            o = @{ en = 'Which one?'; fr = 'Lequel ?' }
        }
        Words       = @{
            '*' = @{ _quoted_ = @('o^r o'); _number_ = @('o^r o'); _path_ = @('o^r o'); _filename_ = @('o^r o'); _url_ = @('o^r o'); _email_ = @('o^r o') }
            en  = $words
        }
        Actions     = $actions.ToArray()
        Category    = @{
            en = @{ Title = $Server; Summary = "$($actions.Count) tool(s) from the MCP server $Server."; Examples = @($actions | Select-Object -First 3 | ForEach-Object { $_.Examples.en[0] }) }
            fr = @{ Title = $Server; Summary = "$($actions.Count) outil(s) du serveur MCP $Server."; Examples = @($actions | Select-Object -First 3 | ForEach-Object { $_.Examples.en[0] }) }
        }
    }

    return [pscustomobject]@{ Data = $data; Skipped = $skipped.ToArray() }
}

function Get-LambekMcpToolHash {
    param([System.Collections.IDictionary] $Tool)

    # Name, input schema, and annotations: what the plan depends on
    $parts = [ordered]@{ name = $Tool.name; inputSchema = $null; annotations = $null }
    if ($Tool.Contains('inputSchema')) { $parts.inputSchema = $Tool.inputSchema }
    if ($Tool.Contains('annotations')) { $parts.annotations = $Tool.annotations }
    return Get-LambekHash -Text ($parts | ConvertTo-Json -Depth 30 -Compress)
}

function Get-LambekMcpForm {
    param(
        [string[]] $Words,
        [hashtable] $BaseForms
    )

    foreach ($word in $Words) {
        $word
        if ($BaseForms.ContainsKey($word) -and $BaseForms[$word] -ne $word) { $BaseForms[$word] }
    }
}

function Add-LambekMcpWord {
    param(
        [hashtable] $Words,
        [string] $Word,
        [string] $Type
    )

    if (-not $Words.ContainsKey($Word)) { $Words[$Word] = @() }
    if ($Type -notin $Words[$Word]) { $Words[$Word] += $Type }
}

function Split-LambekMcpName {
    param([string] $Name)

    # getUser, read_text_file, admin.tools.list
    $spaced = $Name -creplace '(?<=[a-z0-9])(?=[A-Z])', ' ' -replace '[_.\-\s]+', ' '
    return @($spaced.ToLowerInvariant() -split ' ' | Where-Object { $_ -match '^[a-z][a-z0-9]*$' })
}

function ConvertTo-LambekMcpParameter {
    param(
        [string] $Property,
        [object] $Schema,
        [bool] $Required
    )

    if ($Schema -isnot [System.Collections.IDictionary]) { return $null }
    foreach ($keyword in '$ref', 'anyOf', 'oneOf', 'allOf') {
        if ($Schema.Contains($keyword)) { return $null }
    }

    $type = 'string'
    if ($Schema.Contains('type')) {
        $types = @($Schema.type | Where-Object { $_ -ne 'null' })
        if ($types.Count -ne 1) { return $null }
        $type = [string] $types[0]
    }
    if ($type -notin 'string', 'integer', 'number', 'boolean') { return $null }

    $parts = @(Split-LambekMcpName -Name $Property)
    if ($parts.Count -eq 0) { return $null }
    $name = ($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''

    $definition = @{ Name = $name; After = $parts }
    if ($Schema.Contains('enum')) {
        $choices = @{}
        foreach ($value in $Schema.enum) { $choices[([string] $value).ToLowerInvariant()] = [string] $value }
        $definition.Words = $choices
    }
    elseif ($type -eq 'boolean') {
        $definition.Words = @{ $parts[-1] = 'true' }
    }
    elseif ($type -in 'integer', 'number') {
        $definition.Entities = @('number')
        $definition.Fallback = $true
    }
    else {
        $definition.Entities = @('quoted', 'path', 'filename', 'url', 'email')
        $definition.Fallback = $true
        $definition.Free = $true
    }

    if ($Required) {
        $label = $parts -join ' '
        $definition.Required = $true
        $definition.Question = @{ en = "What should $label be?"; fr = "Quelle valeur pour $label ?" }
    }

    return [pscustomobject]@{
        Name       = $name
        Property   = $Property
        After      = $parts
        Schema     = [pscustomobject]@{ Type = $type }
        Definition = $definition
    }
}
