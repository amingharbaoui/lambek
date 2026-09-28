function ConvertTo-LambekMcpCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Action,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Parameters
    )

    $mcp = $Action.Mcp
    $arguments = [ordered]@{}
    $violations = [System.Collections.Generic.List[object]]::new()

    # Values in the JSON type of the schema
    foreach ($item in $mcp.Map) {
        if (-not $Parameters.Contains($item.Name)) { continue }
        $value = $Parameters[$item.Name]
        $text = Format-LambekValue -Value $value

        switch ($item.Type) {
            'integer' {
                $number = 0L
                if ([long]::TryParse($text, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref] $number)) { $arguments[$item.Property] = $number }
                else { $violations.Add((New-LambekMcpViolation "$($item.Property) must be a whole number.")) }
            }
            'number' {
                $number = 0.0
                if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref] $number)) { $arguments[$item.Property] = $number }
                else { $violations.Add((New-LambekMcpViolation "$($item.Property) must be a number.")) }
            }
            'boolean' {
                if ($text -in 'true', 'false') { $arguments[$item.Property] = $text -eq 'true' }
                else { $violations.Add((New-LambekMcpViolation "$($item.Property) must be true or false.")) }
            }
            default {
                $arguments[$item.Property] = $text
            }
        }
    }

    # Input schema rules
    foreach ($violation in Test-LambekMcpArgument -Schema $mcp.Schema -Arguments $arguments) {
        $violations.Add($violation)
    }

    # The exact call, bound to the tool definition by its hash
    $call = [ordered]@{ server = $mcp.Server; tool = $mcp.Tool; arguments = $arguments; hash = $mcp.Hash }
    return [pscustomobject]@{
        Arguments  = $arguments
        Script     = $call | ConvertTo-Json -Depth 10 -Compress
        Violations = $violations.ToArray()
    }
}

function Test-LambekMcpArgument {
    param(
        [System.Collections.IDictionary] $Schema,
        [System.Collections.IDictionary] $Arguments
    )

    $properties = @{}
    if ($Schema.Contains('properties')) { $properties = $Schema.properties }

    if ($Schema.Contains('required')) {
        foreach ($name in $Schema.required) {
            if (-not $Arguments.Contains($name)) { New-LambekMcpViolation "$name is required." }
        }
    }
    if ($Schema.Contains('additionalProperties') -and $Schema.additionalProperties -eq $false) {
        foreach ($name in $Arguments.Keys) {
            if (-not $properties.Contains($name)) { New-LambekMcpViolation "$name is not a parameter of this tool." }
        }
    }

    foreach ($name in $Arguments.Keys) {
        if (-not $properties.Contains($name)) { continue }
        $rules = $properties[$name]
        $value = $Arguments[$name]

        if ($rules.Contains('enum') -and $value -notin @($rules.enum)) {
            New-LambekMcpViolation "$name must be one of: $(@($rules.enum) -join ', ')."
        }
        if ($rules.Contains('const') -and $value -ne $rules.const) {
            New-LambekMcpViolation "$name must be $($rules.const)."
        }
        if ($value -is [string]) {
            if ($rules.Contains('minLength') -and $value.Length -lt $rules.minLength) { New-LambekMcpViolation "$name is too short." }
            if ($rules.Contains('maxLength') -and $value.Length -gt $rules.maxLength) { New-LambekMcpViolation "$name is too long." }
            if ($rules.Contains('pattern') -and $value -cnotmatch $rules.pattern) { New-LambekMcpViolation "$name does not match $($rules.pattern)." }
        }
        if ($value -is [long] -or $value -is [double]) {
            if ($rules.Contains('minimum') -and $value -lt $rules.minimum) { New-LambekMcpViolation "$name must be at least $($rules.minimum)." }
            if ($rules.Contains('maximum') -and $value -gt $rules.maximum) { New-LambekMcpViolation "$name must be at most $($rules.maximum)." }
            if ($rules.Contains('exclusiveMinimum') -and $value -le $rules.exclusiveMinimum) { New-LambekMcpViolation "$name must be more than $($rules.exclusiveMinimum)." }
            if ($rules.Contains('exclusiveMaximum') -and $value -ge $rules.exclusiveMaximum) { New-LambekMcpViolation "$name must be less than $($rules.exclusiveMaximum)." }
        }
    }
}

function New-LambekMcpViolation {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an object in memory.')]
    param([string] $Text)

    [pscustomobject]@{ Rule = 'Schema'; Line = 0; Text = $Text }
}
