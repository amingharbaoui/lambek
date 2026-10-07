function Get-LambekUnresolved {
    param([pscustomobject] $Plan)

    # Words Lambek did not know in the turns before, carried until a plan runs (the last three)
    $unresolved = [System.Collections.Generic.List[object]]::new()
    if ($Plan.PSObject.Properties['Unresolved']) { foreach ($item in $Plan.Unresolved) { $unresolved.Add($item) } }
    if ($Plan.Status -ne 'Ready') {
        foreach ($step in $Plan.Steps) {
            if (-not $step.PSObject.Properties['Guess'] -or -not $step.Guess) { continue }
            $said = Get-LambekMemoryTerm -Text $step.Clause -Language $step.Guess.Language
            $unresolved.Add([pscustomobject]@{
                    Word     = $step.Guess.Word
                    Token    = $step.Guess.Token
                    Language = $step.Guess.Language
                    Types    = @($step.Guess.Types)
                    Terms    = @($said.Terms)
                })
        }
    }
    return @($unresolved | Select-Object -Last 3)
}

function Invoke-LambekPursuit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    # Cross-situational learning: an unknown word of an earlier turn, and the plan the user ran after it
    if (-not $Plan.PSObject.Properties['Unresolved'] -or @($Plan.Unresolved).Count -eq 0) { return @() }
    $pursuit = Get-LambekPursuitStore
    $learned = [System.Collections.Generic.List[object]]::new()
    $observed = $false

    foreach ($unknown in $Plan.Unresolved) {
        $language = $unknown.Language
        $said = Get-LambekMemoryTerm -Text $Plan.Original -Language $language

        # A rephrasing, not another request: at least half of the other words and places are the same
        $others = @($unknown.Terms | Where-Object { $_ -ne $unknown.Word -and $_ -notmatch '^_\w+_$' } | Select-Object -Unique)
        $shared = @($others | Where-Object { $_ -in $said.Terms }).Count
        if ($others.Count -gt 0 -and $shared / $others.Count -lt 0.5) { continue }

        # The meanings it may have: new words whose type solves the equation the unknown word left open
        $grammar = (Get-LambekGrammarLexicon -Language $language).Words
        $request = Read-LambekRequest -Text (Repair-LambekPhrase -Text $Plan.Original) -Original $Plan.Original -Language $language
        $meanings = @($request.Words | Where-Object {
                $word = $_
                $word -notin $unknown.Terms -and $grammar.ContainsKey($word) -and @($grammar[$word] | Where-Object { $_ -in $unknown.Types }).Count -gt 0
            } | Select-Object -Unique)
        if ($meanings.Count -eq 0) { continue }

        $key = "$($language):$($unknown.Word)"
        $pursuit.Observe($key, [string[]] @($meanings | ForEach-Object { "$($language):$_" }))
        $observed = $true

        # Learned once one meaning clearly wins: the word then reads like it
        $meaning = $pursuit.Learned($key)
        if (-not $meaning) { continue }
        $meaning = $meaning.Substring($language.Length + 1)
        try {
            Add-LambekWord -Word $unknown.Word -Meaning $meaning -Language $language | Out-Null
            $learned.Add([pscustomobject]@{ Word = $unknown.Token; Meaning = $meaning; Language = $language })
        }
        catch {
            Write-Verbose "'$($unknown.Word)' could not be learned: $($_.Exception.Message)"
        }
    }

    # Kept on disk, except in an incognito chat
    if ($observed -and -not $script:Incognito) {
        try {
            $folder = Split-Path -Path $script:PursuitPath -Parent
            if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
            Set-Content -LiteralPath $script:PursuitPath -Value $pursuit.Save() -Encoding utf8NoBOM
        }
        catch { Write-Warning "The words being learned could not be written: $($_.Exception.Message)" }
    }
    return $learned.ToArray()
}
