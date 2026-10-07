function Expand-LambekMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # A compound task ("nettoie C:\Temp", "organize D:\Downloads") is decomposed by a method of a pack into its steps,
    # as in hierarchical task networks: the method names the task, what it needs is one folder, and its body is a list
    # of primitive steps said in the language of the request. Each step is then read, typed, checked and simulated
    # like any other, so a method can never do what its steps would not
    $methods = @($script:Packs.Values | Where-Object { $_.PSObject.Properties['Methods'] -and $_.Methods -and $_.Methods.Count -gt 0 })
    if ($methods.Count -eq 0) { return $null }

    # The whole request is the task and its folder: one place, and nothing else that carries a value
    $extraction = Get-LambekEntity -Text $Text
    $places = @($extraction.Entities)
    if ($places.Count -ne 1 -or $places[0].Type -notin 'path', 'quoted') { return $null }
    $path = [string] $places[0].Value
    $said = @((ConvertTo-LambekNormalizedText -Text $extraction.Remainder) -split '[^\p{L}\p{N}_]+' | Where-Object { $_ -and $_ -notmatch '^_\w+_$' })

    foreach ($pack in $methods) {
        # The words for a folder ("dossier", "folder", "Ordner") say nothing more than the path does
        $nouns = @()
        if ($pack.Sorts.ContainsKey('o') -and $pack.Sorts['o'].ContainsKey('folder')) { $nouns = @($pack.Sorts['o']['folder']) }
        foreach ($name in @($pack.Methods.Keys | Sort-Object)) {
            $method = $pack.Methods[$name]
            foreach ($language in @($method.Words.Keys | Sort-Object)) {
                if (-not $method.Steps.ContainsKey($language)) { continue }
                $lexicon = Get-LambekLexicon -Language $language
                # The longest way to say it first: "clean up" before "clean"
                foreach ($word in @($method.Words[$language] | Sort-Object @{ Expression = 'Length'; Descending = $true }, { $_ })) {
                    $task = @($word -split ' ')
                    $rest = @($said | Where-Object { $_ -notin $task })
                    $other = @($rest | Where-Object { -not $lexicon.StopWords.Contains($_) -and $_ -notin $nouns })
                    if ($other.Count -gt 0) { continue }
                    # The words of the task, in their order, at the start of what is left
                    $kept = @($said | Where-Object { $_ -in $task })
                    if (($kept -join ' ') -ne $word) { continue }

                    # "{Path}{/}Images" is a folder inside the one given; a path with a space is said in quotes
                    $separator = '\'
                    if ($path.Contains('/')) { $separator = '/' }
                    $root = $path.TrimEnd('\', '/')
                    if (-not $root) { $root = $path }
                    $steps = @(foreach ($step in @($method.Steps[$language])) {
                            $inside = [regex]::Replace($step, '\{Path\}\{/\}([^\s"]+)', { param($found) Format-LambekMethodPath -Path "$root$separator$($found.Groups[1].Value)" })
                            $inside.Replace('{Path}', (Format-LambekMethodPath -Path $path))
                        })
                    return [pscustomobject]@{
                        Method   = $name
                        Word     = $word
                        Language = $language
                        Path     = $path
                        Steps    = $steps
                    }
                }
            }
        }
    }
    return $null
}

function Format-LambekMethodPath {
    param([string] $Path)

    # A path with a space is said in quotes, so the step reads it whole
    if ($Path -match '\s') { return '"' + $Path + '"' }
    return $Path
}
