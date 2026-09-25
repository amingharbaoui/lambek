function Invoke-LambekSandbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Script,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Commands,

        [switch] $Simulate,

        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 60
    )

    # Normal session with the standard modules
    $session = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $session.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage
    $session.ImportPSModule([string[]] @('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility'))

    # No external programs and no script files
    $blocked = @($session.Commands | Where-Object {
            $_ -is [System.Management.Automation.Runspaces.SessionStateApplicationEntry] -or
            $_ -is [System.Management.Automation.Runspaces.SessionStateScriptEntry]
        })
    foreach ($entry in $blocked) {
        $session.Commands.Remove($entry.Name, $entry.GetType())
    }

    # Preferences
    $variables = @{
        WhatIfPreference              = [bool] $Simulate
        ConfirmPreference             = 'None'
        ErrorActionPreference         = 'Stop'
        PSModuleAutoLoadingPreference = 'None'
    }
    foreach ($key in $variables.Keys) {
        $session.Variables.Add([System.Management.Automation.Runspaces.SessionStateVariableEntry]::new($key, $variables[$key], ''))
    }

    # Run with a time limit
    $runspace = [runspacefactory]::CreateRunspace($session)
    $powershell = [powershell]::Create()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $errorMessage = $null
        $output = @()
        try {
            $runspace.Open()

            # Hide every command outside the list
            $allCommands = $runspace.SessionStateProxy.InvokeCommand.GetCommands('*', 'Alias, Function, Filter, Cmdlet', $true)
            foreach ($command in $allCommands) {
                if ($command.Name -notin $Commands) {
                    $command.Visibility = [System.Management.Automation.SessionStateEntryVisibility]::Private
                }
            }

            $powershell.Runspace = $runspace
            [void] $powershell.AddScript($Script)

            $async = $powershell.BeginInvoke()
            if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
                $powershell.Stop()
                $errorMessage = "The script did not finish within $TimeoutSeconds seconds."
            }
            else {
                $output = @($powershell.EndInvoke($async))
            }
        }
        catch {
            $errorMessage = $_.Exception.InnerException.Message
            if (-not $errorMessage) { $errorMessage = $_.Exception.Message }
        }

        if (-not $errorMessage -and $powershell.Streams.Error.Count -gt 0) {
            $errorMessage = $powershell.Streams.Error[0].ToString()
        }
        if ($errorMessage) {
            $errorMessage = $errorMessage -replace '^The running command stopped because .*? is set to Stop: ', ''
        }

        # Items the script worked on
        $items = $null
        if ($runspace.RunspaceStateInfo.State -eq 'Opened') {
            $items = $runspace.SessionStateProxy.GetVariable('items')
        }

        return [pscustomobject]@{
            Succeeded = $null -eq $errorMessage
            Error     = $errorMessage
            Output    = $output
            Items     = @($items | Where-Object { $null -ne $_ })
            Duration  = $stopwatch.Elapsed
        }
    }
    finally {
        $powershell.Dispose()
        $runspace.Dispose()
    }
}
