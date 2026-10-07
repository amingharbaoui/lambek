function Find-LambekConcept {
    <#
    .SYNOPSIS
        Learns which files the user means from files they chose and files they refused (version space), with the
        exact probability of each description still possible (size principle) and the best file to ask about next.
    .EXAMPLE
        Find-LambekConcept -Positive 'C:\Photos\a.jpg', 'C:\Photos\b.jpg' -Negative 'C:\Photos\notes.txt' -Candidate (Get-ChildItem C:\Photos)
    #>
    [CmdletBinding()]
    param(
        # Files the user means: paths, file objects, or tables with Path, Length and LastWriteTime
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]] $Positive,

        # Files the user does not mean
        [object[]] $Negative = @(),

        # The other files in sight: they are counted by the size principle, and one of them is the next question
        [object[]] $Candidate = @(),

        # What a file is described by
        [ValidateSet('Type', 'Folder', 'Size', 'Age', 'Name')]
        [string[]] $Attribute = @('Type', 'Folder', 'Size', 'Age', 'Name'),

        # Kinds of files as @{ image = '.jpg', '.png' } and wider kinds as @{ media = 'image', 'video' };
        # the kinds of the loaded packs when left out
        [hashtable] $Kind,

        [hashtable] $Taxonomy,

        # The moment ages are counted from
        [datetime] $Now = (Get-Date)
    )

    # Kinds: the ones given, else those of the packs; each extension and each kind gets one parent (a tree)
    if (-not $PSBoundParameters.ContainsKey('Kind')) {
        $Kind = @{}
        foreach ($pack in $script:Packs.Values) {
            foreach ($name in $pack.Kinds.Keys) {
                if (-not $Kind.ContainsKey($name)) { $Kind[$name] = @($pack.Kinds[$name]) }
            }
        }
    }
    if (-not $PSBoundParameters.ContainsKey('Taxonomy')) {
        $Taxonomy = @{}
        foreach ($pack in $script:Packs.Values) {
            if (-not $pack.PSObject.Properties['Taxonomy'] -or -not $pack.Taxonomy) { continue }
            foreach ($name in $pack.Taxonomy.Keys) {
                if (-not $Taxonomy.ContainsKey($name)) { $Taxonomy[$name] = @($pack.Taxonomy[$name]) }
            }
        }
    }
    $kindOf = @{}
    foreach ($name in @($Kind.Keys | Sort-Object)) {
        foreach ($extension in @($Kind[$name])) {
            $key = ([string] $extension).ToLowerInvariant()
            if (-not $key.StartsWith('.')) { $key = ".$key" }
            if (-not $kindOf.ContainsKey($key)) { $kindOf[$key] = [string] $name }
        }
    }
    $parentOf = @{}
    foreach ($name in @($Taxonomy.Keys | Sort-Object)) {
        foreach ($part in @($Taxonomy[$name])) {
            if (-not $parentOf.ContainsKey([string] $part)) { $parentOf[[string] $part] = [string] $name }
        }
    }

    # Every file as one value per attribute, and the trees of these values
    $trees = [ordered]@{}
    foreach ($name in $Attribute) { $trees[$name] = [LambekConceptTree]::new($name) }
    if ($trees.Contains('Size')) {
        $trees['Size'].AddChain([string[]] @('under 10 KB', 'under 1 MB'))
        $trees['Size'].AddChain([string[]] @('10 KB to 1 MB', 'under 1 MB'))
        $trees['Size'].AddChain([string[]] @('1 MB to 100 MB', '1 MB or more'))
        $trees['Size'].AddChain([string[]] @('100 MB or more', '1 MB or more'))
    }
    if ($trees.Contains('Age')) {
        $trees['Age'].AddChain([string[]] @('under 1 day', 'under 30 days'))
        $trees['Age'].AddChain([string[]] @('1 to 7 days', 'under 30 days'))
        $trees['Age'].AddChain([string[]] @('7 to 30 days', 'under 30 days'))
        $trees['Age'].AddChain([string[]] @('30 days to 1 year', '30 days or more'))
        $trees['Age'].AddChain([string[]] @('1 year or more', '30 days or more'))
    }
    $groups = [ordered]@{ Positive = $Positive; Negative = $Negative; Candidate = $Candidate }
    $vectors = @{ Positive = [System.Collections.Generic.List[object]]::new(); Negative = [System.Collections.Generic.List[object]]::new(); Candidate = [System.Collections.Generic.List[object]]::new() }
    foreach ($group in $groups.Keys) {
        # A file given twice in a group counts once (the size principle counts the chosen files)
        $given = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($file in @($groups[$group])) {
            $instance = ConvertTo-LambekFileInstance -File $file -KindOf $kindOf -ParentOf $parentOf -Now $Now
            if (-not $given.Add($instance.Id)) { continue }
            $values = foreach ($name in $Attribute) {
                $chain = @($instance.Chains[$name])
                if ($chain.Count -eq 0) { [LambekConceptTree]::Root }
                else {
                    $trees[$name].AddChain([string[]] $chain)
                    $chain[0]
                }
            }
            $vectors[$group].Add([pscustomobject]@{ Id = $instance.Id; File = $file; Values = [string[]] @($values) })
        }
    }

    # Candidate elimination: the chosen files, then the refused ones
    $space = [LambekVersionSpace]::new([LambekConceptTree[]] @($trees.Values))
    foreach ($item in $vectors.Positive) { [void] $space.AddPositive($item.Values) }
    foreach ($item in $vectors.Negative) { [void] $space.AddNegative($item.Values) }

    # The universe of the size principle: every file in sight, once
    $universe = [System.Collections.Generic.List[string[]]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $open = [System.Collections.Generic.List[object]]::new()
    foreach ($group in $groups.Keys) {
        foreach ($item in $vectors[$group]) {
            if (-not $seen.Add($item.Id)) { continue }
            $universe.Add($item.Values)
            if ($group -eq 'Candidate') { $open.Add($item) }
        }
    }

    # Hypotheses with exact probabilities, the most likely first
    $hypotheses = foreach ($rank in $space.Rank($universe)) {
        [pscustomobject]@{
            Concept          = ConvertTo-LambekConceptTable -Attribute $Attribute -Value $rank.Hypothesis
            Text             = Format-LambekConcept -Attribute $Attribute -Value $rank.Hypothesis
            Size             = $rank.Size
            Probability      = $rank.Exact
            ProbabilityValue = $rank.Value
        }
    }

    # What is already sure about each candidate, and the one to ask about
    $answers = foreach ($item in $open) {
        [pscustomobject]@{ File = $item.File; Answer = $space.Classify($item.Values) }
    }
    $question = $null
    if ($open.Count -gt 0) {
        $asked = $space.NextQuestion([System.Collections.Generic.List[string[]]] @($open | ForEach-Object { , $_.Values }))
        if ($asked -ge 0) { $question = $open[$asked].File }
    }

    $specific = $null
    $specificText = ''
    if ($null -ne $space.Specific) {
        $specific = ConvertTo-LambekConceptTable -Attribute $Attribute -Value $space.Specific
        $specificText = Format-LambekConcept -Attribute $Attribute -Value $space.Specific
    }
    [pscustomobject]@{
        PSTypeName   = 'Lambek.Concept'
        S            = $specific
        SText        = $specificText
        G            = @($space.General | ForEach-Object { ConvertTo-LambekConceptTable -Attribute $Attribute -Value $_ })
        GText        = @($space.General | ForEach-Object { Format-LambekConcept -Attribute $Attribute -Value $_ })
        Converged    = $space.Converged
        Collapsed    = $space.Collapsed
        Reason       = $space.CollapseReason
        Hypotheses   = @($hypotheses)
        Answers      = @($answers)
        Question     = $question
        VersionSpace = $space
    }
}

function ConvertTo-LambekConceptTable {
    param([string[]] $Attribute, [string[]] $Value)

    # A hypothesis as a table: attribute = value
    $table = [ordered]@{}
    for ($i = 0; $i -lt $Attribute.Count; $i++) { $table[$Attribute[$i]] = $Value[$i] }
    return $table
}

function Format-LambekConcept {
    param([string[]] $Attribute, [string[]] $Value)

    # "Type=.jpg, Folder=C:\Photos": only what the hypothesis fixes; "any" when it fixes nothing
    $parts = for ($i = 0; $i -lt $Attribute.Count; $i++) {
        if ($Value[$i] -ne [LambekConceptTree]::Root) { "$($Attribute[$i])=$($Value[$i])" }
    }
    if (@($parts).Count -eq 0) { return [LambekConceptTree]::Root }
    return (@($parts) -join ', ')
}
