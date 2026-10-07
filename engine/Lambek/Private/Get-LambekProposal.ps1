function Get-LambekProposal {
    <#
    .SYNOPSIS
        Asks the optional proposer which action a request Lambek did not understand looks like.
        It gives the best actions with their probabilities and one example sentence of the best one, or nothing
        when the proposer file is absent, when the request looks like no action, or when it is not sure enough.
        The example is only a "did you mean": it must go through the grammar and the checks like anything typed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        # The language of the example sentence; found from the text when not given
        [string] $Language,

        [ValidateRange(1, 20)]
        [int] $First = 3,

        # Under this probability nothing is proposed; -1 is the threshold fitted when the proposer was trained
        [double] $Threshold = -1,

        [string] $Path,

        [string] $AdapterPath
    )

    $model = Get-LambekProposerModel -Path $Path -AdapterPath $AdapterPath
    if (-not $model -or -not $Text.Trim()) { return }
    if ($Threshold -lt 0) { $Threshold = $model.Threshold }

    # The classes from the most probable; "none" first means the request asks for nothing Lambek does
    $probabilities = $model.Predict($Text)
    $order = [LambekTransformer]::Rank($probabilities)
    $best = $model.Classes[$order[0]]
    if ($best -eq 'none' -or $probabilities[$order[0]] -lt $Threshold) { return }

    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($index in $order) {
        if ($model.Classes[$index] -eq 'none') { continue }
        if ($candidates.Count -ge $First) { break }
        $candidates.Add([pscustomobject]@{ Action = $model.Classes[$index]; Probability = [math]::Round($probabilities[$index], 4) })
    }

    if (-not $Language) { $Language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) }
    $example = Get-LambekProposalExample -Action $best -Language $Language -Text $Text
    [pscustomobject]@{
        PSTypeName  = 'Lambek.Proposal'
        Action      = $best
        Probability = [math]::Round($probabilities[$order[0]], 4)
        Example     = $example.Text
        Language    = $example.Language
        Threshold   = [math]::Round($Threshold, 4)
        Candidates  = $candidates.ToArray()
    }
}

function Get-LambekProposerPath {
    param([string] $Path, [string] $AdapterPath)

    # The base comes with the module; the adapter of the user lives with what Lambek learned from that user
    if (-not $Path) { $Path = Join-Path $PSScriptRoot '../Data/proposer.json' }
    if (-not $AdapterPath) { $AdapterPath = Join-Path (Split-Path -Path $script:MemoryPath -Parent) 'proposer-adapter.json' }
    [pscustomobject]@{ Path = $Path; AdapterPath = $AdapterPath }
}

function Get-LambekProposerModel {
    param([string] $Path, [string] $AdapterPath)

    # No file, no proposer: Lambek works as before
    $paths = Get-LambekProposerPath -Path $Path -AdapterPath $AdapterPath
    if (-not (Test-Path -LiteralPath $paths.Path -PathType Leaf)) { return $null }

    # Read once, and again only when one of the two files changed (or the adapter was removed)
    $stamp = Get-LambekProposerStamp -Path $paths.Path
    $stamp += '|' + (Get-LambekProposerStamp -Path $paths.AdapterPath)
    $cache = Get-Variable -Name ProposerCache -Scope Script -ValueOnly -ErrorAction Ignore
    if ($cache -and $cache.Stamp -eq $stamp) { return $cache.Model }

    $model = [LambekTransformer]::Load([System.IO.File]::ReadAllText($paths.Path))
    if (Test-Path -LiteralPath $paths.AdapterPath -PathType Leaf) {
        try {
            $adapter = [LambekAdapter]::Load([System.IO.File]::ReadAllText($paths.AdapterPath))
            # An adapter trained on another base means nothing on this one: it is left aside
            if ($adapter.Base -eq $model.Fingerprint()) { $model.Attach($adapter) }
            else { Write-Verbose 'The adapter of the proposer was trained on another base: it is not used.' }
        }
        catch {
            Write-Verbose "The adapter of the proposer could not be read: $($_.Exception.Message)"
        }
    }
    $script:ProposerCache = [pscustomobject]@{ Stamp = $stamp; Model = $model }
    return $model
}

function Get-LambekProposerStamp {
    param([string] $Path)

    # What tells a file changed: its name, size and time of writing
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "$Path absent" }
    $file = Get-Item -LiteralPath $Path
    return "$($file.FullName) $($file.Length) $($file.LastWriteTimeUtc.Ticks)"
}

function Get-LambekProposalExample {
    param([string] $Action, [string] $Language, [string] $Text)

    # The example sentences of the action in the language asked, else in English, else in any language
    $examples = @()
    $found = $Language
    foreach ($pack in $script:Packs.Values) {
        foreach ($candidate in $pack.Actions) {
            if ($candidate.Id -ne $Action -or -not $candidate.Contains('Examples')) { continue }
            foreach ($try in @($Language, 'en') + @($candidate.Examples.Keys | Sort-Object)) {
                if ($try -and $candidate.Examples.Contains($try) -and @($candidate.Examples[$try]).Count -gt 0) {
                    $examples = @($candidate.Examples[$try])
                    $found = $try
                    break
                }
            }
        }
    }
    if ($examples.Count -eq 0) { return [pscustomobject]@{ Text = $null; Language = $Language } }

    # The one closest to the request: words shared / words of either (Jaccard); the first one of a tie
    $words = @([LambekTransformerText]::Words($Text) | Select-Object -Unique)
    $best = $examples[0]
    $bestScore = -1.0
    foreach ($example in $examples) {
        $own = @([LambekTransformerText]::Words($example) | Select-Object -Unique)
        $shared = @($own | Where-Object { $_ -in $words }).Count
        $score = $shared / ($words.Count + $own.Count - $shared)
        if ($score -gt $bestScore) {
            $best = $example
            $bestScore = $score
        }
    }
    [pscustomobject]@{ Text = [string] $best; Language = $found }
}

function Add-LambekProposalExample {
    <#
    .SYNOPSIS
        Teaches the adapter of the user one request the user confirmed (text -> action): a few gradient steps on
        A and B of the adapter only. The base file is never written. To forget everything learned this way,
        remove the adapter file: the proposer is then the base again, exactly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Action,

        [ValidateRange(1, 200)]
        [int] $Steps = 12,

        [string] $Path,

        [string] $AdapterPath
    )

    $paths = Get-LambekProposerPath -Path $Path -AdapterPath $AdapterPath
    if (-not (Test-Path -LiteralPath $paths.Path -PathType Leaf)) { return }
    $model = [LambekTransformer]::Load([System.IO.File]::ReadAllText($paths.Path))
    if ($model.ClassIndex($Action) -lt 0) { return }

    # The adapter of this base, or a new one (rank 4, B = 0: it starts as the base itself).
    # One trained on an older base is started again from the requests it kept
    $adapter = $model.NewAdapter('user', 4, 8.0, 2021, $true)
    if (Test-Path -LiteralPath $paths.AdapterPath -PathType Leaf) {
        $old = [LambekAdapter]::Load([System.IO.File]::ReadAllText($paths.AdapterPath))
        if ($old.Base -eq $model.Fingerprint()) { $adapter = $old }
        else {
            for ($i = 0; $i -lt $old.Texts.Count; $i++) {
                if ($model.ClassIndex($old.Labels[$i]) -ge 0) {
                    $adapter.Texts.Add($old.Texts[$i])
                    $adapter.Labels.Add($old.Labels[$i])
                }
            }
        }
    }
    $model.Attach($adapter)
    $losses = $model.Learn($adapter, $Text, $Action, $Steps, 0.01)

    $folder = Split-Path -Path $paths.AdapterPath -Parent
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    [System.IO.File]::WriteAllText($paths.AdapterPath, $adapter.Save(), [System.Text.UTF8Encoding]::new($false))
    [pscustomobject]@{
        Examples = $adapter.Texts.Count
        Loss     = [math]::Round($losses[$losses.Length - 1], 4)
        Path     = $paths.AdapterPath
    }
}
