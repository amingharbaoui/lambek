function Register-LambekPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Data,

        [Parameter(Mandatory)]
        [string] $Source
    )

    $file = $Source

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
    if (-not $data.ContainsKey('Commands')) { $data.Commands = @() }
    if (-not $data.ContainsKey('Category')) { $data.Category = @{} }
    if (-not $data.ContainsKey('Rewrites')) { $data.Rewrites = @() }
    if (-not $data.ContainsKey('Folders')) { $data.Folders = @{} }
    if (-not $data.ContainsKey('Kinds')) { $data.Kinds = @{} }
    # Gloss: each word of a language said in English, the pivot between two languages ("fichier": "file")
    if (-not $data.ContainsKey('Gloss')) { $data.Gloss = @{} }

    # Folders: a name in lower case without accents, and a special folder of .NET (or Downloads)
    $specials = [Enum]::GetNames([Environment+SpecialFolder]) + 'Downloads'
    foreach ($name in $data.Folders.Keys) {
        if ($name -cnotmatch '^[a-z]+( [a-z]+)*$' -or $data.Folders[$name] -notin $specials) {
            throw "Pack '$($data.Name)': folder '$name' needs a lower case name and a special folder."
        }
    }

    # Kinds: extensions like .jpg, used when the machine does not know the kind
    foreach ($kind in $data.Kinds.Keys) {
        foreach ($extension in @($data.Kinds[$kind])) {
            if ($extension -cnotmatch '^\.[a-z0-9]{1,10}$') {
                throw "Pack '$($data.Name)': kind '$kind' has an invalid extension '$extension'."
            }
        }
    }

    # Taxonomy: a kind made of other kinds ("media" is image, video and audio), never of itself
    if (-not $data.ContainsKey('Taxonomy')) { $data.Taxonomy = @{} }
    foreach ($kind in $data.Taxonomy.Keys) {
        if ($kind -cnotmatch '^[a-z]+$') { throw "Pack '$($data.Name)': taxonomy kind '$kind' needs a lower case name." }
        foreach ($part in @($data.Taxonomy[$kind])) {
            if ($part -cnotmatch '^[a-z]+$' -or $part -eq $kind) { throw "Pack '$($data.Name)': taxonomy kind '$kind' has an invalid part '$part'." }
        }
    }

    # Vague words: a trapezoid of membership (a, b, c, d) on a parameter, in a unit; null for an open side
    if (-not $data.ContainsKey('Vague')) { $data.Vague = @{} }
    foreach ($name in $data.Vague.Keys) {
        $vague = $data.Vague[$name]
        $shape = @($vague.Membership)
        if ($shape.Count -ne 4 -or -not $vague.Parameter -or $vague.Unit -notin 'day', 'KB', 'MB', 'GB') {
            throw "Pack '$($data.Name)': vague word '$name' needs a Parameter, a Unit (day, KB, MB, GB) and four Membership values."
        }
        $known = @($shape | Where-Object { $null -ne $_ })
        for ($k = 1; $k -lt $known.Count; $k++) {
            if ([double] $known[$k] -lt [double] $known[$k - 1]) { throw "Pack '$($data.Name)': the membership of vague word '$name' must not go down." }
        }
    }

    # Methods: a compound task, the ways to say it and the steps it stands for, by language
    if (-not $data.ContainsKey('Methods')) { $data.Methods = @{} }
    foreach ($name in $data.Methods.Keys) {
        $method = $data.Methods[$name]
        if ($name -cnotmatch '^[a-z]+$' -or -not $method.ContainsKey('Words') -or -not $method.ContainsKey('Steps')) {
            throw "Pack '$($data.Name)': method '$name' needs a lower case name, Words and Steps."
        }
        foreach ($language in $method.Words.Keys) {
            if (-not $method.Steps.ContainsKey($language) -or @($method.Steps[$language]).Count -eq 0) { throw "Pack '$($data.Name)': method '$name' has words but no steps in '$language'." }
            foreach ($step in @($method.Steps[$language])) {
                if ($step -notmatch '\{Path\}') { throw "Pack '$($data.Name)': a step of method '$name' does not say where ({Path})." }
            }
        }
    }

    # Rewrites: a pattern that compiles, and what it becomes
    foreach ($rewrite in @($data.Rewrites)) {
        if (-not $rewrite.Pattern -or $null -eq $rewrite.Replacement) {
            throw "Pack '$($data.Name)': a rewrite needs Pattern and Replacement."
        }
        try { [void] [regex]::new($rewrite.Pattern) }
        catch { throw "Pack '$($data.Name)': rewrite pattern '$($rewrite.Pattern)' is not valid." }
    }

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

    # Kinds of object a base names, for the meaning of sentences: { "o": { "file": [words], "folder": [words] } }
    if (-not $data.ContainsKey('Sorts')) { $data.Sorts = @{} }
    foreach ($base in $data.Sorts.Keys) {
        if (-not $knownBases.Contains($base) -or $base -eq 's') { throw "Pack '$($data.Name)': sorts name an unknown type '$base'." }
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
        if ($rule.Kind -notin 'text', 'lower', 'path', 'number', 'unit', 'duration', 'order', 'extension') {
            throw "Pack '$($data.Name)': entity '$($rule.Name)' has an unknown kind '$($rule.Kind)'."
        }
        if ($rule.Kind -in 'unit', 'duration' -and -not $rule.ContainsKey('Units')) {
            throw "Pack '$($data.Name)': entity '$($rule.Name)' needs Units."
        }
        if ($rule.Kind -eq 'order' -and -not $rule.ContainsKey('Orders')) {
            throw "Pack '$($data.Name)': entity '$($rule.Name)' needs Orders."
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
        $idPattern = "^" + [regex]::Escape($data.Name) + "\.[a-z][a-z0-9-]*$"
        if ($action.Id -notmatch $idPattern) {
            throw "Pack '$($data.Name)': action id '$($action.Id)' must start with '$($data.Name).'."
        }
        if ($action.Risk -notin 'low', 'medium', 'high') {
            throw "Pack '$($data.Name)': action '$($action.Id)' has an unknown risk '$($action.Risk)'."
        }
        if ($action.Examples.Count -eq 0) {
            throw "Pack '$($data.Name)': action '$($action.Id)' needs at least one example."
        }
        $parameterNames = @($action.Parameters | ForEach-Object { $_.Name })

        foreach ($key in 'Reads', 'Writes') {
            if (-not $action.ContainsKey($key)) { $action[$key] = @() }
            foreach ($name in $action[$key]) {
                if ($name -notin $parameterNames) {
                    throw "Pack '$($data.Name)': action '$($action.Id)' lists an unknown parameter '$name' in $key."
                }
            }
        }

        foreach ($effect in @($action['Effect'] | Where-Object { $_ })) {
            if ($effect -notin 'gone', 'arrived', 'renamed', 'exists') {
                throw "Pack '$($data.Name)': action '$($action.Id)' has an unknown effect '$effect'."
            }
        }

        # The kinds of object the action takes, among the sorts of the pack
        if ($action.ContainsKey('Objects')) {
            foreach ($base in $action.Objects.Keys) {
                foreach ($sort in @($action.Objects[$base])) {
                    if (-not $data.Sorts.ContainsKey($base) -or -not $data.Sorts[$base].ContainsKey($sort)) { throw "Pack '$($data.Name)': action '$($action.Id)' takes an unknown sort '$sort'." }
                }
            }
        }

        if ($action.ContainsKey('Which')) {
            foreach ($name in @($action.Which.By)) {
                if ($name -notin $parameterNames) { throw "Pack '$($data.Name)': action '$($action.Id)' picks one file by an unknown parameter '$name'." }
            }
        }

        if ($action.ContainsKey('Command') -and $action.Command -notin $data.Commands) {
            throw "Pack '$($data.Name)': action '$($action.Id)' names a command '$($action.Command)' the pack does not allow."
        }

        if (-not $action.ContainsKey('Output')) { $action.Output = 'command' }
        if ($action.Output -notin 'command', 'code', 'mcp') {
            throw "Pack '$($data.Name)': action '$($action.Id)' has an unknown output '$($action.Output)'."
        }

        $templates = @()
        if ($action.ContainsKey('Template')) { $templates += , $action.Template }
        if ($action.ContainsKey('Templates')) {
            foreach ($key in $action.Templates.Keys) { $templates += , $action.Templates[$key] }
        }
        foreach ($template in $templates) {
            foreach ($line in $template) {
                foreach ($placeholder in [regex]::Matches($line, '\{\{(?<name>[A-Za-z]+)!?\}\}|(?<=^(?:[?!][A-Za-z]+(?:=[\w.-]+)? )*)[?!](?<name>[A-Za-z]+)(?:=[\w.-]+)? ')) {
                    # Trash is a value of the engine: the folder deleted files wait in
                    if ($placeholder.Groups['name'].Value -notin $parameterNames -and $placeholder.Groups['name'].Value -ne 'Trash') {
                        throw "Pack '$($data.Name)': template of '$($action.Id)' uses an unknown parameter '$($placeholder.Groups['name'].Value)'."
                    }
                }
            }
        }

        foreach ($parameter in $action.Parameters) {
            if ($parameter.Name -notmatch '^[A-Z][A-Za-z0-9]*$') {
                throw "Pack '$($data.Name)': action '$($action.Id)' has an invalid parameter name '$($parameter.Name)'."
            }
            if (-not $parameter.ContainsKey('Entities') -and -not $parameter.ContainsKey('Words')) {
                throw "Pack '$($data.Name)': parameter '$($parameter.Name)' needs Entities or Words."
            }
            if ($parameter.ContainsKey('RequiredWith') -and $parameter.RequiredWith -notin $parameterNames) {
                throw "Pack '$($data.Name)': parameter '$($parameter.Name)' is required with an unknown parameter '$($parameter.RequiredWith)'."
            }
            if ($parameter.ContainsKey('Expand') -and $parameter.Expand -ne 'Extensions') {
                throw "Pack '$($data.Name)': parameter '$($parameter.Name)' has an unknown Expand '$($parameter.Expand)'."
            }
        }
    }

    # Register
    $pack = [pscustomobject]@{
        Name        = $data.Name
        Version     = $data.Version
        Description = $data.Description
        Path        = $Source
        Types       = $data.Types
        Words       = $data.Words
        Entities    = @($data.Entities)
        BaseForms   = $data.BaseForms
        Actions     = @($data.Actions)
        Commands    = @($data.Commands)
        Rewrites    = @($data.Rewrites)
        Folders     = $data.Folders
        Kinds       = $data.Kinds
        Taxonomy    = $data.Taxonomy
        Vague       = $data.Vague
        Methods     = $data.Methods
        Gloss       = $data.Gloss
        Extras      = $(if ($data.ContainsKey('Extras')) { $data.Extras } else { @{ Units = @{}; Orders = @{} } })
        Sorts      = $data.Sorts
        Category    = $data.Category
    }

    $script:Packs[$data.Name] = $pack
    $script:LexiconCache.Clear()
    $script:ActionIndexCache.Clear()
    $script:DomainSenseCache.Clear()
    $script:KnownFolderCache = $null
    $script:EntityRules = $null
    $script:KnownExtensions = $null

    return $data.Name
}
