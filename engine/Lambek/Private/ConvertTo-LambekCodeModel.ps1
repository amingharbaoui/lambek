function ConvertTo-LambekCodeModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Lambek.Plan')]
        [pscustomobject] $Plan
    )

    # One operation per step, in the order the plan runs them
    $steps = [System.Collections.Generic.List[object]]::new()
    foreach ($number in $Plan.Order) {
        $steps.Add((ConvertTo-LambekCodeStep -Step $Plan.Steps[$number - 1]))
    }

    return [pscustomobject]@{
        PSTypeName = 'Lambek.CodeModel'
        Original   = [string] $Plan.Original
        Steps      = $steps.ToArray()
    }
}

function ConvertTo-LambekCodeStep {
    param([pscustomobject] $Step)

    # Every field is always there, so a backend never has to guess: $null means "not asked"
    $model = [ordered]@{
        Step             = $Step.Step
        Action           = $Step.Action
        Sentence         = [string] $Step.Clause
        Supported        = $true
        Reason           = $null
        Operation        = 'none'
        Root             = $null
        Recurse          = $false
        Name             = $null
        Extensions       = $null
        ExceptExtensions = @()
        ExceptName       = $null
        OlderThanSeconds = $null
        NewerThanSeconds = $null
        MinSize          = $null
        MaxSize          = $null
        Order            = $null
        Count            = $null
        FreeBytes        = $null
        Destination      = $null
        Source           = $null
        NewName          = $null
        Path             = $null
        Kind             = $null
        Permanent        = $false
    }

    # The sentence Lambek says for the step, in the language of the request
    if ($Step.Action -and $Step.Status -eq 'Ready') {
        $units = (Get-LambekLexicon -Language $Step.Language).Answer.Units
        $model.Sentence = Get-LambekStepSentence -Step $Step -Language $Step.Language -Units $units
    }

    $values = $Step.Parameters
    $reason = $null

    # What cannot be a standalone program
    if (-not $Step.Action) { $reason = 'the step has no action' }
    elseif ($Step.Output -eq 'mcp') { $reason = 'a call to an MCP tool only works inside Lambek' }
    elseif ($Step.Output -eq 'code') { $reason = 'the step already is code, there is nothing to run' }
    elseif ($Step.Action -eq 'files.restore') { $reason = "restoring from Lambek's trash only works inside Lambek" }
    elseif ($Step.Action -notin 'files.list', 'files.delete', 'files.free', 'files.copy', 'files.move', 'files.rename', 'files.create') {
        $reason = "the action $($Step.Action) has no code model yet"
    }

    # A text with a line break (or half a character) is never written in code
    if (-not $reason) {
        foreach ($name in $values.Keys) {
            foreach ($value in @($values[$name])) {
                if ($value -isnot [string]) { continue }
                $problem = Test-LambekCodeText -Value $value
                if ($problem) { $reason = "$name cannot be written in code: $problem" }
            }
        }
    }

    if ($reason) {
        $model.Supported = $false
        $model.Reason = $reason
        return [pscustomobject] $model
    }

    switch ($Step.Action) {
        'files.rename' {
            # Rename-Item -LiteralPath Name -NewName NewName: a file or a folder, the new name stays in the same folder
            $model.Operation = 'rename'
            $model.Source = [string] $values['Name']
            $model.NewName = [string] $values['NewName']
            if ($model.NewName -match '[\\/]') { $reason = 'the new name must be a name, not a path' }
        }
        'files.create' {
            # New-Item -Path Path, or New-Item -Path Parent -Name Name
            $model.Operation = 'create'
            $model.Kind = [string] $values['Kind']
            if ($values.Contains('Path')) { $model.Path = [string] $values['Path'] }
            elseif ($values.Contains('Parent') -and $values.Contains('Name')) {
                $model.Path = Join-LambekCodePath -Parent ([string] $values['Parent']) -Name ([string] $values['Name'])
            }
            else { $reason = 'the step does not say what to create' }
            if ($model.Kind -notin 'File', 'Directory') { $reason = "the kind '$($model.Kind)' cannot be created" }
        }
        default {
            # The actions that first pick files: list, delete, free, copy, move
            $model.Operation = $Step.Action.Split('.')[1]
            if ($Step.Action -eq 'files.free') { $model.Operation = 'delete' }

            # Where: list, delete and free look in the subfolders too, copy and move only in the folder itself
            $model.Recurse = $Step.Action -in 'files.list', 'files.delete', 'files.free'
            $where = 'Path'
            if ($Step.Action -in 'files.copy', 'files.move') { $where = 'Source' }
            $model.Root = '.'
            if ($values.Contains($where)) { $model.Root = [string] $values[$where] }
            elseif ($Step.Action -in 'files.delete', 'files.free') { $reason = 'the step does not say in which folder' }

            # Name -EQ and Name -NE: the whole file name, upper or lower case alike
            if ($values.Contains('Name')) { $model.Name = [string] $values['Name'] }
            if ($values.Contains('ExceptName')) { $model.ExceptName = [string] $values['ExceptName'] }

            # Extension -In: the extensions asked and the extensions of the kinds are two filters, a file passes both
            $asked = $null
            if ($values.Contains('Extension')) { $asked = @(Get-LambekCodeExtension -Values $values['Extension']) }
            if ($values.Contains('Kind')) {
                $ofKind = @(Get-LambekCodeExtension -Values $values['Kind'] -Kind)
                if ($null -eq $asked) { $asked = $ofKind }
                else { $asked = @($asked | Where-Object { $_ -in $ofKind }) }
            }
            if ($null -ne $asked) { $model.Extensions = [string[]] @($asked) }

            # Extension -NotIn: one list for the extensions and the kinds left out
            $except = @()
            if ($values.Contains('ExceptExtension')) { $except += @(Get-LambekCodeExtension -Values $values['ExceptExtension']) }
            if ($values.Contains('ExceptKind')) { $except += @(Get-LambekCodeExtension -Values $values['ExceptKind'] -Kind) }
            $model.ExceptExtensions = [string[]] @(Get-LambekCodeExtension -Values $except)

            # LastWriteTime -LT now - age (strictly older), LastWriteTime -GE now - age (as new or newer)
            foreach ($name in 'OlderThan', 'NewerThan') {
                if (-not $values.Contains($name)) { continue }
                $seconds = ([timespan] $values[$name]).TotalSeconds
                if ($seconds -lt 0 -or $seconds -ne [math]::Floor($seconds)) { $reason = "$name is not a whole number of seconds" }
                else { $model["${name}Seconds"] = [long] $seconds }
            }

            # Length -GT size and Length -LT size, both strict. A length is a whole number of bytes,
            # so "more than 307.2" is "more than 307" and "less than 307.2" is "less than 308"
            if ($values.Contains('MinSize')) { $model.MinSize = [long] [math]::Floor([double] $values['MinSize']) }
            if ($values.Contains('MaxSize')) { $model.MaxSize = [long] [math]::Ceiling([double] $values['MaxSize']) }

            # Sort-Object then Select-Object -First
            if ($values.Contains('Order')) {
                $model.Order = [string] $values['Order']
                if ($model.Order -notin 'newest', 'oldest', 'largest', 'smallest') { $reason = "the order '$($model.Order)' is not known" }
            }
            if ($values.Contains('Count')) {
                $count = [double] $values['Count']
                if ($count -lt 1 -or $count -ne [math]::Floor($count) -or $count -gt [int]::MaxValue) { $reason = 'the count is not a whole number of files' }
                else { $model.Count = [int] $count }
            }

            # Free N bytes: the largest files first, one more as long as less than N bytes are counted
            if ($Step.Action -eq 'files.free') {
                $model.Order = 'largest'
                $model.FreeBytes = [long] [math]::Ceiling([double] $values['FreeSize'])
            }

            if ($Step.Action -in 'files.copy', 'files.move') { $model.Destination = [string] $values['Destination'] }
            # In Lambek a deletion goes to its trash unless it is asked for good; freeing space is always for good
            $model.Permanent = $values.Contains('Permanent') -or $Step.Action -eq 'files.free'
        }
    }

    if ($reason) {
        $model.Supported = $false
        $model.Reason = $reason
        $model.Operation = 'none'
    }
    return [pscustomobject] $model
}

function Get-LambekCodeExtension {
    param([object] $Values, [switch] $Kind)

    # Extensions in lower case with their dot, each one once, in the plain order of their characters.
    # A kind ("image") is the extensions it stands for
    $found = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in @($Values)) {
        $extensions = @([string] $value)
        if ($Kind) { $extensions = @(Get-LambekKindExtension -Kind ([string] $value)) }
        foreach ($extension in $extensions) { [void] $found.Add($extension.ToLowerInvariant()) }
    }
    return [string[]] @($found)
}

function Join-LambekCodePath {
    param([string] $Parent, [string] $Name)

    # The separator the parent already uses: a Windows path gets "\", any other "/"
    $separator = '/'
    if ($Parent -match '^[A-Za-z]:' -or $Parent.StartsWith('\\') -or ($Parent.Contains('\') -and -not $Parent.Contains('/'))) { $separator = '\' }
    if ($Parent.EndsWith('/') -or $Parent.EndsWith('\')) { return "$Parent$Name" }
    return "$Parent$separator$Name"
}
