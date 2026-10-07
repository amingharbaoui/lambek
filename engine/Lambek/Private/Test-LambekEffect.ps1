function Test-LambekEffect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Step,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Items
    )

    # The postcondition of the action, checked on the real disk once it ran:
    # gone (the items left their place), arrived (they are in the destination), renamed, exists
    $action = (Get-LambekAction -Id $Step.Action).Action
    $parameters = $Step.Parameters
    $wrong = [System.Collections.Generic.List[string]]::new()
    foreach ($effect in @($action['Effect'])) {
        switch ($effect) {
            'gone' {
                foreach ($item in $Items) { if ($item.FullName -and (Test-Path -LiteralPath $item.FullName)) { $wrong.Add($item.FullName) } }
            }
            'arrived' {
                foreach ($item in $Items) {
                    $target = Join-Path ([string] $parameters['Destination']) $item.Name
                    if ($item.Name -and -not (Test-Path -LiteralPath $target)) { $wrong.Add($target) }
                }
            }
            'renamed' {
                $old = [string] $parameters['Name']
                $new = Join-Path (Split-Path -Path $old -Parent) ([string] $parameters['NewName'])
                if (-not (Test-Path -LiteralPath $new) -or (Test-Path -LiteralPath $old)) { $wrong.Add($old) }
            }
            'exists' {
                $path = [string] $parameters['Path']
                if (-not $path) { $path = Join-Path ([string] $parameters['Parent']) ([string] $parameters['Name']) }
                if (-not (Test-Path -LiteralPath $path)) { $wrong.Add($path) }
            }
        }
    }
    return [pscustomobject]@{ Verified = $wrong.Count -eq 0; Wrong = $wrong.ToArray() }
}
