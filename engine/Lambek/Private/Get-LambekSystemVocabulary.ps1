function Get-LambekSystemVocabulary {
    [CmdletBinding()]
    param()

    # Read again every ten minutes: a program installed or a folder added while Lambek runs is seen without a restart
    if ($script:SystemVocabulary -and ([datetime]::UtcNow - $script:SystemVocabulary.Read) -lt [timespan]::FromMinutes(10)) {
        return $script:SystemVocabulary
    }

    $script:SystemVocabulary = [pscustomobject]@{
        Folders = Get-LambekSystemFolder
        Kinds   = Get-LambekSystemKind
        Read    = [datetime]::UtcNow
    }
    $script:KnownFolderCache = $null
    $script:EntityRules = $null
    $script:KnownExtensions = $null
    return $script:SystemVocabulary
}

function Get-LambekSystemFolder {
    # Special folders of .NET that live inside the user folder, by their spoken name:
    # MyPictures is "pictures", LocalApplicationData is "local application data"
    $folders = [ordered]@{}
    $userFolder = [Environment]::GetFolderPath('UserProfile')
    if (-not $userFolder) { return $folders }

    foreach ($name in [Enum]::GetNames([Environment+SpecialFolder]) | Sort-Object) {
        $path = [Environment]::GetFolderPath($name, [Environment+SpecialFolderOption]::DoNotVerify)
        # Only folders of the user: never the system, the programs, or the folders shared by all users
        if (-not $path -or -not $path.StartsWith($userFolder + [IO.Path]::DirectorySeparatorChar)) { continue }

        $spoken = ($name -creplace '^My(?=[A-Z])', '' -creplace '(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])', ' ').ToLowerInvariant()
        if (-not $folders.Contains($spoken)) { $folders[$spoken] = $name }
    }
    return $folders
}

function Get-LambekSystemKind {
    # The kind of every file extension the machine knows: image, video, audio, text, document, compressed
    $kinds = @{}

    # Windows: the PerceivedType of each extension in the registry
    if ($IsWindows) {
        try {
            $root = [Microsoft.Win32.Registry]::ClassesRoot
            foreach ($name in $root.GetSubKeyNames()) {
                if (-not $name.StartsWith('.')) { continue }
                $key = $root.OpenSubKey($name)
                if (-not $key) { continue }
                $kind = $key.GetValue('PerceivedType')
                $key.Dispose()
                if ($kind) { Add-LambekKindExtension -Kinds $kinds -Kind ([string] $kind).ToLowerInvariant() -Extension $name }
            }
        }
        catch {
            Write-Verbose "The registry could not be read: $($_.Exception.Message)"
        }
    }

    # Linux and macOS: the media types of mime.types
    foreach ($path in '/etc/mime.types', '/usr/share/mime/mime.types') {
        if ($IsWindows -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        foreach ($line in [IO.File]::ReadLines($path)) {
            if ($line -notmatch '^(?<type>[a-z]+/\S+)\s+(?<ext>.+)$') { continue }
            $extensions = $Matches['ext'] -split '\s+'
            $kind = switch -Regex ($Matches['type']) {
                '^image/' { 'image'; break }
                '^video/' { 'video'; break }
                '^audio/' { 'audio'; break }
                '^text/' { 'text'; break }
                '^application/.*(zip|compress|x-tar|rar|7z|bzip|x-xz|lzma|zstd)' { 'compressed'; break }
                '^application/.*(pdf|msword|officedocument|opendocument|rtf|ms-excel|ms-powerpoint|epub)' { 'document'; break }
            }
            if (-not $kind) { continue }
            foreach ($extension in $extensions) { Add-LambekKindExtension -Kinds $kinds -Kind $kind -Extension ".$extension" }
        }
        break
    }

    $sorted = @{}
    foreach ($kind in $kinds.Keys) { $sorted[$kind] = [string[]] @($kinds[$kind] | Sort-Object -Unique) }
    return $sorted
}

function Add-LambekKindExtension {
    param([hashtable] $Kinds, [string] $Kind, [string] $Extension)

    $clean = $Extension.ToLowerInvariant()
    if ($clean -notmatch '^\.[a-z0-9]{1,10}$') { return }
    if (-not $Kinds.ContainsKey($Kind)) { $Kinds[$Kind] = [System.Collections.Generic.List[string]]::new() }
    $Kinds[$Kind].Add($clean)
}

function Get-LambekKindExtension {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Kind
    )

    # A kind made of other kinds ("media") has the extensions of each of its parts
    $parts = @(Get-LambekKindPart -Kind $Kind)
    if ($parts.Count -gt 0) {
        $all = foreach ($part in $parts) { Get-LambekKindExtension -Kind $part }
        return [string[]] @($all | Sort-Object -Unique)
    }

    # The standard list of the packs always counts, the machine only adds more,
    # and never an extension a pack gives to another kind (".csv" stays text even when a spreadsheet claims it)
    $extensions = [System.Collections.Generic.List[string]]::new()
    $elsewhere = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pack in $script:Packs.Values) {
        foreach ($name in $pack.Kinds.Keys) {
            if ($name -eq $Kind) { $extensions.AddRange([string[]] @($pack.Kinds[$name])) }
            else { $elsewhere.UnionWith([string[]] @($pack.Kinds[$name])) }
        }
    }
    $system = (Get-LambekSystemVocabulary).Kinds
    if ($system.ContainsKey($Kind)) {
        foreach ($extension in $system[$Kind]) {
            if (-not $elsewhere.Contains($extension)) { $extensions.Add($extension) }
        }
    }
    if ($extensions.Count -eq 0) { return [string[]] @() }
    return [string[]] @($extensions | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
}

function Get-LambekKindPart {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Kind
    )

    # The kinds with extensions under a kind of the taxonomy, through any depth: within(K, P) is the transitive
    # closure of isa(K, P) in Datalog, so a loop between two packs still ends
    $logic = [LambekLogic]::new()
    $parents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($pack in $script:Packs.Values) {
        if (-not $pack.PSObject.Properties['Taxonomy'] -or -not $pack.Taxonomy) { continue }
        foreach ($parent in $pack.Taxonomy.Keys) {
            [void] $parents.Add($parent)
            foreach ($part in @($pack.Taxonomy[$parent])) { [void] $logic.Add('isa', [string[]] @($part, $parent)) }
        }
    }
    if (-not $parents.Contains($Kind)) { return [string[]] @() }
    $logic.Rules.AddRange((ConvertFrom-LambekLogic -Text 'within(K, P) :- isa(K, P). within(K, P) :- isa(K, Q), within(Q, P).'))
    $logic.Run()
    return [string[]] @($logic.Get('within') | Where-Object { $_[1] -eq $Kind -and -not $parents.Contains($_[0]) } | ForEach-Object { $_[0] } | Sort-Object -Unique)
}
