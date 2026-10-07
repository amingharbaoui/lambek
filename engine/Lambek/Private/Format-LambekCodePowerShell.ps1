function Format-LambekCodePowerShell {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    $need = Get-LambekCodeNeed -Model $Model
    $lines = [System.Collections.Generic.List[string]]::new()

    # Header comment and the one parameter
    $lines.Add('#Requires -Version 7.0')
    foreach ($line in Get-LambekCodeHeader -Model $Model -Switch '-Apply' -Needs 'Needs PowerShell 7 or later, built-in commands only.') {
        $lines.Add(("# $line").TrimEnd())
    }
    $lines.Add(@'
[CmdletBinding()]
param(
    # Without it nothing is changed
    [switch] $Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Names with accents stay right when the output goes to a file or to another program (Windows would use an old code page)
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) }
catch { Write-Verbose 'The encoding of the console is kept.' }
'@)

    # Finding and choosing the files
    if ($need.Select) {
        $lines.Add('')
        $lines.Add(@'
function Get-TaskExtension {
    param([string] $Name)

    # ".txt" for "Notes.TXT", "" for a name without a dot
    $dot = $Name.LastIndexOf('.')
    if ($dot -lt 0) {
        return ''
    }
    return $Name.Substring($dot).ToLowerInvariant()
}

function Select-TaskFile {
    param(
        [string] $Root,
        [switch] $Recurse,
        [string] $Name,
        [string[]] $Extensions,
        [string[]] $ExceptExtensions = @(),
        [string] $ExceptName,
        [long] $OlderThan,
        [long] $NewerThan,
        [long] $MinSize,
        [long] $MaxSize,
        [string] $Order,
        [int] $Count,
        [long] $FreeBytes
    )

    # Filters: every one that is given must hold. Ages are in seconds, sizes in bytes.
    # Get-ChildItem without -Force skips what is hidden; a path to one file gives that file
    $now = [datetime]::UtcNow
    $kept = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse:$Recurse) {
        $extension = Get-TaskExtension -Name $file.Name
        if ($PSBoundParameters.ContainsKey('Name') -and $file.Name -ne $Name) { continue }
        if ($PSBoundParameters.ContainsKey('ExceptName') -and $file.Name -eq $ExceptName) { continue }
        if ($PSBoundParameters.ContainsKey('Extensions') -and $Extensions -notcontains $extension) { continue }
        if ($ExceptExtensions -contains $extension) { continue }
        if ($PSBoundParameters.ContainsKey('OlderThan') -and -not ($file.LastWriteTimeUtc -lt $now.AddSeconds(-$OlderThan))) { continue }
        if ($PSBoundParameters.ContainsKey('NewerThan') -and -not ($file.LastWriteTimeUtc -ge $now.AddSeconds(-$NewerThan))) { continue }
        if ($PSBoundParameters.ContainsKey('MinSize') -and -not ($file.Length -gt $MinSize)) { continue }
        if ($PSBoundParameters.ContainsKey('MaxSize') -and -not ($file.Length -lt $MaxSize)) { continue }
        $kept.Add($file)
    }

    # Order: by path first, so that files of the same size or date always come in the same order
    $sorted = $kept.ToArray()
    $paths = [string[]] @($sorted | ForEach-Object { $_.FullName })
    [array]::Sort($paths, $sorted, [System.StringComparer]::Ordinal)
    switch ($Order) {
        'newest' { $sorted = @($sorted | Sort-Object -Stable -Property LastWriteTimeUtc -Descending) }
        'oldest' { $sorted = @($sorted | Sort-Object -Stable -Property LastWriteTimeUtc) }
        'largest' { $sorted = @($sorted | Sort-Object -Stable -Property Length -Descending) }
        'smallest' { $sorted = @($sorted | Sort-Object -Stable -Property Length) }
    }

    # The first ones only, or as many as it takes to free the bytes asked
    if ($PSBoundParameters.ContainsKey('Count')) {
        $sorted = @($sorted | Select-Object -First $Count)
    }
    if ($PSBoundParameters.ContainsKey('FreeBytes')) {
        $chosen = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $freed = 0
        foreach ($file in $sorted) {
            if ($freed -ge $FreeBytes) { break }
            $freed += $file.Length
            $chosen.Add($file)
        }
        $sorted = $chosen.ToArray()
    }
    return , [System.IO.FileInfo[]] @($sorted)
}
'@)
    }

    if ($need.List) {
        $lines.Add('')
        $lines.Add(@'
function Write-TaskList {
    param([System.IO.FileInfo[]] $Files)

    # One line per file: path, size in bytes, last change (UTC)
    foreach ($file in $Files) {
        $moment = $file.LastWriteTimeUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
        Write-Output ($file.FullName + "`t" + $file.Length + "`t" + $moment)
    }
}
'@)
    }

    if ($need.Delete) {
        $lines.Add('')
        $lines.Add(@'
function Invoke-TaskDelete {
    param([System.IO.FileInfo[]] $Files, [bool] $Apply)

    # A real deletion: the file does not go to any trash
    foreach ($file in $Files) {
        if (-not $Apply) {
            Write-Output ('would delete: ' + $file.FullName)
            continue
        }
        Remove-Item -LiteralPath $file.FullName
        Write-Output ('deleted: ' + $file.FullName)
    }
}
'@)
    }

    if ($need.Transfer) {
        $lines.Add('')
        $lines.Add(@'
function Invoke-TaskTransfer {
    param([System.IO.FileInfo[]] $Files, [string] $Destination, [bool] $Move, [bool] $Apply)

    # Into the destination when it is a folder; one file alone may also go to a new name
    $verb = 'copy'
    $done = 'copied'
    if ($Move) {
        $verb = 'move'
        $done = 'moved'
    }
    $intoFolder = Test-Path -LiteralPath $Destination -PathType Container
    if (-not $intoFolder -and $Files.Count -gt 1) {
        if ($Apply) {
            throw "$Destination is not an existing folder"
        }
        [Console]::Error.WriteLine("warning: $Destination is not an existing folder yet")
        $intoFolder = $true
    }
    foreach ($file in $Files) {
        $target = $Destination
        if ($intoFolder) {
            $target = [System.IO.Path]::Combine($Destination, $file.Name)
        }
        if (-not $Apply) {
            Write-Output ("would $($verb): " + $file.FullName + ' -> ' + $target)
            continue
        }
        if ($Move) {
            # A move never replaces a file that is already there
            if (Test-Path -LiteralPath $target) {
                throw "$target already exists"
            }
            Move-Item -LiteralPath $file.FullName -Destination $target
        }
        else {
            # A copy replaces a file of the same name, and keeps the date of the original
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            (Get-Item -LiteralPath $target -Force).LastWriteTimeUtc = $file.LastWriteTimeUtc
        }
        Write-Output ("$($done): " + $file.FullName + ' -> ' + $target)
    }
}
'@)
    }

    if ($need.Rename) {
        $lines.Add('')
        $lines.Add(@'
function Invoke-TaskRename {
    param([string] $Source, [string] $NewName, [bool] $Apply)

    # A file or a folder gets a new name in the folder it is in
    $target = [System.IO.Path]::Combine([string] [System.IO.Path]::GetDirectoryName($Source), $NewName)
    if (-not $Apply) {
        Write-Output ('would rename: ' + $Source + ' -> ' + $target)
        return
    }
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "$Source does not exist"
    }
    if (Test-Path -LiteralPath $target) {
        throw "$target already exists"
    }
    Move-Item -LiteralPath $Source -Destination $target
    Write-Output ('renamed: ' + $Source + ' -> ' + $target)
}
'@)
    }

    if ($need.Create) {
        $lines.Add('')
        $lines.Add(@'
function Invoke-TaskCreate {
    param([string] $Path, [bool] $Folder, [bool] $Apply)

    # A new empty file (its folder must exist) or a new folder (with the folders above it)
    $kind = 'file'
    if ($Folder) {
        $kind = 'folder'
    }
    if (-not $Apply) {
        Write-Output ("would create $($kind): " + $Path)
        return
    }
    if (Test-Path -LiteralPath $Path) {
        throw "$Path already exists"
    }
    # The path is taken as it is written: the .NET calls read no wildcard in it
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ($Folder) {
        [void] [System.IO.Directory]::CreateDirectory($full)
    }
    else {
        [System.IO.File]::Open($full, [System.IO.FileMode]::CreateNew).Dispose()
    }
    Write-Output ("created $($kind): " + $Path)
}
'@)
    }

    # The steps of the plan
    $lines.Add('')
    $lines.Add('try {')
    $first = $true
    foreach ($step in $Model.Steps) {
        if (-not $first) { $lines.Add('') }
        $first = $false
        $lines.Add("    # Step $($step.Step): " + (ConvertTo-LambekCodeComment -Text $step.Sentence))
        foreach ($line in Format-LambekCodePowerShellStep -Step $step) { $lines.Add("    $line") }
    }
    if ($need.Changes) {
        $lines.Add('')
        $lines.Add('    if (-not $Apply) {')
        $lines.Add("        Write-Output 'Dry run: nothing was changed. Add -Apply to really do it.'")
        $lines.Add('    }')
    }
    $lines.Add(@'
}
catch {
    [Console]::Error.WriteLine('error: ' + $_.Exception.Message)
    exit 1
}
exit 0
'@)

    return (($lines -join "`n") -replace "`r", '') + "`n"
}

function Format-LambekCodePowerShellStep {
    param([pscustomobject] $Step)

    $quote = { param($text) ConvertTo-LambekCodeLiteral -Value $text -Language PowerShell }

    if ($Step.Operation -eq 'rename') {
        return "Invoke-TaskRename -Source $(& $quote $Step.Source) -NewName $(& $quote $Step.NewName) -Apply `$Apply"
    }
    if ($Step.Operation -eq 'create') {
        $folder = '$false'
        if ($Step.Kind -eq 'Directory') { $folder = '$true' }
        return "Invoke-TaskCreate -Path $(& $quote $Step.Path) -Folder $folder -Apply `$Apply"
    }

    # The filters that were asked, one per line
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add("Root = $(& $quote $Step.Root)")
    if ($Step.Recurse) { $arguments.Add('Recurse = $true') }
    if ($null -ne $Step.Name) { $arguments.Add("Name = $(& $quote $Step.Name)") }
    if ($null -ne $Step.Extensions) { $arguments.Add("Extensions = @($(@($Step.Extensions | ForEach-Object { & $quote $_ }) -join ', '))") }
    if ($Step.ExceptExtensions.Count -gt 0) { $arguments.Add("ExceptExtensions = @($(@($Step.ExceptExtensions | ForEach-Object { & $quote $_ }) -join ', '))") }
    if ($null -ne $Step.ExceptName) { $arguments.Add("ExceptName = $(& $quote $Step.ExceptName)") }
    if ($null -ne $Step.OlderThanSeconds) { $arguments.Add("OlderThan = $($Step.OlderThanSeconds)") }
    if ($null -ne $Step.NewerThanSeconds) { $arguments.Add("NewerThan = $($Step.NewerThanSeconds)") }
    if ($null -ne $Step.MinSize) { $arguments.Add("MinSize = $($Step.MinSize)") }
    if ($null -ne $Step.MaxSize) { $arguments.Add("MaxSize = $($Step.MaxSize)") }
    if ($null -ne $Step.Order) { $arguments.Add("Order = $(& $quote $Step.Order)") }
    if ($null -ne $Step.Count) { $arguments.Add("Count = $($Step.Count)") }
    if ($null -ne $Step.FreeBytes) { $arguments.Add("FreeBytes = $($Step.FreeBytes)") }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('$filter = @{')
    foreach ($argument in $arguments) { $lines.Add("    $argument") }
    $lines.Add('}')
    $lines.Add('$files = Select-TaskFile @filter')
    switch ($Step.Operation) {
        'list' { $lines.Add('Write-TaskList -Files $files') }
        'delete' { $lines.Add('Invoke-TaskDelete -Files $files -Apply $Apply') }
        'copy' { $lines.Add("Invoke-TaskTransfer -Files `$files -Destination $(& $quote $Step.Destination) -Move `$false -Apply `$Apply") }
        'move' { $lines.Add("Invoke-TaskTransfer -Files `$files -Destination $(& $quote $Step.Destination) -Move `$true -Apply `$Apply") }
    }
    return $lines.ToArray()
}
