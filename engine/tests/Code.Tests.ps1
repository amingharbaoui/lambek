BeforeDiscovery {
    # The tools on this machine decide which tests run: a missing one is skipped, and the name of the test says why
    function Test-ToolPresent {
        param([string[]] $Name)
        foreach ($candidate in $Name) {
            # A real tool answers --version with code 0; the "python" of Windows that only opens the store does not
            $found = @(Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue)
            if ($found.Count -eq 0) { continue }
            try { $null = & $found[0].Source --version 2>&1; if ($LASTEXITCODE -eq 0) { return $true } }
            catch { continue }
        }
        return $false
    }

    $backends = @(
        @{ Language = 'PowerShell'; Missing = $false; Why = '' }
        @{ Language = 'Python'; Missing = -not (Test-ToolPresent -Name 'python3', 'python'); Why = ' [skipped: python is not installed]' }
        @{ Language = 'JavaScript'; Missing = -not (Test-ToolPresent -Name 'node', 'nodejs'); Why = ' [skipped: node is not installed]' }
        @{ Language = 'CSharp'; Missing = $false; Why = '' }
        @{ Language = 'Rust'; Missing = -not (Test-ToolPresent -Name 'rustc'); Why = ' [skipped: rustc is not installed]' }
        @{ Language = 'Bash'; Missing = $IsWindows -or -not (Test-ToolPresent -Name 'bash'); Why = ' [skipped: needs bash with GNU find]' }
    )
    foreach ($backend in $backends) {
        if (-not $backend.Missing) { $backend.Why = '' }
    }

    # The requests of the golden tests: one per action of the files pack
    $requests = @(
        'list the 3 largest images in /tmp/x'
        'delete the .log files older than 30 days in C:\Temp'
        'copy the .txt files from /tmp/a to /tmp/b'
        'move the files larger than 1 MB from /tmp/a to /tmp/b'
        'rename /tmp/a/report.txt to final.txt'
        'create a folder /tmp/a/new'
        'free 2 GB in /tmp/a'
    )
    $syntaxCases = foreach ($request in $requests) {
        foreach ($backend in $backends) {
            @{ Text = $request; Language = $backend.Language; Missing = $backend.Missing; Why = $backend.Why }
        }
    }

    # The behaviour tests: every scenario in every language
    $scenarios = @(
        'list with filters', 'list newest first', 'list the two oldest', 'list small recent files',
        'delete old logs', 'delete images but not png', 'delete the three largest', 'free space',
        'copy into a folder', 'copy one file to a new name', 'move by name', 'rename', 'create'
    )
    $behaviourCases = foreach ($scenario in $scenarios) {
        foreach ($backend in $backends) {
            @{ Scenario = $scenario; Language = $backend.Language; Missing = $backend.Missing; Why = $backend.Why }
        }
    }

    # The skeletons of code.generate: every kind in every language
    $skeletonCases = foreach ($backend in $backends) {
        foreach ($kind in 'Function', 'Script', 'Class', 'Module', 'Test') {
            @{ Kind = $kind; Language = $backend.Language; Missing = $backend.Missing; Why = $backend.Why }
        }
    }
}

BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    # Plans are slow to build: each request is planned once for the whole file
    $script:PlanCache = @{}
    function Get-TestPlan {
        param([string] $Text)
        if (-not $script:PlanCache.ContainsKey($Text)) { $script:PlanCache[$Text] = New-LambekPlan -Text $Text }
        return $script:PlanCache[$Text]
    }

    function Get-TestStep {
        param([string] $Text)
        $plan = Get-TestPlan -Text $Text
        $model = InModuleScope Lambek -Parameters @{ Plan = $plan } { ConvertTo-LambekCodeModel -Plan $Plan }
        return $model.Steps[0]
    }

    # A model made by hand: the parameters of each step exactly as a plan would hold them, without the planning
    function New-TestModel {
        param([hashtable[]] $Steps)
        InModuleScope Lambek -Parameters @{ Steps = $Steps } {
            $number = 0
            $made = foreach ($wanted in $Steps) {
                $number++
                $values = [ordered]@{}
                foreach ($key in $wanted.Keys) {
                    if ($key -ne 'Action') { $values[$key] = $wanted[$key] }
                }
                $step = [pscustomobject]@{
                    Step = $number; Action = $wanted.Action; Status = 'Test'; Clause = "step $number of a test"
                    Language = 'en'; Output = 'command'; Parameters = $values
                }
                ConvertTo-LambekCodeStep -Step $step
            }
            [pscustomobject]@{ PSTypeName = 'Lambek.CodeModel'; Original = 'a request made for a test'; Steps = @($made) }
        }
    }

    function Get-TestCode {
        param([pscustomobject] $Model, [string] $Language)
        InModuleScope Lambek -Parameters @{ Model = $Model; Language = $Language } { & "Format-LambekCode$Language" -Model $Model }
    }

    function Get-TestLiteral {
        param([string] $Value, [string] $Language)
        InModuleScope Lambek -Parameters @{ Value = $Value; Language = $Language } { ConvertTo-LambekCodeLiteral -Value $Value -Language $Language }
    }

    function Invoke-TestTool {
        param([string] $FilePath, [string[]] $Arguments = @())
        InModuleScope Lambek -Parameters @{ FilePath = $FilePath; Arguments = $Arguments } {
            Invoke-LambekCodeTool -FilePath $FilePath -ArgumentList $Arguments -TimeoutSeconds 180
        }
    }

    function Find-TestTool {
        param([string[]] $Name)
        foreach ($candidate in $Name) {
            $found = @(Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue)
            if ($found.Count -eq 0) { continue }
            try { $null = & $found[0].Source --version 2>&1; if ($LASTEXITCODE -eq 0) { return $found[0].Source } }
            catch { continue }
        }
        return $null
    }

    # Runs a generated program: dry run unless -Apply. Rust is built once per program; C# is built with the
    # compiler inside PowerShell (there is no dotnet SDK here) and its Main is called with the console captured
    function Invoke-TestProgram {
        param([string] $Language, [string] $Code, [string] $Folder, [switch] $Apply, [string[]] $Extra = @())

        $names = @{ PowerShell = 'task.ps1'; Python = 'task.py'; JavaScript = 'task.js'; CSharp = 'Program.cs'; Rust = 'main.rs'; Bash = 'task.sh' }
        $file = Join-Path $Folder $names[$Language]
        if (-not (Test-Path -LiteralPath $file)) {
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
            [System.IO.File]::WriteAllText($file, $Code, [System.Text.UTF8Encoding]::new($false))
        }
        $switches = @($Extra)
        if ($Apply -and $Language -eq 'PowerShell') { $switches += '-Apply' }
        elseif ($Apply) { $switches += '--apply' }

        switch ($Language) {
            'PowerShell' { return Invoke-TestTool -FilePath (Get-Process -Id $PID).Path -Arguments (@('-NoProfile', '-File', $file) + $switches) }
            'Python' { return Invoke-TestTool -FilePath (Find-TestTool -Name 'python3', 'python') -Arguments (@($file) + $switches) }
            'JavaScript' { return Invoke-TestTool -FilePath (Find-TestTool -Name 'node', 'nodejs') -Arguments (@($file) + $switches) }
            'Bash' { return Invoke-TestTool -FilePath (Find-TestTool -Name 'bash') -Arguments (@($file) + $switches) }
            'Rust' {
                $binary = Join-Path $Folder 'task-bin'
                if (-not (Test-Path -LiteralPath $binary)) {
                    $build = Invoke-TestTool -FilePath (Find-TestTool -Name 'rustc') -Arguments @('--edition', '2021', '--color', 'never', '-o', $binary, $file)
                    if ($build.ExitCode -ne 0) { throw "rustc failed: $($build.Error)" }
                }
                return Invoke-TestTool -FilePath $binary -Arguments $switches
            }
            'CSharp' {
                $library = Join-Path $Folder 'task.dll'
                if (-not (Test-Path -LiteralPath $library)) {
                    Add-Type -Path $file -OutputAssembly $library -OutputType Library -IgnoreWarnings
                }
                $main = [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($library)).GetType('Program').GetMethod('Main', [System.Reflection.BindingFlags] 'NonPublic, Public, Static')
                $output = [System.IO.StringWriter]::new()
                $failure = [System.IO.StringWriter]::new()
                $oldOutput = [Console]::Out
                $oldFailure = [Console]::Error
                [Console]::SetOut($output)
                [Console]::SetError($failure)
                try { $exit = [int] $main.Invoke($null, (, [string[]] $switches)) }
                finally {
                    [Console]::SetOut($oldOutput)
                    [Console]::SetError($oldFailure)
                }
                return [pscustomobject]@{ ExitCode = $exit; Output = $output.ToString(); Error = $failure.ToString(); TimedOut = $false }
            }
        }
    }

    # The fixture: name, size in bytes, age in days. Two pairs have the same size or the same date on purpose
    function New-TestFixture {
        param([string] $Root)

        $accent = 'accent' + [char] 0x00E9 + '.txt'
        $odd = 'it''s "odd" $x `y.md'
        if ($IsWindows) { $odd = 'it''s ''odd'' $x `y.md' }
        $files = @(
            @('a.log', 100, 40), @('b.log', 2000, 10), @('keep.log', 500, 50), @('C.LOG', 300, 31),
            @('notes.txt', 50, 5), @('big.txt', 5000, 100), @('tiny.txt', 5, 1), @('same1.txt', 700, 3), @('same2.txt', 700, 3),
            @('photo.jpg', 3000, 60), @('pic.PNG', 1500, 20), @('noext', 20, 2), @('dot.', 30, 2), @('archive.tar.gz', 800, 70),
            @('.hidden.log', 100, 90), @('.hiddendir/in.log', 100, 90),
            @('sub/x.log', 150, 45), @('sub/deeper/y.log', 250, 35), @('sub/z.txt', 60, 6), @('sub/deeper/old.jpg', 900, 400),
            @($odd, 10, 1), @('sp ace [1].txt', 11, 2), @($accent, 12, 2), @('linktarget/inner.log', 70, 80)
        )
        $now = [datetime]::UtcNow
        foreach ($folder in 'sub/deeper', '.hiddendir', 'sub2', 'linktarget') {
            [void] [System.IO.Directory]::CreateDirectory((Join-Path $Root $folder))
        }
        foreach ($file in $files) {
            $path = Join-Path $Root $file[0]
            [System.IO.File]::WriteAllBytes($path, [byte[]]::new($file[1]))
            [System.IO.File]::SetLastWriteTimeUtc($path, $now.AddDays(-$file[2]))
        }
        if ($IsWindows) {
            # On Windows a file is hidden by its attribute, not by its name
            foreach ($hidden in '.hidden.log', '.hiddendir') {
                $item = Get-Item -LiteralPath (Join-Path $Root $hidden) -Force
                $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
            }
        }
        else {
            # A link to a folder: what is inside is found once, through the real folder
            New-Item -ItemType SymbolicLink -Path (Join-Path $Root 'dirlink') -Target (Join-Path $Root 'linktarget') | Out-Null
        }
    }

    function Get-TestTree {
        param([string] $Root)
        $prefix = $Root.TrimEnd('/', '\').Length + 1
        $names = @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]dirlink[\\/]' } | ForEach-Object { $_.FullName.Substring($prefix).Replace('\', '/') })
        return [string[]] @($names | Sort-Object -CaseSensitive)
    }

    # What a program printed, ready to compare: no root, no date, "/" in the paths, no last line of the dry run
    function Get-TestLine {
        param([string] $Output, [string] $Root)
        $lines = @($Output -split "\r?\n" | Where-Object { $_ -ne '' })
        $kept = foreach ($line in $lines) {
            if ($line -match '^Dry run: nothing was changed\. Add (--apply|-Apply) to really do it\.$') { continue }
            # The same separators on both sides first: Windows prints "\", the root may have been given with "/"
            $text = $line.Replace('\', '/').Replace($Root.Replace('\', '/'), '{R}')
            $text -replace "\t\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", ''
        }
        return [string[]] @($kept)
    }

    # The scenarios: the steps, what a dry run must print (the files in this order), and what --apply must change.
    # Every expectation was worked out by hand from the fixture above
    function Get-TestScenario {
        param([string] $Name, [string] $Root)

        $accent = 'accent' + [char] 0x00E9 + '.txt'
        $odd = 'it''s "odd" $x `y.md'
        if ($IsWindows) { $odd = 'it''s ''odd'' $x `y.md' }
        $tab = "`t"
        switch ($Name) {
            'list with filters' {
                # .log and .txt, strictly more than 100 bytes, not keep.log, largest first; 700 = 700 goes by path
                return @{
                    Steps   = @(@{ Action = 'files.list'; Path = $Root; Extension = @('.log', '.txt'); ExceptName = 'KEEP.log'; MinSize = 100; Order = 'largest' })
                    Lines   = @("{R}/big.txt${tab}5000", "{R}/b.log${tab}2000", "{R}/same1.txt${tab}700", "{R}/same2.txt${tab}700", "{R}/C.LOG${tab}300", "{R}/sub/deeper/y.log${tab}250", "{R}/sub/x.log${tab}150")
                    Removed = @(); Added = @()
                }
            }
            'list newest first' {
                # The two files of 2 days and the two of 3 days have the same date: they come by path
                return @{
                    Steps   = @(@{ Action = 'files.list'; Path = $Root; Extension = @('.txt'); Order = 'newest' })
                    Lines   = @("{R}/tiny.txt${tab}5", "{R}/$accent${tab}12", "{R}/sp ace [1].txt${tab}11", "{R}/same1.txt${tab}700", "{R}/same2.txt${tab}700", "{R}/notes.txt${tab}50", "{R}/sub/z.txt${tab}60", "{R}/big.txt${tab}5000")
                    Removed = @(); Added = @()
                }
            }
            'list the two oldest' {
                # old.jpg is 400 days old, archive.tar.gz (extension .gz) 70, photo.jpg 60
                return @{
                    Steps   = @(@{ Action = 'files.list'; Path = $Root; Extension = @('.jpg', '.gz'); Order = 'oldest'; Count = 2 })
                    Lines   = @("{R}/sub/deeper/old.jpg${tab}900", "{R}/archive.tar.gz${tab}800")
                    Removed = @(); Added = @()
                }
            }
            'list small recent files' {
                # At most 3 days old (the files of exactly 3 days are a moment too old), strictly less than 12 bytes
                return @{
                    Steps   = @(@{ Action = 'files.list'; Path = $Root; NewerThan = [timespan]::FromDays(3); MaxSize = 12; Order = 'smallest' })
                    Lines   = @("{R}/tiny.txt${tab}5", "{R}/$odd${tab}10", "{R}/sp ace [1].txt${tab}11")
                    Removed = @(); Added = @()
                }
            }
            'delete old logs' {
                # .log in any case, strictly older than 30 days, in the subfolders too, not the hidden ones, not keep.log
                return @{
                    Steps   = @(@{ Action = 'files.delete'; Path = $Root; Extension = @('.log'); OlderThan = [timespan]::FromDays(30); ExceptName = 'keep.log' })
                    Lines   = @('would delete: {R}/C.LOG', 'would delete: {R}/a.log', 'would delete: {R}/linktarget/inner.log', 'would delete: {R}/sub/deeper/y.log', 'would delete: {R}/sub/x.log')
                    Removed = @('C.LOG', 'a.log', 'linktarget/inner.log', 'sub/deeper/y.log', 'sub/x.log'); Added = @()
                }
            }
            'delete images but not png' {
                return @{
                    Steps   = @(@{ Action = 'files.delete'; Path = $Root; Kind = @('image'); ExceptExtension = @('.png') })
                    Lines   = @('would delete: {R}/photo.jpg', 'would delete: {R}/sub/deeper/old.jpg')
                    Removed = @('photo.jpg', 'sub/deeper/old.jpg'); Added = @()
                }
            }
            'delete the three largest' {
                return @{
                    Steps   = @(@{ Action = 'files.delete'; Path = $Root; Order = 'largest'; Count = 3 })
                    Lines   = @('would delete: {R}/big.txt', 'would delete: {R}/photo.jpg', 'would delete: {R}/b.log')
                    Removed = @('big.txt', 'photo.jpg', 'b.log'); Added = @()
                }
            }
            'free space' {
                # 7500 bytes: big.txt (5000) is not enough, photo.jpg (3000) makes 8000, then it stops
                return @{
                    Steps   = @(@{ Action = 'files.free'; Path = $Root; FreeSize = 7500 })
                    Lines   = @('would delete: {R}/big.txt', 'would delete: {R}/photo.jpg')
                    Removed = @('big.txt', 'photo.jpg'); Added = @()
                }
            }
            'copy into a folder' {
                # Only the folder itself, .txt, strictly less than 700 bytes
                return @{
                    Steps   = @(@{ Action = 'files.copy'; Source = $Root; Destination = "$Root/sub2"; Extension = @('.txt'); MaxSize = 700 })
                    Lines   = @("would copy: {R}/$accent -> {R}/sub2/$accent", 'would copy: {R}/notes.txt -> {R}/sub2/notes.txt', 'would copy: {R}/sp ace [1].txt -> {R}/sub2/sp ace [1].txt', 'would copy: {R}/tiny.txt -> {R}/sub2/tiny.txt')
                    Removed = @(); Added = @("sub2/$accent", 'sub2/notes.txt', 'sub2/sp ace [1].txt', 'sub2/tiny.txt')
                }
            }
            'copy one file to a new name' {
                return @{
                    Steps   = @(@{ Action = 'files.copy'; Source = "$Root/a.log"; Destination = "$Root/copy of a.bin" })
                    Lines   = @('would copy: {R}/a.log -> {R}/copy of a.bin')
                    Removed = @(); Added = @('copy of a.bin')
                }
            }
            'move by name' {
                # A name is the same in upper and lower case
                return @{
                    Steps   = @(@{ Action = 'files.move'; Source = $Root; Destination = "$Root/sub2"; Name = 'B.LOG' })
                    Lines   = @('would move: {R}/b.log -> {R}/sub2/b.log')
                    Removed = @('b.log'); Added = @('sub2/b.log')
                }
            }
            'rename' {
                return @{
                    Steps   = @(@{ Action = 'files.rename'; Name = "$Root/$odd"; NewName = 'new [1] $HOME.md' })
                    Lines   = @("would rename: {R}/$odd -> {R}/new [1] `$HOME.md")
                    Removed = @($odd); Added = @('new [1] $HOME.md')
                }
            }
            'create' {
                return @{
                    Steps   = @(
                        @{ Action = 'files.create'; Kind = 'Directory'; Path = "$Root/made/deep" }
                        @{ Action = 'files.create'; Kind = 'File'; Parent = $Root; Name = 'empty file.txt' }
                    )
                    Lines   = @('would create folder: {R}/made/deep', 'would create file: {R}/empty file.txt')
                    Removed = @(); Added = @('made', 'made/deep', 'empty file.txt')
                }
            }
        }
        throw "No scenario '$Name'."
    }
}

Describe 'ConvertTo-LambekCodeModel' {

    It 'reads "list the 3 largest images": every image extension, in the subfolders, the 3 largest' {
        $step = Get-TestStep -Text 'list the 3 largest images in /tmp/x'
        $images = InModuleScope Lambek { @(Get-LambekKindExtension -Kind 'image' | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique) }
        $step.Operation | Should -Be 'list'
        $step.Root | Should -Be '/tmp/x'
        $step.Recurse | Should -BeTrue
        $step.Extensions | Should -Contain '.jpg'
        $step.Extensions | Should -Contain '.png'
        $step.Extensions.Count | Should -Be $images.Count
        $step.Order | Should -Be 'largest'
        $step.Count | Should -Be 3
        $step.Supported | Should -BeTrue
    }

    It 'reads "delete the .log files older than 30 days": 30 x 86400 = 2592000 seconds, in the subfolders' {
        $step = Get-TestStep -Text 'delete the .log files older than 30 days in C:\Temp'
        $step.Operation | Should -Be 'delete'
        $step.Root | Should -Be 'C:\Temp'
        $step.Recurse | Should -BeTrue
        $step.Extensions | Should -Be @('.log')
        $step.OlderThanSeconds | Should -Be 2592000
        $step.NewerThanSeconds | Should -BeNullOrEmpty
        $step.Sentence | Should -Be 'delete the .log files older than 30 days in C:\Temp'
    }

    It 'reads "copy the .txt files": only the folder itself, like Get-ChildItem -File without -Recurse' {
        $step = Get-TestStep -Text 'copy the .txt files from /tmp/a to /tmp/b'
        $step.Operation | Should -Be 'copy'
        $step.Root | Should -Be '/tmp/a'
        $step.Destination | Should -Be '/tmp/b'
        $step.Recurse | Should -BeFalse
        $step.Extensions | Should -Be @('.txt')
    }

    It 'reads "move the files larger than 1 MB": 1024 x 1024 = 1048576 bytes' {
        $step = Get-TestStep -Text 'move the files larger than 1 MB from /tmp/a to /tmp/b'
        $step.Operation | Should -Be 'move'
        $step.MinSize | Should -Be 1048576
        $step.Extensions | Should -BeNullOrEmpty
        $step.Destination | Should -Be '/tmp/b'
    }

    It 'reads a rename and a creation' {
        $rename = Get-TestStep -Text 'rename /tmp/a/report.txt to final.txt'
        $rename.Operation | Should -Be 'rename'
        $rename.Source | Should -Be '/tmp/a/report.txt'
        $rename.NewName | Should -Be 'final.txt'

        $create = Get-TestStep -Text 'create a folder /tmp/a/new'
        $create.Operation | Should -Be 'create'
        $create.Kind | Should -Be 'Directory'
        $create.Path | Should -Be '/tmp/a/new'
    }

    It 'reads "free 2 GB": a deletion for good of the largest files until 2 x 1024^3 = 2147483648 bytes' {
        $step = Get-TestStep -Text 'free 2 GB in /tmp/a'
        $step.Operation | Should -Be 'delete'
        $step.Order | Should -Be 'largest'
        $step.FreeBytes | Should -Be 2147483648
        $step.Recurse | Should -BeTrue
        $step.Permanent | Should -BeTrue
    }

    It 'keeps "except" apart from the extensions asked' {
        $model = New-TestModel -Steps @(@{ Action = 'files.list'; Path = '/tmp/x'; Extension = @('.TXT', '.log'); ExceptExtension = @('.Log'); ExceptName = 'keep.txt' })
        $model.Steps[0].Extensions | Should -Be @('.log', '.txt')
        $model.Steps[0].ExceptExtensions | Should -Be @('.log')
        $model.Steps[0].ExceptName | Should -Be 'keep.txt'
    }

    It 'rounds a size to whole bytes the safe way: more than 307.2 is more than 307, less than 307.2 is less than 308' {
        $model = New-TestModel -Steps @(@{ Action = 'files.list'; Path = '/tmp/x'; MinSize = 307.2; MaxSize = 307.2 })
        $model.Steps[0].MinSize | Should -Be 307
        $model.Steps[0].MaxSize | Should -Be 308
    }

    It 'joins the parent and the name of a creation with the separator of the parent' {
        $model = New-TestModel -Steps @(
            @{ Action = 'files.create'; Kind = 'File'; Parent = 'C:\Temp'; Name = 'a.txt' }
            @{ Action = 'files.create'; Kind = 'File'; Parent = '/tmp/x'; Name = 'a.txt' }
        )
        $model.Steps[0].Path | Should -Be 'C:\Temp\a.txt'
        $model.Steps[1].Path | Should -Be '/tmp/x/a.txt'
    }

    It 'refuses what cannot be a program: <Action>' -ForEach @(
        @{ Action = 'files.restore'; Reason = '*trash*' }
        @{ Action = 'notes.search'; Reason = '*no code model*' }
    ) {
        $model = New-TestModel -Steps @(@{ Action = $Action; Path = '/tmp/x' })
        $model.Steps[0].Supported | Should -BeFalse
        $model.Steps[0].Reason | Should -BeLike $Reason
        $model.Steps[0].Operation | Should -Be 'none'
    }

    It 'refuses a path with a line break' {
        $model = New-TestModel -Steps @(@{ Action = 'files.delete'; Path = "/tmp/x`nrm -rf ~" })
        $model.Steps[0].Supported | Should -BeFalse
        $model.Steps[0].Reason | Should -BeLike '*line break*'
    }
}

Describe 'ConvertTo-LambekCodeLiteral' {

    BeforeAll {
        # Hostile values: quotes, dollars, backticks, backslashes, an apostrophe, letters outside ASCII, a tab,
        # an invisible character, a character outside the first plane
        $values = @(
            'C:\My "odd" $dir\it''s'
            'a`b ``c'
            '$(rm -rf ~) ${HOME} %s %d \n \t \\'
            ('caf' + [char] 0x00E9 + ' ' + [char] 0x65E5 + [char] 0x672C)
            "tab`there"
            ('zero' + [char] 0x200B + 'width')
            ('smile ' + [char]::ConvertFromUtf32(0x1F600))
            ([string] [char] 0x201C + 'curly' + [char] 0x201D + ' ' + [char] 0x2018 + 'single' + [char] 0x2019)
            '\\server\share\'
            ''
            '-rf'
            "'; exit 1; '"
            '"); process.exit(1); ("'
        )
    }

    It 'gives back the same text when PowerShell reads its literal' {
        foreach ($value in $values) {
            $literal = Get-TestLiteral -Value $value -Language PowerShell
            $tokens = $null
            $errors = $null
            $tree = [System.Management.Automation.Language.Parser]::ParseInput($literal, [ref] $tokens, [ref] $errors)
            $errors.Count | Should -Be 0 -Because $literal
            # One constant string and nothing else: no variable, no sub-expression
            $nodes = @($tree.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExpressionAst] }, $true))
            $nodes.Count | Should -Be 1 -Because $literal
            $nodes[0] | Should -BeOfType ([System.Management.Automation.Language.StringConstantExpressionAst])
            $nodes[0].Value | Should -BeExactly $value
        }
    }

    It 'gives back the same text when C# reads its literal' {
        Test-LambekCodeSyntax -Code 'class A { }' -Language CSharp | Out-Null
        foreach ($value in $values) {
            $literal = Get-TestLiteral -Value $value -Language CSharp
            $expression = [Microsoft.CodeAnalysis.CSharp.SyntaxFactory]::ParseExpression($literal)
            @($expression.GetDiagnostics()).Count | Should -Be 0 -Because $literal
            $expression.Token.ValueText | Should -BeExactly $value
        }
    }

    It 'gives back the same text when <Language> runs its literal<Why>' -ForEach @($backends | Where-Object { $_.Language -in 'Python', 'JavaScript', 'Bash', 'Rust' }) {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $literals = @($values | ForEach-Object { Get-TestLiteral -Value $_ -Language $Language })
        $folder = Join-Path $TestDrive "literal-$Language"
        # Each program prints every value followed by a zero byte (JSON for Python and JavaScript)
        switch ($Language) {
            'Python' { $code = "import json, sys`nsys.stdout.buffer.write(json.dumps([" + ($literals -join ', ') + "]).encode('utf-8'))`n" }
            'JavaScript' { $code = "process.stdout.write(JSON.stringify([" + ($literals -join ', ') + "]));`n" }
            'Bash' { $code = "printf '%s\0' " + ($literals -join ' ') + "`n" }
            'Rust' { $code = "fn main() {`n    for value in [" + ($literals -join ', ') + "] {`n        print!(`"{}\0`", value);`n    }`n}`n" }
        }
        $run = Invoke-TestProgram -Language $Language -Code $code -Folder $folder
        $run.ExitCode | Should -Be 0 -Because $run.Error
        if ($Language -in 'Python', 'JavaScript') { $read = @($run.Output | ConvertFrom-Json) }
        else { $read = @($run.Output.Substring(0, $run.Output.Length - 1) -split [string] [char] 0) }
        $read.Count | Should -Be $values.Count
        for ($i = 0; $i -lt $values.Count; $i++) { $read[$i] | Should -BeExactly $values[$i] }
    }

    It 'refuses a line break in <Language>' -ForEach $backends {
        { Get-TestLiteral -Value "a`nb" -Language $Language } | Should -Throw '*line break*'
        { Get-TestLiteral -Value "a`rb" -Language $Language } | Should -Throw '*line break*'
    }

    It 'keeps a comment on one line' {
        $comment = InModuleScope Lambek { ConvertTo-LambekCodeComment -Text "list files`nimport os; os.system('x')`r`n*/ done" }
        $comment | Should -Not -Match "[`r`n]"
        $comment | Should -Be "list files import os; os.system('x') */ done"
    }

    It 'never ends a C# or Rust or JavaScript comment early: the header only uses line comments' {
        $model = New-TestModel -Steps @(@{ Action = 'files.list'; Path = '/tmp/*/ x' })
        $model.Original = 'evil */ request'
        foreach ($language in 'CSharp', 'Rust', 'JavaScript') {
            (Get-TestCode -Model $model -Language $language) | Should -Not -Match '(?m)^\s*/\*'
        }
    }
}

Describe 'Test-LambekCodeSyntax' {

    It 'accepts a valid <Language> program<Why>' -ForEach $backends {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $valid = @{
            PowerShell = 'Get-ChildItem | Where-Object { $_.Length -gt 1 }'
            Python     = "def f():`n    return 1`n"
            JavaScript = 'function f() { return 1; }'
            CSharp     = 'class Program { static int Main(string[] args) { return 0; } }'
            Rust       = 'fn main() { println!("ok"); }'
            Bash       = 'if [ -n "$1" ]; then echo ok; fi'
        }
        $result = Test-LambekCodeSyntax -Code $valid[$Language] -Language $Language
        $result.Checked | Should -BeTrue
        $result.Valid | Should -BeTrue
        $result.Errors.Count | Should -Be 0
        $result.Tool | Should -Not -BeNullOrEmpty
    }

    It 'finds the error of a broken <Language> program<Why>' -ForEach $backends {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $broken = @{
            PowerShell = 'if ($true) { '
            Python     = "def f(:`n    return 1`n"
            JavaScript = 'function f() { return 1; '
            CSharp     = 'class Program { static int Main(string[] args) { return 0; }'
            Rust       = 'fn main() { println!("ok") '
            Bash       = 'if [ -n "$1" ]; then echo ok'
        }
        $result = Test-LambekCodeSyntax -Code $broken[$Language] -Language $Language
        $result.Checked | Should -BeTrue
        $result.Valid | Should -BeFalse
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It 'never runs the program it checks<Why>' -ForEach @($backends | Where-Object { $_.Language -in 'Python', 'JavaScript', 'Bash' }) {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $marker = Join-Path $TestDrive "ran-$Language.txt"
        $quoted = Get-TestLiteral -Value $marker -Language $Language
        $programs = @{
            Python     = "open($quoted, 'w').close()`n"
            JavaScript = "require('fs').writeFileSync($quoted, '');`n"
            Bash       = ": > $quoted`n"
        }
        (Test-LambekCodeSyntax -Code $programs[$Language] -Language $Language).Valid | Should -BeTrue
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'claims nothing when the tool is not installed' {
        $old = $env:PATH
        try {
            $env:PATH = Join-Path $TestDrive 'no-tools-here'
            foreach ($language in 'Python', 'JavaScript', 'Rust', 'Bash') {
                $result = Test-LambekCodeSyntax -Code 'x' -Language $language
                $result.Checked | Should -BeFalse
                $result.Valid | Should -BeFalse
                $result.Message | Should -BeLike '*not installed*'
            }
        }
        finally { $env:PATH = $old }
    }

    It 'understands the usual names of a language and refuses an unknown one' {
        (Test-LambekCodeSyntax -Code '1' -Language 'pwsh').Language | Should -Be 'PowerShell'
        (Test-LambekCodeSyntax -Code 'class A { }' -Language 'C#').Language | Should -Be 'CSharp'
        { Test-LambekCodeSyntax -Code '1' -Language 'cobol' } | Should -Throw '*not one of*'
    }

    It 'leaves no temporary folder behind<Why>' -ForEach @($backends | Where-Object { $_.Language -in 'JavaScript', 'Rust' }) {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $before = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'lambek-code-*' -Directory).Count
        Test-LambekCodeSyntax -Code 'fn main() {' -Language $Language | Out-Null
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'lambek-code-*' -Directory).Count | Should -Be $before
    }

    It 'writes valid <Language> for "<Text>"<Why>' -ForEach $syntaxCases {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $code = ConvertTo-LambekCode -Plan (Get-TestPlan -Text $Text) -Language $Language
        $code.Unsupported.Count | Should -Be 0
        $code.Syntax.Checked | Should -BeTrue
        $code.Syntax.Errors | Should -BeNullOrEmpty
        $code.Syntax.Valid | Should -BeTrue
    }
}

Describe 'ConvertTo-LambekCode' {

    It 'returns the program, a file name, the syntax check and no refused step' {
        $code = ConvertTo-LambekCode -Plan (Get-TestPlan -Text 'delete the .log files older than 30 days in C:\Temp') -Language python
        $code.Language | Should -Be 'Python'
        $code.FileName | Should -Be 'lambek_task.py'
        $code.Unsupported.Count | Should -Be 0
        $code.Syntax.Language | Should -Be 'Python'
        $code.Code | Should -BeLike '#!/usr/bin/env python3*'
    }

    It 'says in the header what was asked, what each step does, that it is a dry run and that a deletion is real (<Language>)' -ForEach $backends {
        $code = (ConvertTo-LambekCode -Plan (Get-TestPlan -Text 'delete the .log files older than 30 days in C:\Temp') -Language $Language -SkipSyntax).Code
        $header = @($code -split "`n" | Select-Object -First 12) -join "`n"
        $header | Should -BeLike '*Written by Lambek from this request:*delete the .log files older than 30 days in C:\Temp*'
        $header | Should -BeLike '*Step 1: delete the .log files older than 30 days in C:\Temp*'
        $header | Should -BeLike '*Dry run by default*'
        $header | Should -BeLike '*really deleted: no trash, no undo*'
        $code | Should -Not -Match "`r"
    }

    It 'writes the same text every time (<Language>)' -ForEach $backends {
        $plan = Get-TestPlan -Text 'list the 3 largest images in /tmp/x'
        $first = (ConvertTo-LambekCode -Plan $plan -Language $Language -SkipSyntax).Code
        $second = (ConvertTo-LambekCode -Plan $plan -Language $Language -SkipSyntax).Code
        $second | Should -BeExactly $first
    }

    It 'keeps a Windows path as it was typed in every language that runs on Windows' {
        $plan = Get-TestPlan -Text 'delete the .log files older than 30 days in C:\Temp'
        (ConvertTo-LambekCode -Plan $plan -Language PowerShell -SkipSyntax).Code | Should -BeLike "*Root = 'C:\Temp'*"
        (ConvertTo-LambekCode -Plan $plan -Language Python -SkipSyntax).Code | Should -BeLike '*"C:\\Temp",*'
        (ConvertTo-LambekCode -Plan $plan -Language JavaScript -SkipSyntax).Code | Should -BeLike '*selectFiles("C:\\Temp", {*'
        (ConvertTo-LambekCode -Plan $plan -Language CSharp -SkipSyntax).Code | Should -BeLike '*SelectFiles("C:\\Temp", filter)*'
        (ConvertTo-LambekCode -Plan $plan -Language Rust -SkipSyntax).Code | Should -BeLike '*select_files("C:\\Temp", &filter)*'
        $bash = ConvertTo-LambekCode -Plan $plan -Language Bash -SkipSyntax
        $bash.Code | Should -BeLike "*select_files 'C:\Temp'*"
        $bash.Notes | Should -BeLike '*Windows paths*'
    }

    It 'refuses a plan that is not ready' {
        $plan = Get-TestPlan -Text 'delete the .log files'
        $plan.Status | Should -Not -Be 'Ready'
        { ConvertTo-LambekCode -Plan $plan -Language Python } | Should -Throw '*Only a ready plan*'
    }

    It 'refuses an unknown language' {
        { ConvertTo-LambekCode -Plan (Get-TestPlan -Text 'free 2 GB in /tmp/a') -Language 'cobol' } | Should -Throw '*not one of*'
    }

    It 'gives no code for a step that cannot be a program, and says which one' {
        $plan = Get-TestPlan -Text 'restore the deleted files'
        $plan.Status | Should -Be 'Ready'
        $code = ConvertTo-LambekCode -Plan $plan -Language Bash
        $code.Code | Should -BeNullOrEmpty
        $code.Syntax | Should -BeNullOrEmpty
        $code.Unsupported.Count | Should -Be 1
        $code.Unsupported[0].Step | Should -Be 1
        $code.Unsupported[0].Action | Should -Be 'files.restore'
        $code.Unsupported[0].Reason | Should -BeLike '*trash*'
    }

    It 'gives no code for a plan that already is code' {
        $code = ConvertTo-LambekCode -Plan (Get-TestPlan -Text 'generate a powershell function named Get-Report') -Language Python
        $code.Code | Should -BeNullOrEmpty
        $code.Unsupported[0].Reason | Should -BeLike '*already is code*'
    }
}

Describe 'The generated programs' {

    It '<Scenario>: <Language> picks exactly the expected files, changes nothing in a dry run, and does it with the switch<Why>' -ForEach $behaviourCases {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $program = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-TestFixture -Root $root
        $scenario = Get-TestScenario -Name $Scenario -Root $root
        $code = Get-TestCode -Model (New-TestModel -Steps $scenario.Steps) -Language $Language
        $before = Get-TestTree -Root $root
        $changes = ($scenario.Removed.Count + $scenario.Added.Count) -gt 0

        # Dry run: the right files in the right order, and nothing changed
        $dry = Invoke-TestProgram -Language $Language -Code $code -Folder $program
        $dry.Error | Should -BeNullOrEmpty
        $dry.ExitCode | Should -Be 0
        if ($IsWindows -and $Language -eq 'JavaScript' -and $dry.Output -match '[\\/]\.hidden') {
            Set-ItResult -Skipped -Because 'Node cannot read the hidden attribute of Windows (the header of the program says so)'
            return
        }
        Get-TestLine -Output $dry.Output -Root $root | Should -BeExactly $scenario.Lines
        Get-TestTree -Root $root | Should -BeExactly $before
        if ($changes) { $dry.Output | Should -Match 'Dry run: nothing was changed' }

        # For real: the same files, and the folder is exactly what was expected
        $applied = Invoke-TestProgram -Language $Language -Code $code -Folder $program -Apply
        $applied.Error | Should -BeNullOrEmpty
        $applied.ExitCode | Should -Be 0
        $done = @($scenario.Lines | ForEach-Object { $_ -replace '^would delete: ', 'deleted: ' -replace '^would copy: ', 'copied: ' -replace '^would move: ', 'moved: ' -replace '^would rename: ', 'renamed: ' -replace '^would create ', 'created ' })
        Get-TestLine -Output $applied.Output -Root $root | Should -BeExactly $done
        $expected = [string[]] @(@($before | Where-Object { $_ -notin $scenario.Removed }) + @($scenario.Added) | Sort-Object -CaseSensitive)
        Get-TestTree -Root $root | Should -BeExactly $expected

        # A copy keeps the size and the date of the original
        if ($Scenario -eq 'copy into a folder') {
            $original = Get-Item -LiteralPath (Join-Path $root 'notes.txt')
            $copy = Get-Item -LiteralPath (Join-Path $root 'sub2/notes.txt')
            $copy.Length | Should -Be 50
            [math]::Abs(($copy.LastWriteTimeUtc - $original.LastWriteTimeUtc).TotalSeconds) | Should -BeLessThan 2
        }
    }

    It 'stops with an error, a code that is not 0 and nothing changed (<Language>)<Why>' -ForEach $backends {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-TestFixture -Root $root
        $before = Get-TestTree -Root $root

        # A folder that does not exist: an error even in a dry run
        $missing = Get-TestCode -Model (New-TestModel -Steps @(@{ Action = 'files.list'; Path = "$root/nowhere" })) -Language $Language
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $run = Invoke-TestProgram -Language $Language -Code $missing -Folder $folder
        $run.ExitCode | Should -Not -Be 0
        $run.Error | Should -Match '^error: '
        $run.Output | Should -BeNullOrEmpty

        # An argument that is not the switch: refused, nothing is done
        $delete = Get-TestCode -Model (New-TestModel -Steps @(@{ Action = 'files.delete'; Path = $root; Extension = @('.log') })) -Language $Language
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $run = Invoke-TestProgram -Language $Language -Code $delete -Folder $folder -Extra @('--force')
        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -Not -Match 'deleted'
        Get-TestTree -Root $root | Should -BeExactly $before

        # Several files to a folder that does not exist: a warning in the dry run, an error for real
        $copy = Get-TestCode -Model (New-TestModel -Steps @(@{ Action = 'files.copy'; Source = $root; Destination = "$root/nowhere"; Extension = @('.txt') })) -Language $Language
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $run = Invoke-TestProgram -Language $Language -Code $copy -Folder $folder
        $run.ExitCode | Should -Be 0
        $run.Error | Should -Match '^warning: '
        $run = Invoke-TestProgram -Language $Language -Code $copy -Folder $folder -Apply
        $run.ExitCode | Should -Not -Be 0
        $run.Error | Should -Match '^error: .*is not an existing folder'
        Get-TestTree -Root $root | Should -BeExactly $before

        # A move never replaces a file that is already there
        [System.IO.File]::WriteAllText((Join-Path $root 'sub2/b.log'), 'already here')
        $move = Get-TestCode -Model (New-TestModel -Steps @(@{ Action = 'files.move'; Source = $root; Destination = "$root/sub2"; Name = 'b.log' })) -Language $Language
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $run = Invoke-TestProgram -Language $Language -Code $move -Folder $folder -Apply
        $run.ExitCode | Should -Not -Be 0
        $run.Error | Should -Match '^error: .*already exists'
        (Get-Item -LiteralPath (Join-Path $root 'b.log')).Length | Should -Be 2000
        [System.IO.File]::ReadAllText((Join-Path $root 'sub2/b.log')) | Should -Be 'already here'
    }

    It 'runs the steps of a plan in order (<Language>)<Why>' -ForEach $backends {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        # Three steps that need each other: the folder is made, filled, then listed
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-TestFixture -Root $root
        $root = $root.Replace('\', '/')
        $model = New-TestModel -Steps @(
            @{ Action = 'files.create'; Kind = 'Directory'; Path = "$root/archive" }
            @{ Action = 'files.move'; Source = $root; Destination = "$root/archive"; Extension = @('.log'); OlderThan = [timespan]::FromDays(30) }
            @{ Action = 'files.list'; Path = "$root/archive" }
        )
        $code = Get-TestCode -Model $model -Language $Language
        $run = Invoke-TestProgram -Language $Language -Code $code -Folder (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Apply
        $run.Error | Should -BeNullOrEmpty
        $run.ExitCode | Should -Be 0
        if ($IsWindows -and $Language -eq 'JavaScript' -and $run.Output -match '[\\/]\.hidden') {
            Set-ItResult -Skipped -Because 'Node cannot read the hidden attribute of Windows (the header of the program says so)'
            return
        }
        # In the folder itself: C.LOG (31 days), a.log (40) and keep.log (50) are older than 30 days, b.log (10) is not
        $tab = "`t"
        Get-TestLine -Output $run.Output -Root $root | Should -BeExactly @(
            'created folder: {R}/archive'
            'moved: {R}/C.LOG -> {R}/archive/C.LOG', 'moved: {R}/a.log -> {R}/archive/a.log', 'moved: {R}/keep.log -> {R}/archive/keep.log'
            "{R}/archive/C.LOG${tab}300", "{R}/archive/a.log${tab}100", "{R}/archive/keep.log${tab}500"
        )
    }

    It 'does what the sentence asks, from the request to the files (Python)<Why>' -ForEach @($backends | Where-Object { $_.Language -eq 'Python' }) {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        $root = (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))).Replace('\', '/')
        New-TestFixture -Root $root
        $plan = New-LambekPlan -Text "delete the .log files older than 30 days in $root"
        $plan.Status | Should -Be 'Ready'
        $code = ConvertTo-LambekCode -Plan $plan -Language Python
        $code.Syntax.Valid | Should -BeTrue
        $run = Invoke-TestProgram -Language Python -Code $code.Code -Folder (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Apply
        $run.ExitCode | Should -Be 0
        # keep.log (50 days) goes too this time; b.log (10 days) and the hidden ones stay
        $left = @(Get-TestTree -Root $root | Where-Object { $_ -match '\.log$' })
        $left.Count | Should -Be 3
        $left | Should -Contain '.hidden.log'
        $left | Should -Contain '.hiddendir/in.log'
        $left | Should -Contain 'b.log'
    }
}

Describe 'Exporting a plan from the chat' {

    BeforeAll {
        $french = Get-TestPlan -Text 'supprime les .log de plus de 30 jours dans C:\Temp'
        $english = Get-TestPlan -Text 'delete the .log files older than 30 days in C:\Temp'
    }

    It 'answers "<Text>" with the <Language> program (French plan)' -ForEach @(
        @{ Text = 'en python'; Language = 'Python'; Fence = 'python' }
        @{ Text = 'donne-moi le script en rust'; Language = 'Rust'; Fence = 'rust' }
        @{ Text = 'montre-moi ca en C#'; Language = 'CSharp'; Fence = 'csharp' }
        @{ Text = 'ecris-le en javascript'; Language = 'JavaScript'; Fence = 'javascript' }
        @{ Text = 'et en bash ?'; Language = 'Bash'; Fence = 'bash' }
    ) {
        $result = Resolve-LambekFollowUp -Plan $french -Text $Text
        $result.Kind | Should -Be 'explain'
        $result.Code.Language | Should -Be $Language
        [object]::ReferenceEquals($result.Plan, $french) | Should -BeTrue
        $lines = @($result.Answer -split "`n")
        $lines[0] | Should -BeLike 'Voici le plan sous forme de programme*'
        $lines[1] | Should -Be ('```' + $Fence)
        $result.Answer | Should -BeLike '*supprimer les fichiers .log de plus de 30 jours dans C:\Temp*'
        # One line says whether the syntax was checked and by which tool, or that it was not
        if ($result.Code.Syntax.Checked) { $result.Answer | Should -BeLike "*Syntaxe v*rifi*e avec $($result.Code.Syntax.Tool) : aucune erreur.*" }
        else { $result.Answer | Should -BeLike '*Syntaxe non v*rifi*e*' }
        $result.Answer | Should -BeLike '*--apply*'
        $result.Answer | Should -BeLike '*supprime d*finitivement*'
    }

    It 'answers "<Text>" with the <Language> program (English plan)' -ForEach @(
        @{ Text = 'show me this in bash'; Language = 'Bash' }
        @{ Text = 'in python please'; Language = 'Python' }
        @{ Text = 'can I have it in powershell?'; Language = 'PowerShell' }
        @{ Text = 'convert it to node.js'; Language = 'JavaScript' }
        @{ Text = 'write the script in c sharp'; Language = 'CSharp' }
    ) {
        $result = Resolve-LambekFollowUp -Plan $english -Text $Text
        $result.Kind | Should -Be 'explain'
        $result.Code.Language | Should -Be $Language
        $result.Answer | Should -BeLike 'Here is the plan as a * program (*):*'
        $result.Answer | Should -Match 'Syntax (checked with .+: no error\.|not checked)'
        $result.Answer | Should -BeLike '*it deletes for good*'
    }

    It 'understands "<Text>" in <Spoken>' -ForEach @(
        @{ Spoken = 'Spanish'; Text = 'en JavaScript por favor'; Language = 'JavaScript' }
        @{ Spoken = 'German'; Text = 'als Python-Skript'; Language = 'Python' }
        @{ Spoken = 'Italian'; Text = 'mostramelo in rust'; Language = 'Rust' }
        @{ Spoken = 'Dutch'; Text = 'geef me het script in bash'; Language = 'Bash' }
        @{ Spoken = 'Portuguese'; Text = 'mostra isto em python'; Language = 'Python' }
    ) {
        $asked = InModuleScope Lambek -Parameters @{ Text = $Text } { Get-LambekCodeAsk -Text $Text }
        $asked.Language | Should -Be $Language
        $asked.Inner | Should -BeNullOrEmpty
    }

    It 'answers in <Spoken> for a plan made in <Spoken>' -ForEach @(
        @{ Spoken = 'Spanish'; Request = 'elimina los archivos .tmp de C:\Temp'; Text = 'en JavaScript por favor'; Start = 'Aqu* est* el plan como programa en JavaScript*' }
        @{ Spoken = 'German'; Request = 'zeige die dateien in C:\Temp'; Text = 'als Python-Skript'; Start = 'Hier ist der Plan als Python-Programm*' }
    ) {
        $plan = Get-TestPlan -Text $Request
        $plan.Status | Should -Be 'Ready'
        $result = Resolve-LambekFollowUp -Plan $plan -Text $Text
        $result.Kind | Should -Be 'explain'
        $result.Answer | Should -BeLike $Start
    }

    It 'does not take "<Text>" for a request to export' -ForEach @(
        @{ Text = 'write a python script' }
        @{ Text = 'ecris un script python' }
        @{ Text = 'generate a python function named Get-Data' }
        @{ Text = 'delete the .py files in C:\Temp' }
        @{ Text = 'list the python files in /tmp' }
        @{ Text = 'use .js instead' }
        @{ Text = 'in D:\rust' }
        @{ Text = 'python or rust' }
        @{ Text = 'explain' }
        @{ Text = 'yes' }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text } { Get-LambekCodeAsk -Text $Text } | Should -BeNullOrEmpty
    }

    It 'still starts new code with "write a python script"' {
        $result = Resolve-LambekFollowUp -Plan $english -Text 'write a python script'
        $result.Kind | Should -Be 'new'
        $result.Plan.Steps[0].Action | Should -Be 'code.generate'
        $result.Plan.Steps[0].Parameters.Language | Should -Be 'Python'
    }

    It 'changes the language of a plan that already is code instead of exporting it' {
        $result = Resolve-LambekFollowUp -Plan (Get-TestPlan -Text 'generate a python function named Get-Data') -Text 'in rust'
        $result.Kind | Should -Be 'edit'
        $result.Plan.Steps[0].Parameters.Language | Should -Be 'Rust'
        $result.Plan.Steps[0].Script | Should -BeLike 'fn get_data() {*'
    }

    It 'says so when the plan is not complete yet' {
        $result = Resolve-LambekFollowUp -Plan (Get-TestPlan -Text 'delete the .log files') -Text 'in python'
        $result.Kind | Should -Be 'explain'
        $result.Code | Should -BeNullOrEmpty
        $result.Answer | Should -Be 'The plan is not complete yet, so I cannot write it as a program.'
    }

    It 'says which step cannot be a program' {
        $result = Resolve-LambekFollowUp -Plan (Get-TestPlan -Text 'restore the deleted files') -Text 'in python'
        $result.Kind | Should -Be 'explain'
        $result.Answer | Should -BeLike 'I cannot write step 1 as a program:*trash*'
        $result.Answer | Should -Not -Match '```'
    }

    It 'uses a longer fence when a path holds backticks' {
        $code = [pscustomobject]@{ Language = 'Bash'; Code = "echo '````````'`n"; FileName = 'x.sh'; Syntax = $null; Unsupported = @(); Notes = @() }
        $answer = InModuleScope Lambek -Parameters @{ Code = $code; Plan = $english } { Format-LambekCodeAnswer -Code $Code -Plan $Plan }
        @($answer -split "`n")[1] | Should -Be '`````bash'
    }

    It 'writes the program of a whole task asked in one sentence: "<Text>"' -ForEach @(
        @{ Text = 'ecris un script python qui supprime les .log de plus de 30 jours dans C:\Temp'; Language = 'Python'; Action = 'files.delete'; Start = 'Voici le plan*' }
        @{ Text = 'write a rust program to list the 3 largest files in /tmp/x'; Language = 'Rust'; Action = 'files.list'; Start = 'Here is the plan*' }
    ) {
        $result = InModuleScope Lambek -Parameters @{ Text = $Text } { Resolve-LambekCodeRequest -Text $Text }
        $result.Kind | Should -Be 'new'
        $result.Plan.Status | Should -Be 'Ready'
        $result.Plan.Steps[0].Action | Should -Be $Action
        $result.Code.Language | Should -Be $Language
        $result.Answer | Should -BeLike $Start
    }

    It 'reads the task of a one-sentence request with its own values' {
        $result = InModuleScope Lambek { Resolve-LambekCodeRequest -Text 'ecris un script python qui supprime les .log de plus de 30 jours dans C:\Temp' }
        $values = $result.Plan.Steps[0].Parameters
        $values['Path'] | Should -Be 'C:\Temp'
        $values['Extension'] | Should -Be '.log'
        $values['OlderThan'] | Should -Be ([timespan]::FromDays(30))
    }

    It 'leaves a one-sentence request it cannot plan to the normal pipeline' {
        InModuleScope Lambek { Resolve-LambekCodeRequest -Text 'write a python script that sings a song' } | Should -BeNullOrEmpty
    }

    It 'answers through the host: the program after a plan, and a whole task in one message' {
        $audit = Join-Path $TestDrive 'audit.jsonl'
        $send = {
            param([hashtable] $Request)
            $line = $Request | ConvertTo-Json -Depth 5 -Compress
            $json = InModuleScope Lambek -Parameters @{ Line = $line; AuditPath = $audit } { Invoke-LambekHostRequest -Line $Line -AuditPath $AuditPath }
            $json | ConvertFrom-Json -AsHashtable
        }
        $ask = & $send @{ id = 1; method = 'ask'; params = @{ text = 'delete the .log files older than 30 days in C:\Temp' } }
        $next = & $send @{ id = 2; method = 'ask'; params = @{ text = 'in bash'; context = $ask.result.id } }
        $next.result.kind | Should -Be 'explain'
        $next.result.answer | Should -BeLike 'Here is the plan as a Bash program*```bash*'

        $whole = & $send @{ id = 3; method = 'ask'; params = @{ text = 'write a python script that deletes the .log files older than 30 days in C:\Temp' } }
        $whole.result.kind | Should -Be 'new'
        $whole.result.answer | Should -BeLike 'Here is the plan as a Python program*```python*'
        $whole.result.id | Should -Not -BeNullOrEmpty
    }
}

Describe 'code.generate in six languages' {

    It 'writes a valid <Language> <Kind>, with and without a name<Why>' -ForEach $skeletonCases {
        if ($Missing) { Set-ItResult -Skipped -Because $Why.Trim(); return }
        foreach ($name in $null, 'Get-Report') {
            $values = [ordered]@{ Kind = $Kind; Language = $Language }
            if ($name) { $values['Name'] = $name }
            $code = InModuleScope Lambek -Parameters @{ Values = $values } {
                $action = (Get-LambekAction -Id 'code.generate').Action
                ConvertTo-LambekScript -Template $action.Templates[$Values['Kind']] -Parameters $Values
            }
            $code | Should -Not -BeNullOrEmpty
            # PowerShell cannot name a class with a hyphen: that one is refused by the plan, as before
            if ($Language -eq 'PowerShell' -and $Kind -eq 'Class' -and $name) { continue }
            $syntax = Test-LambekCodeSyntax -Code $code -Language $Language
            $syntax.Errors | Should -BeNullOrEmpty -Because $code
            $syntax.Valid | Should -BeTrue
        }
    }

    It 'writes the name the way the language does: <Style> of "<Name>" is <Expected>' -ForEach @(
        @{ Name = 'Get-Report'; Style = 'snake'; Expected = 'get_report' }
        @{ Name = 'Get-Report'; Style = 'camel'; Expected = 'getReport' }
        @{ Name = 'Get-Report'; Style = 'pascal'; Expected = 'GetReport' }
        @{ Name = 'my report 2'; Style = 'snake'; Expected = 'my_report_2' }
        @{ Name = 'HTTPServer'; Style = 'snake'; Expected = 'http_server' }
        @{ Name = 'parseLine'; Style = 'pascal'; Expected = 'ParseLine' }
        @{ Name = '2 fast'; Style = 'camel'; Expected = '_2Fast' }
        @{ Name = 'class'; Style = 'snake'; Expected = 'class_' }
        @{ Name = 'x; rm -rf ~'; Style = 'snake'; Expected = 'x_rm_rf' }
    ) {
        InModuleScope Lambek -Parameters @{ Name = $Name; Style = $Style } { ConvertTo-LambekCodeIdentifier -Name $Name -Style $Style } | Should -BeExactly $Expected
    }

    It 'drops the accents of a name and refuses a name without any letter or digit' {
        $name = 'R' + [char] 0x00E9 + 'sum' + [char] 0x00E9
        InModuleScope Lambek -Parameters @{ Name = $name } { ConvertTo-LambekCodeIdentifier -Name $Name -Style pascal } | Should -BeExactly 'Resume'
        { InModuleScope Lambek { ConvertTo-LambekCodeIdentifier -Name '---' -Style snake } } | Should -Throw '*not a valid name*'
    }

    It 'understands "<Text>"' -ForEach @(
        @{ Text = 'generate a javascript class named "Invoice"'; Kind = 'Class'; Language = 'JavaScript'; Code = 'class Invoice {*' }
        @{ Text = 'create a c# class named "Invoice"'; Kind = 'Class'; Language = 'CSharp'; Code = 'class Invoice*public Invoice()*' }
        @{ Text = 'write a node script'; Kind = 'Script'; Language = 'JavaScript'; Code = '#!/usr/bin/env node*' }
        @{ Text = 'ecris une fonction rust nommee "lire ligne"'; Kind = 'Function'; Language = 'Rust'; Code = 'fn lire_ligne() {*' }
        @{ Text = 'erstelle ein c# skript'; Kind = 'Script'; Language = 'CSharp'; Code = '*static int Main(string`[`] args)*' }
        @{ Text = 'genera una funcion js llamada "sumar"'; Kind = 'Function'; Language = 'JavaScript'; Code = 'function sumar() {*' }
        @{ Text = 'scrivi una funzione bash chiamata "pulisci log"'; Kind = 'Function'; Language = 'Bash'; Code = 'pulisci_log() {*' }
        @{ Text = 'schrijf een bash script'; Kind = 'Script'; Language = 'Bash'; Code = '#!/usr/bin/env bash*' }
        @{ Text = 'gera uma funcao rust chamada "somar"'; Kind = 'Function'; Language = 'Rust'; Code = 'fn somar() {*' }
    ) {
        $plan = Get-TestPlan -Text $Text
        $plan.Status | Should -Be 'Ready'
        $step = $plan.Steps[0]
        $step.Action | Should -Be 'code.generate'
        $step.Parameters['Kind'] | Should -Be $Kind
        $step.Parameters['Language'] | Should -Be $Language
        $step.Script | Should -BeLike $Code
        $step.Check.IsValid | Should -BeTrue
    }

    It 'still writes PowerShell when no language is named, exactly as before' {
        $step = (Get-TestPlan -Text 'generate a powershell function named Get-Report').Steps[0]
        $step.Script | Should -Be (@('function Get-Report {', '    [CmdletBinding()]', '    param()', '', '}') -join [Environment]::NewLine)
        (Get-TestPlan -Text 'write a script').Steps[0].Parameters['Language'] | Should -Be 'PowerShell'
    }

    It 'returns the code of another language without running it' {
        $plan = Get-TestPlan -Text 'generate a javascript class named "Invoice"'
        $result = Invoke-LambekPlan -Plan $plan -AuditPath (Join-Path $TestDrive 'code-audit.jsonl')
        $result.Steps[0].Status | Should -Be 'Completed'
        $result.Steps[0].Output[0] | Should -BeLike 'class Invoice {*'
    }
}
