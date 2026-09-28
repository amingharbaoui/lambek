function Complete-LambekStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Step
    )

    # Only a ready card gets a script
    if ($Step.Status -ne 'Ready') {
        return $Step
    }

    $definition = Get-LambekAction -Id $Step.Action
    $action = $definition.Action
    $parameters = $Step.Parameters
    $Step.Output = $action.Output

    # Resources read and written
    $Step.Reads = @($action.Reads | Where-Object { $parameters.Contains($_) } | ForEach-Object { [string] $parameters[$_] })
    $Step.Writes = @($action.Writes | Where-Object { $parameters.Contains($_) } | ForEach-Object { [string] $parameters[$_] })

    # MCP tool: the exact call, checked against the input schema
    if ($action.Output -eq 'mcp') {
        $call = ConvertTo-LambekMcpCall -Action $action -Parameters $parameters
        $Step.Script = $call.Script
        $Step.Check = [pscustomobject]@{ IsValid = $call.Violations.Count -eq 0; Violations = $call.Violations }
        if (-not $Step.Check.IsValid) {
            $Step.Status = 'Blocked'
            $Step.Questions = @($Step.Questions) + @($call.Violations | ForEach-Object { $_.Text })
        }
        return $Step
    }

    # Supported values (for example, only PowerShell code)
    $unsupported = $null
    if ($action.ContainsKey('Supported')) {
        foreach ($name in $action.Supported.Keys) {
            if ($parameters.Contains($name) -and $parameters[$name] -notin $action.Supported[$name]) {
                $unsupported = "$name '$($parameters[$name])' is not supported yet."
            }
        }
    }

    # Template
    $template = $null
    if ($action.ContainsKey('Template')) {
        $template = $action.Template
    }
    elseif ($action.ContainsKey('Templates')) {
        $key = [string] $parameters[$action.TemplateKey]
        if ($action.Templates.ContainsKey($key)) {
            $template = $action.Templates[$key]
        }
        else {
            $unsupported = "$($action.TemplateKey) '$key' has no template yet."
        }
    }

    if ($unsupported) {
        $Step.Status = 'Unsupported'
        $Step.Questions = @($Step.Questions) + $unsupported
        return $Step
    }

    # Script and safety check
    try {
        $Step.Script = ConvertTo-LambekScript -Template $template -Parameters $parameters
        $Step.Check = Test-LambekScript -Script $Step.Script -AllowedCommand $definition.Pack.Commands
        if (-not $Step.Check.IsValid) {
            $Step.Status = 'Blocked'
            $rules = ($Step.Check.Violations | ForEach-Object { $_.Rule } | Select-Object -Unique) -join ', '
            $Step.Questions = @($Step.Questions) + "the script did not pass the safety check ($rules)."
        }
    }
    catch {
        $Step.Status = 'Blocked'
        $Step.Questions = @($Step.Questions) + $_.Exception.Message
    }

    return $Step
}
