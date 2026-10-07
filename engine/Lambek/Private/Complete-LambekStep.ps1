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

    # The rules of the knowledge base: some folders are never changed (the system, a whole drive, your whole user folder)
    $blocked = @(Test-LambekPolicy -Paths $Step.Writes)
    if ($blocked.Count -gt 0) {
        $said = (Get-LambekLexicon -Language $Step.Language).Protected
        $Step.Status = 'Blocked'
        $Step.Questions = @($Step.Questions) + @($blocked | ForEach-Object { $said.Text -f $_.Path, $said.Reasons[$_.Reason] } | Select-Object -Unique)
        return $Step
    }

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
        # A kind of file becomes the extensions this machine gives it: image is .jpg, .png...
        $values = [ordered]@{}
        foreach ($name in $parameters.Keys) { $values[$name] = $parameters[$name] }
        foreach ($parameter in $action.Parameters) {
            if ($parameter['Expand'] -eq 'Extensions' -and $values.Contains($parameter.Name)) {
                $extensions = foreach ($kind in @($values[$parameter.Name])) { Get-LambekKindExtension -Kind $kind }
                $values[$parameter.Name] = [string[]] @($extensions | Sort-Object -Unique)
            }
        }
        # Values of the engine the templates may use: Lambek's trash
        $values['Trash'] = $script:TrashPath
        $Step.Script = ConvertTo-LambekScript -Template $template -Parameters $values
        $Step.Check = Test-LambekScript -Script $Step.Script -AllowedCommand $definition.Pack.Commands
        # Code in another language is only text to copy: it never runs here, and the PowerShell check cannot read it
        if ($action.Output -eq 'code' -and $values.Contains('Language') -and $values['Language'] -ne 'PowerShell') {
            $Step.Check = [pscustomobject]@{ IsValid = $true; Violations = @() }
        }
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
