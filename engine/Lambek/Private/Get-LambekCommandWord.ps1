function Get-LambekCommandWord {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    # PowerShell aliases of the command each action runs: del and erase run Remove-Item, so they mean delete
    $words = @{}
    # An action that names its command first ("delete" runs Remove-Item even when its last line moves to the trash),
    # then the command each other action ends with
    foreach ($pass in 'named', 'found') {
        foreach ($pack in $script:Packs.Values) {
            if (-not $pack.Words.ContainsKey($Language)) { continue }

            foreach ($action in $pack.Actions) {
                if (-not $action.ContainsKey('Template')) { continue }
                if (($pass -eq 'named') -ne $action.ContainsKey('Command')) { continue }

                # The command that does the work: the last one that is not a filter (Where-Object, Select-Object, Get-Date)
                $effect = $null
                if ($action.ContainsKey('Command')) { $effect = $action.Command }
                else {
                    foreach ($line in $action.Template) {
                        foreach ($command in $pack.Commands) {
                            if ($line -match "(^|[\s|(])$([regex]::Escape($command))(\s|$)" -and $command -notmatch '-(Object|Date)$') { $effect = $command }
                        }
                    }
                }
                if (-not $effect) { continue }

                # The verb of the action in this language
                $verb = @($action.Verbs | Where-Object { $pack.Words[$Language].ContainsKey($_) }) | Select-Object -First 1
                if (-not $verb) { continue }

                foreach ($alias in @(Get-Alias -Definition $effect -ErrorAction SilentlyContinue)) {
                    $name = $alias.Name.ToLowerInvariant()
                    # A word of three letters or more, or one with no vowel ("rm", "cp"): "ni" or "mi" are words of French
                    if ($name -notmatch '^[a-z]+$' -or ($name.Length -lt 3 -and $name -match '[aeiouy]')) { continue }
                    if (-not $words.ContainsKey($name)) { $words[$name] = $verb }
                }
            }
        }
    }
    return $words
}
