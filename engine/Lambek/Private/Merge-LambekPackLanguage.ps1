function Merge-LambekPackLanguage {
    [CmdletBinding()]
    param(
        # The pack as read from pack.json
        [Parameter(Mandatory)]
        [hashtable] $Data,

        # One language file of the pack (languages/nl.json)
        [Parameter(Mandatory)]
        [hashtable] $Overlay,

        [Parameter(Mandatory)]
        [string] $Source
    )

    # A language of a pack lives in its own file: its words and their types, its sentences, its questions.
    # Nothing here changes what an action does, only how it is said and understood
    $language = [string] $Overlay['Language']
    if ($language -cnotmatch '^[a-z]{2,3}$') { throw "Language file '$Source' needs a Language like ""nl""." }

    # Words, base forms, rewrites, folders, category
    foreach ($key in 'Words', 'BaseForms', 'Gloss') {
        if (-not $Overlay.ContainsKey($key)) { continue }
        if (-not $Data.ContainsKey($key)) { $Data[$key] = @{} }
        $Data[$key][$language] = $Overlay[$key]
    }
    if ($Overlay.ContainsKey('Rewrites')) {
        if (-not $Data.ContainsKey('Rewrites')) { $Data.Rewrites = @() }
        # An idiom of one language only rewrites a sentence of that language ("back-up" is Dutch, not the folder D:\Backup)
        $own = @(foreach ($rewrite in @($Overlay.Rewrites)) { $rewrite['Language'] = $language; $rewrite })
        $Data.Rewrites = @($Data.Rewrites) + $own
    }
    if ($Overlay.ContainsKey('Folders')) {
        if (-not $Data.ContainsKey('Folders')) { $Data.Folders = @{} }
        foreach ($name in $Overlay.Folders.Keys) { $Data.Folders[$name] = $Overlay.Folders[$name] }
    }
    if ($Overlay.ContainsKey('Category')) {
        if (-not $Data.ContainsKey('Category')) { $Data.Category = @{} }
        $Data.Category[$language] = $Overlay.Category
    }

    # Compound tasks: how the language says them, and their steps in the language
    if ($Overlay.ContainsKey('Methods') -and $Data.ContainsKey('Methods')) {
        foreach ($name in $Overlay.Methods.Keys) {
            if (-not $Data.Methods.ContainsKey($name)) { continue }
            $Data.Methods[$name].Words[$language] = $Overlay.Methods[$name].Words
            $Data.Methods[$name].Steps[$language] = $Overlay.Methods[$name].Steps
        }
    }

    # Questions for a missing type ("Which files?")
    if ($Overlay.ContainsKey('Types')) {
        foreach ($base in $Overlay.Types.Keys) {
            if ($Data.Types.ContainsKey($base)) { $Data.Types[$base][$language] = $Overlay.Types[$base] }
        }
    }

    # Words for the kinds of object
    if ($Overlay.ContainsKey('Sorts') -and $Data.ContainsKey('Sorts')) {
        foreach ($base in $Overlay.Sorts.Keys) {
            if (-not $Data.Sorts.ContainsKey($base)) { continue }
            foreach ($sort in $Overlay.Sorts[$base].Keys) {
                if ($Data.Sorts[$base].ContainsKey($sort)) { $Data.Sorts[$base][$sort] = @($Data.Sorts[$base][$sort]) + @($Overlay.Sorts[$base][$sort]) }
            }
        }
    }

    # Entities: more rules, more units ("dagen", "Tage"), more orders ("nieuwste")
    if ($Overlay.ContainsKey('Entities')) {
        if (-not $Data.ContainsKey('Entities')) { $Data.Entities = @() }
        # A rule of one language only reads a sentence of that language (the Spanish "de musica" is not the French "de musique")
        $rules = @(foreach ($rule in @($Overlay.Entities)) { $rule['Language'] = $language; $rule })
        $Data.Entities = @($Data.Entities) + $rules
    }
    if (-not $Data.ContainsKey('Extras')) { $Data.Extras = @{ Units = @{}; Orders = @{} } }
    if ($Overlay.ContainsKey('Units')) {
        foreach ($name in $Overlay.Units.Keys) {
            if (-not $Data.Extras.Units.ContainsKey($name)) { $Data.Extras.Units[$name] = @{} }
            foreach ($unit in $Overlay.Units[$name].Keys) { $Data.Extras.Units[$name][$unit] = $Overlay.Units[$name][$unit] }
        }
    }
    if ($Overlay.ContainsKey('Orders')) {
        foreach ($said in $Overlay.Orders.Keys) { $Data.Extras.Orders[$said] = $Overlay.Orders[$said] }
    }

    # Actions: the same parameter reads the same way in every action, unless an action says otherwise
    $shared = @{}
    if ($Overlay.ContainsKey('Parameters')) { $shared = $Overlay.Parameters }
    $actions = @{}
    if ($Overlay.ContainsKey('Actions')) { $actions = $Overlay.Actions }
    foreach ($action in @($Data['Actions'])) {
        $own = @{}
        if ($actions.ContainsKey($action.Id)) { $own = $actions[$action.Id] }

        foreach ($key in 'Title', 'Examples', 'Say', 'Note') {
            if (-not $own.ContainsKey($key)) { continue }
            if (-not $action.ContainsKey($key) -or $action[$key] -isnot [hashtable]) { $action[$key] = @{} }
            $action[$key][$language] = $own[$key]
        }
        foreach ($key in 'Verbs', 'Uses') {
            if ($own.ContainsKey($key)) { $action[$key] = @(@($action[$key]) + @($own[$key]) | Select-Object -Unique) }
        }
        if ($own.ContainsKey('RequireOneOf') -and $action.ContainsKey('RequireOneOf')) { $action.RequireOneOf.Question[$language] = $own.RequireOneOf }

        # Which one: nouns, the words for all of them, and the question
        $which = $null
        if ($Overlay.ContainsKey('Which')) { $which = $Overlay.Which }
        if ($own.ContainsKey('Which')) { $which = $own.Which }
        if ($which -and $action.ContainsKey('Which')) {
            foreach ($key in 'Nouns', 'All', 'Among') {
                if ($which.ContainsKey($key)) { $action.Which[$key] = @(@($action.Which[$key]) + @($which[$key]) | Select-Object -Unique) }
            }
            if ($which.ContainsKey('Question')) { $action.Which.Question[$language] = $which.Question }
        }

        foreach ($parameter in @($action.Parameters)) {
            $said = @{}
            if ($shared.ContainsKey($parameter.Name)) { foreach ($key in $shared[$parameter.Name].Keys) { $said[$key] = $shared[$parameter.Name][$key] } }
            if ($own.ContainsKey('Parameters') -and $own.Parameters.ContainsKey($parameter.Name)) {
                foreach ($key in $own.Parameters[$parameter.Name].Keys) { $said[$key] = $own.Parameters[$parameter.Name][$key] }
            }
            # Only words the parameter already reads by: a word anchor, a question, a list of words
            if ($said.ContainsKey('After') -and $parameter.ContainsKey('After')) {
                $parameter.After = @(@($parameter.After) + @($said.After) | Select-Object -Unique)
            }
            if ($said.ContainsKey('Question') -and $parameter.ContainsKey('Question')) { $parameter.Question[$language] = $said.Question }
            if ($said.ContainsKey('Words') -and $parameter.ContainsKey('Words')) {
                foreach ($word in $said.Words.Keys) {
                    if (-not $parameter.Words.ContainsKey($word)) { $parameter.Words[$word] = $said.Words[$word] }
                }
            }
        }
    }
    return $Data
}
