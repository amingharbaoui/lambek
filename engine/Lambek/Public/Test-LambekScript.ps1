function Test-LambekScript {
    <#
    .SYNOPSIS
        Checks a PowerShell script with its syntax tree before it can run (AST firewall).
    .EXAMPLE
        Test-LambekScript -Script 'Get-ChildItem C:\Temp' -AllowedCommand 'Get-ChildItem'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Script,

        [string[]] $AllowedCommand = @()
    )

    process {
        $violations = [System.Collections.Generic.List[object]]::new()
        $allowedTypes = @('timespan', 'System.TimeSpan', 'CmdletBinding', 'Parameter', 'OutputType',
            'string', 'int', 'long', 'double', 'bool', 'switch', 'datetime')
        $allowedStatic = @('timespan::FromSeconds', 'System.TimeSpan::FromSeconds')
        $blockedVariables = @('ExecutionContext', 'Host', 'PSCmdlet', 'MyInvocation')

        # Parse without running anything
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Script, [ref] $tokens, [ref] $errors)

        foreach ($parseError in $errors) {
            $violations.Add([pscustomobject]@{
                    Rule = 'ParseError'
                    Line = $parseError.Extent.StartLineNumber
                    Text = $parseError.Message
                })
        }

        # Walk every node of the syntax tree
        foreach ($node in $ast.FindAll({ $true }, $true)) {
            $rule = $null

            if ($node -is [System.Management.Automation.Language.CommandAst]) {
                $name = $node.GetCommandName()
                if ($node.InvocationOperator -ne 'Unknown') {
                    $rule = 'InvocationOperator'
                }
                elseif ($null -eq $name) {
                    $rule = 'DynamicCommand'
                }
                elseif ($name -notin $AllowedCommand) {
                    $rule = 'CommandNotAllowed'
                }
            }
            elseif ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                $member = "$($node.Expression.Extent.Text.Trim('[', ']'))::$($node.Member.Extent.Text)"
                if (-not $node.Static -or $member -notin $allowedStatic) {
                    $rule = 'MethodCall'
                }
            }
            elseif ($node -is [System.Management.Automation.Language.MemberExpressionAst] -and $node.Static) {
                $rule = 'StaticMember'
            }
            elseif ($node -is [System.Management.Automation.Language.AttributeBaseAst] -or $node -is [System.Management.Automation.Language.TypeExpressionAst]) {
                if ($node.TypeName.Name -notin $allowedTypes) {
                    $rule = 'TypeNotAllowed'
                }
            }
            elseif ($node -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $path = $node.VariablePath
                if ($path.DriveName -or $path.IsGlobal -or $path.IsScript -or $path.IsPrivate) {
                    $rule = 'ScopedVariable'
                }
                elseif ($path.UserPath -in $blockedVariables) {
                    $rule = 'VariableNotAllowed'
                }
            }
            elseif ($node -is [System.Management.Automation.Language.FileRedirectionAst]) {
                $rule = 'FileRedirection'
            }

            if ($rule) {
                $violations.Add([pscustomobject]@{
                        Rule = $rule
                        Line = $node.Extent.StartLineNumber
                        Text = $node.Extent.Text
                    })
            }
        }

        [pscustomobject]@{
            PSTypeName = 'Lambek.ScriptCheck'
            IsValid    = $violations.Count -eq 0
            Violations = $violations.ToArray()
        }
    }
}
