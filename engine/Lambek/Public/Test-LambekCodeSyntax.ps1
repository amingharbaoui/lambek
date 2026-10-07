function Test-LambekCodeSyntax {
    <#
    .SYNOPSIS
        Checks the syntax of a program in PowerShell, Python, JavaScript, C#, Rust or Bash without running it.
    .DESCRIPTION
        PowerShell and C# are read by the parsers that ship with PowerShell. The others need their own tool
        (python3, node, rustc, bash): when it is not installed, Checked is false and nothing is claimed.
    .EXAMPLE
        Test-LambekCodeSyntax -Code 'print("hello")' -Language Python
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Code,

        [Parameter(Mandatory)]
        [string] $Language,

        # Each external tool is stopped after this long
        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 60
    )

    $known = Resolve-LambekCodeLanguage -Name $Language
    if (-not $known) {
        throw "Language '$Language' is not one of: $(@(Get-LambekCodeLanguage | ForEach-Object { $_.Name }) -join ', ')."
    }

    $checked = $false
    $tool = $null
    $errors = [System.Collections.Generic.List[string]]::new()
    $message = $null

    switch ($known.Name) {
        'PowerShell' {
            # The parser of PowerShell itself: nothing runs
            $tokens = $null
            $parseErrors = $null
            [void] [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref] $tokens, [ref] $parseErrors)
            foreach ($parseError in $parseErrors) { $errors.Add("line $($parseError.Extent.StartLineNumber): $($parseError.Message)") }
            $checked = $true
            $tool = 'PowerShell parser'
        }
        'CSharp' {
            # The C# compiler that ships inside PowerShell reads the text into a syntax tree: nothing is compiled or run
            try {
                if (-not ('Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree' -as [type])) {
                    [void] [System.Reflection.Assembly]::LoadFrom((Join-Path $PSHOME 'Microsoft.CodeAnalysis.dll'))
                    [void] [System.Reflection.Assembly]::LoadFrom((Join-Path $PSHOME 'Microsoft.CodeAnalysis.CSharp.dll'))
                }
                $tree = [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([string] $Code)
                foreach ($diagnostic in $tree.GetDiagnostics()) {
                    if ($diagnostic.Severity -ne [Microsoft.CodeAnalysis.DiagnosticSeverity]::Error) { continue }
                    $line = $diagnostic.Location.GetLineSpan().StartLinePosition.Line + 1
                    $errors.Add("line $($line): $($diagnostic.GetMessage([cultureinfo]::InvariantCulture))")
                }
                $checked = $true
                $tool = 'Roslyn (syntax only)'
            }
            catch {
                $message = "The C# parser of PowerShell could not be used: $($_.Exception.Message)"
            }
        }
        'Python' {
            # compile() builds the code object and stops there. The answer starts with a word of ours,
            # so a "python" that is only a shortcut to a store is not taken for a real one
            $program = Get-LambekCodeTool -Name 'python3', 'python'
            if (-not $program) { $message = 'python3 is not installed.' }
            else {
                $script = "import sys`ntry:`n    compile(sys.stdin.buffer.read().decode('utf-8'), 'program.py', 'exec')`n    print('LAMBEK-VALID')`nexcept (SyntaxError, ValueError) as error:`n    print('LAMBEK-ERROR line %s: %s' % (getattr(error, 'lineno', 0), getattr(error, 'msg', error)))`n"
                $run = Invoke-LambekCodeTool -FilePath $program -ArgumentList @('-c', $script) -InputText $Code -TimeoutSeconds $TimeoutSeconds
                $tool = 'python compile()'
                if ($run.Output -match '(?m)^LAMBEK-VALID') { $checked = $true }
                elseif ($run.Output -match '(?m)^LAMBEK-ERROR (?<text>.*)$') { $checked = $true; $errors.Add($Matches['text'].Trim()) }
                else { $message = "python did not answer: $($run.Error)".Trim() }
            }
        }
        'JavaScript' {
            $program = Get-LambekCodeTool -Name 'node', 'nodejs'
            if (-not $program) { $message = 'node is not installed.' }
            else {
                $folder = New-LambekCodeFolder
                try {
                    $file = Join-Path $folder 'program.js'
                    [System.IO.File]::WriteAllText($file, $Code, [System.Text.UTF8Encoding]::new($false))
                    $run = Invoke-LambekCodeTool -FilePath $program -ArgumentList @('--check', $file) -TimeoutSeconds $TimeoutSeconds
                    $tool = 'node --check'
                    if ($run.ExitCode -eq 0 -and -not $run.TimedOut) { $checked = $true }
                    elseif ($run.Error -match 'SyntaxError') {
                        $checked = $true
                        $errors.Add((Get-LambekCodeToolError -Text $run.Error -Folder $folder -Pattern 'SyntaxError'))
                    }
                    else { $message = "node did not answer: $($run.Error)".Trim() }
                }
                finally { Remove-LambekCodeFolder -Path $folder }
            }
        }
        'Bash' {
            # bash -n reads the script from its input and runs nothing
            $program = Get-LambekCodeTool -Name 'bash'
            if (-not $program) { $message = 'bash is not installed.' }
            else {
                $run = Invoke-LambekCodeTool -FilePath $program -ArgumentList @('-n') -InputText ($Code -replace "`r`n", "`n") -TimeoutSeconds $TimeoutSeconds
                $tool = 'bash -n'
                if ($run.ExitCode -eq 0 -and -not $run.TimedOut) { $checked = $true }
                elseif ($run.Error -match 'syntax error|unexpected') {
                    $checked = $true
                    foreach ($line in @($run.Error -split "`n" | Where-Object { $_ -match 'syntax error|unexpected' })) { $errors.Add($line.Trim()) }
                }
                else { $message = "bash did not answer: $($run.Error)".Trim() }
            }
        }
        'Rust' {
            # rustc stops after the checks (metadata only): no program is built. A text without main is read as a library
            $program = Get-LambekCodeTool -Name 'rustc'
            if (-not $program) { $message = 'rustc is not installed.' }
            else {
                $folder = New-LambekCodeFolder
                try {
                    $file = Join-Path $folder 'main.rs'
                    [System.IO.File]::WriteAllText($file, $Code, [System.Text.UTF8Encoding]::new($false))
                    $kind = 'lib'
                    if ($Code -match '\bfn\s+main\s*\(') { $kind = 'bin' }
                    $arguments = @('--edition', '2021', '--emit=metadata', '--crate-type', $kind, '--crate-name', 'program', '--color', 'never', '--out-dir', $folder, $file)
                    $run = Invoke-LambekCodeTool -FilePath $program -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds
                    $tool = 'rustc --emit=metadata'
                    if ($run.ExitCode -eq 0 -and -not $run.TimedOut) { $checked = $true }
                    elseif ($run.Error -match '(?m)^error') {
                        $checked = $true
                        foreach ($line in @($run.Error -split "`n" | Where-Object { $_ -match '^error' -and $_ -notmatch '^error: aborting' })) { $errors.Add($line.Trim()) }
                    }
                    else { $message = "rustc did not answer: $($run.Error)".Trim() }
                }
                finally { Remove-LambekCodeFolder -Path $folder }
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'Lambek.CodeSyntax'
        Language   = $known.Name
        Checked    = $checked
        Valid      = ($checked -and $errors.Count -eq 0)
        Tool       = $tool
        Errors     = $errors.ToArray()
        Message    = $message
    }
}

function Get-LambekCodeTool {
    param([string[]] $Name)

    # The first of the names that is a program on this machine
    foreach ($candidate in $Name) {
        $found = @(Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) { return $found[0].Source }
    }
    return $null
}

function New-LambekCodeFolder {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A private temporary folder, removed right after the check.')]
    param()

    $folder = Join-Path ([System.IO.Path]::GetTempPath()) "lambek-code-$([guid]::NewGuid().ToString('N'))"
    [void] [System.IO.Directory]::CreateDirectory($folder)
    return $folder
}

function Remove-LambekCodeFolder {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only removes the temporary folder made by New-LambekCodeFolder.')]
    param([string] $Path)

    try {
        if ([System.IO.Directory]::Exists($Path)) { [System.IO.Directory]::Delete($Path, $true) }
    }
    catch {
        Write-Verbose "The temporary folder $Path could not be removed: $($_.Exception.Message)"
    }
}

function Get-LambekCodeToolError {
    param([string] $Text, [string] $Folder, [string] $Pattern)

    # The line that names the error, without the name of the temporary folder
    $line = @($Text -split "`n" | Where-Object { $_ -match $Pattern } | Select-Object -First 1)
    $where = ''
    if ($Text -match 'program\.js:(?<line>\d+)') { $where = "line $($Matches['line']): " }
    return ($where + "$line".Trim()).Replace($Folder, '')
}

function Invoke-LambekCodeTool {
    param(
        [string] $FilePath,
        [string[]] $ArgumentList = @(),
        [string] $InputText,
        [int] $TimeoutSeconds = 60
    )

    # A child process with its own pipes: each argument is passed as it is, never through a shell
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    foreach ($argument in $ArgumentList) { $start.ArgumentList.Add($argument) }
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    $start.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    $timedOut = $false
    try {
        [void] $process.Start()
        # Both outputs are read while the program runs, so a long message never blocks it
        $output = $process.StandardOutput.ReadToEndAsync()
        $failure = $process.StandardError.ReadToEndAsync()
        try {
            if ($InputText) { $process.StandardInput.Write($InputText) }
            $process.StandardInput.Close()
        }
        catch { Write-Verbose "The tool closed its input early: $($_.Exception.Message)" }

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            try { $process.Kill($true) } catch { Write-Verbose "The tool could not be stopped: $($_.Exception.Message)" }
            return [pscustomobject]@{ ExitCode = -1; Output = ''; Error = "stopped after $TimeoutSeconds seconds"; TimedOut = $true }
        }
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output.GetAwaiter().GetResult(); Error = $failure.GetAwaiter().GetResult(); TimedOut = $timedOut }
    }
    catch {
        return [pscustomobject]@{ ExitCode = -1; Output = ''; Error = $_.Exception.Message; TimedOut = $false }
    }
    finally {
        $process.Dispose()
    }
}
