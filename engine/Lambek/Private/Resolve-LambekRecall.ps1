function Resolve-LambekRecall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # "comme la derniere fois", "like last time": which phrase, in which language
    $normalized = " $((ConvertTo-LambekNormalizedText -Text $Text) -replace '[^\p{L}\p{N}]+', ' ') "
    $said = $null
    foreach ($language in Get-LambekAvailableLanguage) {
        foreach ($phrase in (Get-LambekLexicon -Language $language).Again) {
            if ($phrase -and $normalized.Contains(" $phrase ") -and (-not $said -or $phrase.Length -gt $said.Phrase.Length)) {
                $said = [pscustomobject]@{ Phrase = $phrase; Language = $language }
            }
        }
    }
    if (-not $said) { return $null }

    # The rest of the request, as it was typed: "supprime les .tmp" of "supprime les .tmp comme la derniere fois"
    $pattern = ConvertTo-LambekWordPattern -Names @($said.Phrase)
    $pattern = $pattern -replace '\\s\+', '[\s''\u2019-]+'
    $rest = ([regex]::Replace($Text, "(?i)(?<![\p{L}\p{N}])$pattern(?![\p{L}\p{N}])", ' ') -replace '\s+', ' ').Trim(' ', ',', '.', '!', '?', ';')
    $lexicon = Get-LambekLexicon -Language $said.Language
    $meaningful = @((ConvertTo-LambekNormalizedText -Text $rest) -split '[^\p{L}\p{N}]+' | Where-Object { $_ -and -not $lexicon.StopWords.Contains($_) })

    $restPlan = $null
    $structure = @()
    if ($meaningful.Count -gt 0) {
        $restPlan = New-LambekPlan -Text $rest -NoRecall
        $structure = @($restPlan.Steps | Where-Object Action | ForEach-Object Action)
    }

    # The memory that fits: same action when the rest names one, else the closest words, else the most active
    $found = @(Find-LambekMemory -Text $rest -Language $said.Language -Structure $structure -First 20 | Where-Object Kind -EQ 'run')
    if ($structure.Count -gt 0) { $found = @($found | Where-Object { @(($_.Payload | ConvertFrom-Json).Steps | Where-Object { $_.Action -in $structure }).Count -gt 0 }) }
    elseif ($meaningful.Count -gt 0) { $found = @($found | Where-Object { $_.Coverage -gt 0 -or $_.Shape -ge 0.3 }) }
    $best = $found | Select-Object -First 1

    if (-not $best) {
        $plan = $restPlan
        if (-not $plan) { $plan = New-LambekPlan -Text $Text -NoRecall }
        $plan | Add-Member -NotePropertyName Remark -NotePropertyValue $lexicon.Answer.NoMemory -Force
        return $plan
    }

    # The rest names an action: it keeps what it says, the memory gives what it does not say
    $remembered = @(($best.Payload | ConvertFrom-Json -AsHashtable).Steps)
    if ($restPlan -and $structure.Count -gt 0) {
        $plan = $restPlan
        for ($i = 0; $i -lt $plan.Steps.Count; $i++) {
            $step = $plan.Steps[$i]
            $same = @($remembered | Where-Object { $_.Action -eq $step.Action }) | Select-Object -First 1
            if (-not $same) { continue }
            foreach ($name in $same.Parameters.Keys) {
                if ($plan.Steps[$i].Parameters.Contains($name)) { continue }
                try { $plan = Set-LambekPlanParameter -Plan $plan -Step ($i + 1) -Name $name -Value $same.Parameters[$name] }
                catch { Write-Verbose "The remembered $name could not be used: $($_.Exception.Message)" }
            }
        }
    }
    # Else the request remembered, as it was when it ran
    else {
        $plan = New-LambekPlan -Text $best.Text -NoRecall
        for ($i = 0; $i -lt [math]::Min($plan.Steps.Count, $remembered.Count); $i++) {
            if ($plan.Steps[$i].Action -ne $remembered[$i].Action) { continue }
            foreach ($name in $remembered[$i].Parameters.Keys) {
                $value = $remembered[$i].Parameters[$name]
                if ($plan.Steps[$i].Parameters.Contains($name) -and (Format-LambekValue -Value $plan.Steps[$i].Parameters[$name]) -eq $value) { continue }
                try { $plan = Set-LambekPlanParameter -Plan $plan -Step ($i + 1) -Name $name -Value $value }
                catch { Write-Verbose "The remembered $name could not be used: $($_.Exception.Message)" }
            }
        }
    }

    $when = $best.LastUsed.ToLocalTime().ToString('d MMMM HH:mm', [cultureinfo]::GetCultureInfo($said.Language))
    $plan | Add-Member -NotePropertyName Remark -NotePropertyValue ($lexicon.Answer.Recalled -f $when, $best.Text) -Force
    $plan | Add-Member -NotePropertyName Recalled -NotePropertyValue $best.Id -Force
    return $plan
}

function Find-LambekSuggestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Language
    )

    # A request the user confirmed first, then an example of a pack in any language (a typo can hide the language):
    # close in letters, or holding most of the words of the request
    $sources = @(Get-LambekMemoryStore) + @(Get-LambekAvailableLanguage | ForEach-Object { Get-LambekExampleMemory -Language $_ })
    foreach ($memory in $sources) {
        $found = @(Find-LambekMemory -Text $Text -Language $Language -First 3 -Memory $memory | Where-Object { $_.Text -ne $Text })
        $close = $found | Where-Object { $_.Shape -ge 0.45 -or ($_.Shared -ge 2 -and $_.Coverage -ge 0.6) } | Select-Object -First 1
        if ($close) { return $close }
    }
    return $null
}
