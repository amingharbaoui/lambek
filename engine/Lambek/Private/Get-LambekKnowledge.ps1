function Get-LambekKnowledge {
    [CmdletBinding()]
    param(
        # Facts for this question only, as @{ changes = @(@('C:\Temp')) }
        [hashtable] $Facts = @{}
    )

    # The rules and the facts of the machine are read once; each question adds its own facts and runs them
    if (-not $script:Knowledge) {
        $clauses = [System.Collections.Generic.List[object]]::new()
        $clauses.AddRange((ConvertFrom-LambekLogic -Text (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Data/rules.dl') -Raw)))
        if (Test-Path -LiteralPath $script:RulesPath -PathType Leaf) {
            $clauses.AddRange((ConvertFrom-LambekLogic -Text (Get-Content -LiteralPath $script:RulesPath -Raw)))
        }

        $machine = [System.Collections.Generic.List[object]]::new()
        $os = 'linux'
        if ($IsWindows) { $os = 'windows' }
        elseif ($IsMacOS) { $os = 'macos' }
        $machine.Add(@('os', $os))
        foreach ($name in 'Windows', 'System', 'SystemX86', 'ProgramFiles', 'ProgramFilesX86', 'CommonProgramFiles', 'CommonProgramFilesX86', 'CommonApplicationData') {
            $path = [Environment]::GetFolderPath($name)
            if ($path) { $machine.Add(@('protected', $path)) }
        }
        foreach ($drive in [IO.DriveInfo]::GetDrives()) { $machine.Add(@('root', $drive.Name)) }
        $userFolder = [Environment]::GetFolderPath('UserProfile')
        $machine.Add(@('home', $userFolder))
        # The folder of every user (C:\Users, /home), unless the user folder sits at the root of a drive
        $users = Split-Path -Path $userFolder -Parent
        if ($users -and $users -ne [IO.Path]::GetPathRoot($userFolder)) { $machine.Add(@('users', $users)) }

        $script:Knowledge = [pscustomobject]@{ Clauses = $clauses; Machine = $machine }
    }

    $logic = [LambekLogic]::new()
    foreach ($fact in $script:Knowledge.Machine) { [void] $logic.Add($fact[0], [string[]] @($fact | Select-Object -Skip 1)) }
    foreach ($clause in $script:Knowledge.Clauses) {
        if ($clause.Body.Count -eq 0) {
            [void] $logic.Add($clause.Head.Name, [string[]] @($clause.Head.Terms | ForEach-Object { [LambekLogic]::Value($_) }))
        }
        else { $logic.Rules.Add($clause) }
    }
    foreach ($name in $Facts.Keys) {
        foreach ($row in $Facts[$name]) { [void] $logic.Add($name, [string[]] @($row)) }
    }
    $logic.Run()
    return $logic
}

function Test-LambekPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Paths
    )

    # The paths a step changes that the rules forbid, with the reason; a path is also read where it really leads, through
    # every link on the way (a symbolic link, a junction: "C:\Temp\sys" may be C:\Windows)
    if ($Paths.Count -eq 0) { return @() }
    $all = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $Paths) {
        $all.Add($path)
        $real = Get-LambekRealPath -Path $path
        if ($real -and -not $all.Contains($real)) { $all.Add($real) }
    }
    $logic = Get-LambekKnowledge -Facts @{ changes = @($all | ForEach-Object { , @($_) }) }
    foreach ($row in $logic.Get('blocked')) {
        # The proof of the block, for "why?": the rule and the facts that gave it
        [pscustomobject]@{ Path = $row[0]; Reason = $row[1]; Proof = @($logic.Explain('blocked', [string[]] $row, 6)) }
    }
}

function Get-LambekRealPath {
    # Where a full path of this system really leads: each folder on the way that is a link is followed to its final
    # target; the part that does not exist yet is added as it is written. Nothing for a path of another system
    param([string] $Path)

    if (-not $Path -or -not [IO.Path]::IsPathFullyQualified($Path)) { return $null }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return $null }
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    $parts = @($full.Substring($root.Length) -split '[\\/]' | Where-Object { $_ })
    # Read with .NET, not the PowerShell provider: "D:\Backup" on a computer without a D: drive is a path that does
    # not exist yet, not an error; a folder that cannot be read is left as it is written
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $next = [IO.Path]::Combine($current, $parts[$i])
        $link = $null
        $exists = $false
        try {
            $item = [IO.DirectoryInfo]::new($next)
            if (-not $item.Exists) { $item = [IO.FileInfo]::new($next) }
            $exists = $item.Exists
            $link = $item.LinkTarget
            if ($link) {
                $target = $item.ResolveLinkTarget($true)
                if ($target) { $next = $target.FullName }
            }
        }
        catch { $exists = $false }
        if (-not $exists -and -not $link) { return (@($next) + @($parts | Select-Object -Skip ($i + 1)) -join [IO.Path]::DirectorySeparatorChar) }
        $current = $next
    }
    return $current
}
