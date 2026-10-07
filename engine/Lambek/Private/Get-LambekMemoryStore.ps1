function Get-LambekMemoryStore {
    [CmdletBinding()]
    param()

    # The confirmed requests, read once per session
    if ($null -eq $script:Memory) { $script:Memory = [LambekMemory]::Load($script:MemoryPath) }
    return $script:Memory
}

function Get-LambekPursuitStore {
    [CmdletBinding()]
    param()

    # What each unknown word may mean, read once per session
    if ($null -eq $script:Pursuit) {
        $text = ''
        if (Test-Path -LiteralPath $script:PursuitPath -PathType Leaf) { $text = [IO.File]::ReadAllText($script:PursuitPath) }
        try { $script:Pursuit = [LambekPursuit]::Load($text) }
        catch {
            Write-Warning "The words being learned in $script:PursuitPath could not be read: $($_.Exception.Message)"
            $script:Pursuit = [LambekPursuit]::new()
        }
    }
    return $script:Pursuit
}

function Get-LambekMemoryTime {
    param([datetime] $Time = [datetime]::UtcNow)

    return ($Time.ToUniversalTime() - [datetime]::UnixEpoch).TotalSeconds
}

function Get-LambekMemoryTerm {
    param(
        [string] $Text,
        [string] $Language = 'auto'
    )

    # The words of a request, then its entities as they were said: ".tmp" and "C:\Temp" tell two requests apart
    $request = Read-LambekRequest -Text (Repair-LambekPhrase -Text $Text) -Original $Text -Language $Language
    $terms = [System.Collections.Generic.List[string]]::new()
    foreach ($term in $request.Terms) { $terms.Add([string] $term) }
    foreach ($entity in $request.Entities) {
        $terms.Add("$($entity.Type):$((Format-LambekValue -Value $entity.Value).ToLowerInvariant())")
    }
    [pscustomobject]@{ Language = $request.Language; Terms = [string[]] $terms.ToArray() }
}

function Get-LambekPlanStructure {
    param([pscustomobject] $Plan)

    # What the plan means, without its words: its actions and the parameters each one has
    $structure = foreach ($step in $Plan.Steps) {
        if (-not $step.Action) { continue }
        $step.Action
        foreach ($name in $step.Parameters.Keys) { "$($step.Action):$name" }
    }
    return [string[]] @($structure)
}

function Add-LambekMemory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    # Nothing is kept from an incognito chat
    if ($script:Incognito) { return }

    $steps = foreach ($step in $Plan.Steps) {
        $values = [ordered]@{}
        foreach ($name in $step.Parameters.Keys) { $values[$name] = Format-LambekValue -Value $step.Parameters[$name] }
        [ordered]@{ Action = $step.Action; Parameters = $values }
    }
    $payload = ConvertTo-Json -InputObject @{ Steps = @($steps) } -Compress -Depth 5
    $said = Get-LambekMemoryTerm -Text $Plan.Original -Language $Plan.Steps[0].Language

    $memory = Get-LambekMemoryStore
    $before = $memory.Count
    $time = Get-LambekMemoryTime
    $item = $memory.Add('run', $Plan.Original, $said.Language, $said.Terms, (Get-LambekPlanStructure -Plan $Plan), $payload, $time)

    # A new memory is written whole, one used again only gets its new use
    $line = [LambekMemory]::UseLine($item.Id, $time)
    if ($memory.Count -gt $before) { $line = [LambekMemory]::Line($item) }
    try { [LambekMemory]::Append($script:MemoryPath, $line) }
    catch { Write-Warning "The memory could not be written: $($_.Exception.Message)" }
    return $item
}

function Find-LambekMemory {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string] $Text = '',

        [string] $Language = 'auto',

        [string[]] $Structure = @(),

        [ValidateRange(1, 100)]
        [int] $First = 5,

        [LambekMemory] $Memory
    )

    if (-not $Memory) { $Memory = Get-LambekMemoryStore }
    if ($Memory.Count -eq 0) { return @() }
    $terms = [string[]] @()
    if ($Text.Trim()) { $terms = (Get-LambekMemoryTerm -Text $Text -Language $Language).Terms }
    $found = $Memory.Recall($terms, $Text, [string[]] @($Structure), (Get-LambekMemoryTime), $First, '')

    foreach ($recall in $found) {
        # The part of the words of the request the memory holds too
        $shared = @($terms | Where-Object { $_ -in $recall.Item.Terms } | Select-Object -Unique).Count
        $coverage = 0.0
        if ($terms.Count -gt 0) { $coverage = $shared / @($terms | Select-Object -Unique).Count }
        [pscustomobject]@{
            PSTypeName  = 'Lambek.Memory'
            Id          = $recall.Item.Id
            Kind        = $recall.Item.Kind
            Text        = $recall.Item.Text
            Language    = $recall.Item.Language
            Score       = [math]::Round($recall.Score, 5)
            Lexical     = [math]::Round($recall.Lexical, 3)
            Shape       = [math]::Round($recall.Shape, 3)
            Meaning     = [math]::Round($recall.Meaning, 3)
            Shared      = $shared
            Coverage    = [math]::Round($coverage, 3)
            Activation  = [math]::Round($recall.Activation, 3)
            Probability = [math]::Round($recall.Probability, 3)
            Uses        = $recall.Item.Uses.Count
            LastUsed    = [datetime]::UnixEpoch.AddSeconds(($recall.Item.Uses | Measure-Object -Maximum).Maximum)
            Payload     = $recall.Item.Payload
        }
    }
}

function Get-LambekExampleMemory {
    param([string] $Language)

    # The examples of the packs, as a memory of their own: "did you mean" works from the first day
    $index = Get-LambekActionIndex -Language $Language
    if (-not $index.PSObject.Properties['Memory']) {
        $memory = [LambekMemory]::new()
        foreach ($entry in $index.Entries) {
            if ($memory.Get([LambekMemory]::MakeId('example', $Language, $entry.Example, $entry.Action.Id))) { continue }
            $memory.Add('example', $entry.Example, $Language, [string[]] @($entry.Terms), [string[]] @($entry.Action.Id), $entry.Action.Id, 0) | Out-Null
        }
        $index | Add-Member -NotePropertyName Memory -NotePropertyValue $memory
    }
    return $index.Memory
}
