function Get-LambekVagueMeaning {
    [CmdletBinding()]
    param(
        # A step read from a clause, and the words of the clause
        [Parameter(Mandatory)]
        [pscustomobject] $Step,

        [Parameter(Mandatory)]
        [string] $Clause
    )

    # A vague word ("gros", "old", "recientes") has a membership that grows from 0 to 1 over a range (a trapezoid, Zadeh):
    # mu(x) = max(0, min((x - a) / (b - a), 1, (d - x) / (d - c))). A reading takes the 0.5 cut, rounded to a number
    # people use (1, 2 or 5 times a power of ten); a change takes the core, where mu is 1, so only what surely is
    # "large" is touched. The threshold is always said, and the sentence with it must read back to the same plan
    if (-not $Step.Action) { return $null }
    # "les 3 plus gros", "the oldest": a superlative orders the files, it gives no threshold
    if ($Step.Parameters -and $Step.Parameters.Contains('Order')) { return $null }
    $found = Get-LambekAction -Id $Step.Action
    if (-not $found) { return $null }
    $names = @($found.Action.Parameters | ForEach-Object { $_.Name })
    $tokens = @((ConvertTo-LambekNormalizedText -Text $Clause) -split '[^\p{L}\p{N}]+' | Where-Object { $_ })
    $typed = @($Clause -split '[^\p{L}\p{N}]+' | Where-Object { $_ })

    foreach ($pack in $script:Packs.Values) {
        if (-not $pack.PSObject.Properties['Vague'] -or -not $pack.Vague) { continue }
        foreach ($entry in $pack.Vague.GetEnumerator()) {
            $vague = $entry.Value
            if ($vague.Parameter -notin $names -or $Step.Parameters.Contains($vague.Parameter)) { continue }
            # The words of every language: a borrowed word counts too ("delete les big fichiers")
            $words = @($vague.Words.Values | ForEach-Object { $_ })
            $at = -1
            for ($k = 0; $k -lt $tokens.Count; $k++) { if ($tokens[$k] -in $words) { $at = $k; break } }
            if ($at -lt 0) { continue }

            $shape = @($vague.Membership)
            $rising = $null -ne $shape[0]
            $low = if ($rising) { [double] $shape[0] } else { [double] $shape[2] }
            $high = if ($rising) { [double] $shape[1] } else { [double] $shape[3] }
            $core = $Step.Risk -ne 'low'
            if ($core) { $amount = if ($rising) { $high } else { $low } }
            else { $amount = Get-LambekRoundNumber -Value (($low + $high) / 2) }

            $value = switch ($vague.Unit) {
                'day' { [timespan]::FromDays($amount) }
                'KB' { [long] ($amount * 1KB) }
                'MB' { [long] ($amount * 1MB) }
                'GB' { [long] ($amount * 1GB) }
            }
            $proposed = [pscustomobject]@{}
            foreach ($property in $Step.PSObject.Properties) { $proposed | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
            $parameters = [ordered]@{}
            foreach ($key in $Step.Parameters.Keys) { $parameters[$key] = $Step.Parameters[$key] }
            $parameters[$vague.Parameter] = $value
            $proposed.Parameters = $parameters

            # Said in the language of the step, and read back: the sentence must give this very plan
            $answer = (Get-LambekLexicon -Language $Step.Language).Answer
            $sentence = Get-LambekStepSentence -Step $proposed -Language $Step.Language -Units $answer.Units -Unchecked
            $differ = Test-LambekRoundTrip -Step $proposed -Sentence $sentence -Language $Step.Language
            if ($null -eq $differ -or @($differ).Count -gt 0) {
                Write-Verbose "The threshold of '$($typed[$at])' does not read back: it is only asked."
                return $null
            }
            $word = $tokens[$at]
            if ($at -lt $typed.Count) { $word = $typed[$at] }
            return [pscustomobject]@{
                Word      = $word
                Name      = $entry.Key
                Parameter = $vague.Parameter
                Value     = $value
                Shown     = $answer.VagueDirection[$vague.Parameter] -f (Format-LambekHumanValue -Name $vague.Parameter -Value $value -Units $answer.Units)
                Core      = $core
                Sentence  = $sentence
                Step      = $proposed
            }
        }
    }
    return $null
}

function Get-LambekRoundNumber {
    param([double] $Value)

    # The nearest of 1, 2 or 5 times a power of ten, on a logarithmic scale
    if ($Value -le 0) { return 0 }
    $power = [math]::Pow(10, [math]::Floor([math]::Log10($Value)))
    $best = $power
    foreach ($step in 1, 2, 5, 10) {
        if ([math]::Abs([math]::Log($Value / ($step * $power))) -lt [math]::Abs([math]::Log($Value / $best))) { $best = $step * $power }
    }
    return $best
}
