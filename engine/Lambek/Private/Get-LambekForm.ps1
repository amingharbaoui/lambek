function Get-LambekFormStore {
    # The turns of phrase learned from the user's own rephrasings, by language:
    # the sentence not understood, its values taken out, and the sentence that said the same and was understood
    if ($null -eq $script:Forms) {
        $script:Forms = @{}
        if (Test-Path -LiteralPath $script:FormsPath -PathType Leaf) {
            try { $script:Forms = Get-Content -LiteralPath $script:FormsPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable }
            catch { Write-Warning "The turns of phrase learned in $script:FormsPath could not be read: $($_.Exception.Message)" }
        }
    }
    return $script:Forms
}

function Get-LambekFormKey {
    param([pscustomobject] $Request)

    # A sentence with its values taken out: "what is inside C:\Data" is "what is inside _path_".
    # Any kind of value has its mark (a place, a name, a number, a size, a duration), so nothing here is about files
    return "$($Request.Normalized)"
}

function Add-LambekRephrased {
    [CmdletBinding()]
    param(
        # The plan the user can run
        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        # The request before it, that was not understood
        [Parameter(Mandatory)]
        [pscustomobject] $Previous
    )

    # A request not understood, then one understood that carries exactly the same values: the second may be the first
    # said another way. The pair travels with the plan, and is only learned once the user has run it
    if ($Plan.PSObject.Properties['Rephrased'] -or $Plan.Status -ne 'Ready' -or $Previous.Status -eq 'Ready') { return }
    if (@($Plan.Steps).Count -ne 1 -or @($Previous.Steps).Count -ne 1) { return }
    $before = @($Previous.Steps)[0]
    if ($before.PSObject.Properties['Act'] -and $before.Act -and $before.Act -ne 'Order') { return }
    if ("$($Plan.Original)" -ceq "$($Previous.Original)") { return }

    $failed = Read-LambekRequest -Text (Repair-LambekPhrase -Text "$($Previous.Original)") -Original "$($Previous.Original)" -Language 'auto'
    $said = Read-LambekRequest -Text (Repair-LambekPhrase -Text "$($Plan.Original)") -Original "$($Plan.Original)" -Language 'auto'
    if ($failed.Language -ne $said.Language) { return }
    $key = Get-LambekFormKey -Request $failed
    if ($key -eq (Get-LambekFormKey -Request $said)) { return }
    # Words of its own, not values alone: a path typed by itself teaches nothing
    if (@($failed.Tokens | Where-Object { $_ -notmatch '^_[a-z]+_$' }).Count -lt 2) { return }

    # Each value of one sentence is a value of the other, one for one, and there is at least one
    $theirs = @($failed.Entities)
    $mine = @($said.Entities)
    if ($mine.Count -eq 0 -or $mine.Count -ne $theirs.Count) { return }
    $taken = [bool[]]::new($theirs.Count)
    $slots = [System.Collections.Generic.List[int]]::new()
    foreach ($entity in $mine) {
        $at = -1
        for ($i = 0; $i -lt $theirs.Count; $i++) {
            if ($taken[$i] -or $theirs[$i].Type -ne $entity.Type) { continue }
            if ((Format-LambekValue -Value $theirs[$i].Value) -ne (Format-LambekValue -Value $entity.Value)) { continue }
            $at = $i
            break
        }
        if ($at -lt 0) { return }
        $taken[$at] = $true
        $slots.Add($at)
    }

    # The sentence understood, as it was written, with a numbered hole where each value stood
    $text = "$($Plan.Original)"
    $to = [System.Text.StringBuilder]::new()
    $from = 0
    for ($i = 0; $i -lt $mine.Count; $i++) {
        $raw = "$($mine[$i].Raw)"
        $at = $text.IndexOf($raw, $from, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $raw -or $at -lt 0) { return }
        [void] $to.Append($text.Substring($from, $at - $from).Replace('{', '{{').Replace('}', '}}')).Append("{$i}")
        $from = $at + $raw.Length
    }
    [void] $to.Append($text.Substring($from).Replace('{', '{{').Replace('}', '}}'))

    $Plan | Add-Member -NotePropertyName Rephrased -NotePropertyValue ([pscustomobject]@{
            Language = $failed.Language
            Key      = $key
            To       = $to.ToString()
            Slots    = $slots.ToArray()
            Said     = "$($Previous.Original)"
            Meaning  = "$($Plan.Original)"
        })
}

function Invoke-LambekFormLearning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    # The plan ran: the sentence said before it is now known to mean it, whatever the values
    if (-not $Plan.PSObject.Properties['Rephrased'] -or -not $Plan.Rephrased) { return @() }
    $pair = $Plan.Rephrased
    $forms = Get-LambekFormStore
    if (-not $forms.ContainsKey($pair.Language)) { $forms[$pair.Language] = @{} }
    $forms[$pair.Language][$pair.Key] = [ordered]@{ To = $pair.To; Slots = @($pair.Slots); Action = "$(@($Plan.Steps)[0].Action)" }

    # Kept on disk, sorted, except in an incognito chat
    if (-not $script:Incognito) {
        try {
            $folder = Split-Path -Path $script:FormsPath -Parent
            if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
            $sorted = [ordered]@{}
            foreach ($language in @($forms.Keys | Sort-Object)) {
                $sorted[$language] = [ordered]@{}
                foreach ($key in [string[]] @($forms[$language].Keys | Sort-Object)) { $sorted[$language][$key] = $forms[$language][$key] }
            }
            Set-Content -LiteralPath $script:FormsPath -Value ($sorted | ConvertTo-Json -Depth 5) -Encoding utf8NoBOM
        }
        catch { Write-Warning "The turns of phrase learned could not be written: $($_.Exception.Message)" }
    }
    return @([pscustomobject]@{ Word = $pair.Said; Meaning = $pair.Meaning; Language = $pair.Language })
}

function Get-LambekFormReading {
    [CmdletBinding()]
    param(
        # The request read as typed
        [Parameter(Mandatory)]
        [pscustomobject] $Request
    )

    # The sentence a learned turn of phrase stands for, with the values of this request in its holes
    $forms = Get-LambekFormStore
    if (-not $forms.ContainsKey($Request.Language)) { return $null }
    $key = Get-LambekFormKey -Request $Request
    if (-not $forms[$Request.Language].ContainsKey($key)) { return $null }
    $form = $forms[$Request.Language][$key]
    $entities = @($Request.Entities)
    $slots = @($form['Slots'])
    if ($slots.Count -ne $entities.Count) { return $null }
    $values = foreach ($slot in $slots) {
        if ([int] $slot -lt 0 -or [int] $slot -ge $entities.Count) { return $null }
        "$($entities[[int] $slot].Raw)"
    }
    try { return "$($form['To'])" -f @($values) } catch { return $null }
}
