function ConvertTo-LambekFileInstance {
    [CmdletBinding()]
    param(
        # A path, a file object, or a table with Path (or FullName, Name), Length (or Size) and LastWriteTime (or Time)
        [Parameter(Mandatory)]
        [object] $File,

        # Extension to kind (".jpg" = "image") and kind to wider kind ("image" = "media")
        [hashtable] $KindOf = @{},

        [hashtable] $ParentOf = @{},

        [datetime] $Now = (Get-Date)
    )

    # A file as the version space sees it: for each attribute, its value and the wider values above it
    # (the most specific first; no value means "any")
    $path = Get-LambekFileField -File $File -Name 'Path', 'FullName', 'Name'
    if (-not $path) { throw 'A file description needs a path or a name.' }
    $path = [string] $path
    $cut = [math]::Max($path.LastIndexOf('/'), $path.LastIndexOf('\'))
    $leaf = $path.Substring($cut + 1)

    # Type: extension, kind, wider kinds
    $type = [System.Collections.Generic.List[string]]::new()
    $dot = $leaf.LastIndexOf('.')
    $stem = $leaf
    if ($dot -gt 0) {
        $stem = $leaf.Substring(0, $dot)
        $extension = $leaf.Substring($dot).ToLowerInvariant()
        $type.Add($extension)
        $kind = $null
        if ($KindOf.ContainsKey($extension)) { $kind = $KindOf[$extension] }
        while ($kind -and -not $type.Contains($kind)) {
            $type.Add($kind)
            if ($ParentOf.ContainsKey($kind)) { $kind = $ParentOf[$kind] }
            else { $kind = $null }
        }
    }
    else { $type.Add('(no extension)') }

    # Folder: the folder, its parent, and so on up to the root of the path
    $folder = [System.Collections.Generic.List[string]]::new()
    for ($i = $cut; $i -ge 0; $i--) {
        if ($path[$i] -ne '/' -and $path[$i] -ne '\') { continue }
        $prefix = $path.Substring(0, $i)
        # A drive keeps its separator ("C:\"); the root "/" says nothing more than "any" and is left out
        if ($prefix -match '^[A-Za-z]:$') { $prefix = $path.Substring(0, $i + 1) }
        if ($prefix -match '^[\\/]*$') { continue }
        if (-not $folder.Contains($prefix)) { $folder.Add($prefix) }
    }

    # Size: four classes in two halves
    $size = [System.Collections.Generic.List[string]]::new()
    $length = Get-LambekFileField -File $File -Name 'Length', 'Size'
    if ($null -ne $length) {
        $bytes = [double] $length
        if ($bytes -lt 10KB) { $size.AddRange([string[]] @('under 10 KB', 'under 1 MB')) }
        elseif ($bytes -lt 1MB) { $size.AddRange([string[]] @('10 KB to 1 MB', 'under 1 MB')) }
        elseif ($bytes -lt 100MB) { $size.AddRange([string[]] @('1 MB to 100 MB', '1 MB or more')) }
        else { $size.AddRange([string[]] @('100 MB or more', '1 MB or more')) }
    }

    # Age: five classes in two halves
    $age = [System.Collections.Generic.List[string]]::new()
    $time = Get-LambekFileField -File $File -Name 'LastWriteTime', 'Time'
    if ($null -ne $time) {
        $days = ($Now - [datetime] $time).TotalDays
        if ($days -lt 1) { $age.AddRange([string[]] @('under 1 day', 'under 30 days')) }
        elseif ($days -lt 7) { $age.AddRange([string[]] @('1 to 7 days', 'under 30 days')) }
        elseif ($days -lt 30) { $age.AddRange([string[]] @('7 to 30 days', 'under 30 days')) }
        elseif ($days -lt 365) { $age.AddRange([string[]] @('30 days to 1 year', '30 days or more')) }
        else { $age.AddRange([string[]] @('1 year or more', '30 days or more')) }
    }

    # Name: the name without its extension, then its first word ("IMG_001" is under "img*")
    $name = [System.Collections.Generic.List[string]]::new()
    $name.Add($stem)
    if ($stem -match '^\p{L}+') {
        $start = $Matches[0].ToLowerInvariant() + '*'
        if ($start -ne $stem) { $name.Add($start) }
    }

    [pscustomobject]@{
        Id     = $path
        File   = $File
        Chains = [ordered]@{
            Type   = [string[]] $type
            Folder = [string[]] $folder
            Size   = [string[]] $size
            Age    = [string[]] $age
            Name   = [string[]] $name
        }
    }
}

function Get-LambekFileField {
    param([object] $File, [string[]] $Name)

    # The first of the names the description has: a text is its own path, a table is read by key, an object by property
    if ($File -is [string]) {
        if ($Name -contains 'Path') { return $File }
        return $null
    }
    foreach ($key in $Name) {
        if ($File -is [System.Collections.IDictionary]) {
            if ($File.Contains($key) -and $null -ne $File[$key]) { return $File[$key] }
        }
        elseif ($File.PSObject.Properties[$key] -and $null -ne $File.PSObject.Properties[$key].Value) {
            return $File.PSObject.Properties[$key].Value
        }
    }
    return $null
}
