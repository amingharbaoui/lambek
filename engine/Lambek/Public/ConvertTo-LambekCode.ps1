function ConvertTo-LambekCode {
    <#
    .SYNOPSIS
        Writes a ready plan as a standalone program in PowerShell, Python, JavaScript, C#, Rust or Bash.
    .DESCRIPTION
        The program is only text: Lambek never runs it. It does a dry run unless it is started with --apply
        (-Apply in PowerShell). A plan with a step that cannot be a program gives no code, and says which step.
    .EXAMPLE
        ConvertTo-LambekCode -Plan (New-LambekPlan 'delete the .log files older than 30 days in C:\Temp') -Language Python
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Lambek.Plan')]
        [pscustomobject] $Plan,

        [Parameter(Mandatory)]
        [string] $Language,

        # Leave the syntax check out (it starts python, node, rustc or bash)
        [switch] $SkipSyntax,

        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 60
    )

    process {
        $known = Resolve-LambekCodeLanguage -Name $Language
        if (-not $known) {
            throw "Language '$Language' is not one of: $(@(Get-LambekCodeLanguage | ForEach-Object { $_.Name }) -join ', ')."
        }
        if ($Plan.Status -ne 'Ready') {
            throw "Only a ready plan can be written as code (status: $($Plan.Status))."
        }

        # The plan as operations no language owns, then the steps that cannot be a program
        $model = ConvertTo-LambekCodeModel -Plan $Plan
        $unsupported = @($model.Steps | Where-Object { -not $_.Supported } | ForEach-Object {
                [pscustomobject]@{ Step = $_.Step; Action = $_.Action; Reason = $_.Reason }
            })

        $code = $null
        $syntax = $null
        $notes = [System.Collections.Generic.List[string]]::new()
        if ($unsupported.Count -eq 0) {
            switch ($known.Name) {
                'PowerShell' { $code = Format-LambekCodePowerShell -Model $model }
                'Python' { $code = Format-LambekCodePython -Model $model }
                'JavaScript' { $code = Format-LambekCodeJavaScript -Model $model }
                'CSharp' { $code = Format-LambekCodeCSharp -Model $model }
                'Rust' { $code = Format-LambekCodeRust -Model $model }
                'Bash' { $code = Format-LambekCodeBash -Model $model }
            }
            if (-not $SkipSyntax) { $syntax = Test-LambekCodeSyntax -Code $code -Language $known.Name -TimeoutSeconds $TimeoutSeconds }

            # A Windows path in a Bash script is kept as typed: it is for the user to say where that drive is mounted
            $paths = @($model.Steps | ForEach-Object { $_.Root; $_.Destination; $_.Source; $_.Path } | Where-Object { $_ })
            if ($known.Name -eq 'Bash' -and @($paths | Where-Object { $_ -match '^[A-Za-z]:|\\' }).Count -gt 0) {
                $notes.Add('The paths are Windows paths: in Bash (WSL, Git Bash) write them the way that shell sees the drive, for example /mnt/c/Temp.')
            }
        }

        [pscustomobject]@{
            PSTypeName  = 'Lambek.Code'
            Language    = $known.Name
            Code        = $code
            FileName    = $known.FileName
            Syntax      = $syntax
            Unsupported = $unsupported
            Notes       = $notes.ToArray()
        }
    }
}
