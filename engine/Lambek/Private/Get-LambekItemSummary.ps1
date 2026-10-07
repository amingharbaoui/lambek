function Get-LambekItemSummary {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Items
    )

    # What a step worked on, in numbers: files and folders, their size, the largest and the newest
    $files = 0
    $folders = 0
    $bytes = 0L
    $largest = $null
    $newest = $null
    $extensions = [System.Collections.Generic.SortedDictionary[string, int]]::new([System.StringComparer]::Ordinal)
    foreach ($item in @($Items | Where-Object { $null -ne $_ })) {
        $isFolder = $item -is [System.IO.DirectoryInfo] -or ($item.PSObject.Properties['PSIsContainer'] -and $item.PSIsContainer)
        if ($isFolder) { $folders++; continue }
        $files++
        $length = 0L
        if ($item.PSObject.Properties['Length'] -and $item.Length -is [long]) { $length = $item.Length }
        $bytes += $length
        $name = [string] $item
        if ($item.PSObject.Properties['Name']) { $name = [string] $item.Name }
        # Ties go to the smaller name, so the same files always give the same sentence
        if (-not $largest -or $length -gt $largest.Bytes -or ($length -eq $largest.Bytes -and [string]::CompareOrdinal($name, $largest.Name) -lt 0)) {
            $largest = [pscustomobject]@{ Name = $name; Bytes = $length }
        }
        if ($item.PSObject.Properties['LastWriteTime']) {
            $when = [datetime] $item.LastWriteTime
            if (-not $newest -or $when -gt $newest.When -or ($when -eq $newest.When -and [string]::CompareOrdinal($name, $newest.Name) -lt 0)) {
                $newest = [pscustomobject]@{ Name = $name; When = $when }
            }
        }
        $extension = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
        if ($extension) { $extensions[$extension] = 1 + $(if ($extensions.ContainsKey($extension)) { $extensions[$extension] } else { 0 }) }
    }

    [pscustomobject]@{
        Files      = $files
        Folders    = $folders
        Bytes      = $bytes
        Largest    = $largest
        Newest     = $newest
        Extensions = $extensions
    }
}

function Get-LambekReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Step,

        [Parameter(Mandatory)]
        [pscustomobject] $Summary,

        [Parameter(Mandatory)]
        [string] $Language,

        # Only what was done, without the largest and the newest
        [switch] $Short
    )

    # Data to text: the facts of the run, said with the verb of the action. Nothing is said that the run did not give
    $answer = (Get-LambekLexicon -Language $Language).Answer
    $report = $answer.Report
    $count = $Summary.Files + $Summary.Folders
    if ($count -eq 0) { return $report.None }

    # "3 files", "1 folder", or "4 items" for both
    $noun = 'item'
    if ($Summary.Folders -eq 0) { $noun = 'file' }
    elseif ($Summary.Files -eq 0) { $noun = 'folder' }
    $things = Format-LambekPlural -Template $report.Nouns[$noun] -Language $Language -Values @($count)
    $size = $null
    if ($Summary.Bytes -gt 0) { $size = Format-LambekHumanValue -Name 'Size' -Value $Summary.Bytes -Units $answer.Units }

    # A read finds; a change says its verb in the past ("deleted", "copied")
    if (-not @($Step.Writes).Count -and $Step.Risk -eq 'low') {
        $sentence = $report.Read -f $things, $(if ($size) { $report.Total -f $size } else { '' })
    }
    else {
        # The verb of the action, as its pack says it ("supprimer", "delete")
        $found = Get-LambekAction -Id $Step.Action
        $types = @(foreach ($word in $found.Action.Verbs) {
                if ($found.Pack.Words.ContainsKey($Language) -and $found.Pack.Words[$Language].ContainsKey($word)) { @($found.Pack.Words[$Language][$word]) -match '^s\b' }
            })
        $verb = Get-LambekActionVerb -Action $found.Action -Language $Language -Types $types
        $done = $null
        $dictionary = Get-LambekDictionary -Language $Language
        if ($verb -and $dictionary) { $done = $dictionary.Participle($verb, $Language) }
        if (-not $done) { return (Format-LambekPlural -Template $answer.Done -Language $Language -Values @($count)) }
        $sentence = $report.Did -f $done, $things, $(if ($size) { $report.Size -f $size } else { '' })
        if ($Step.Parameters.Contains('Destination')) { $sentence = $sentence.TrimEnd('.') + ($report.To -f $Step.Parameters['Destination']) + '.' }
    }
    if ($Short -or $count -lt 2) { return $sentence }

    # Quantity: the largest file when there is more than one, the newest when it is another one
    $more = [System.Collections.Generic.List[string]]::new()
    $more.Add($sentence)
    if ($Summary.Largest -and $Summary.Largest.Bytes -gt 0) {
        $more.Add(($report.Largest -f $Summary.Largest.Name, (Format-LambekHumanValue -Name 'Size' -Value $Summary.Largest.Bytes -Units $answer.Units)))
    }
    if ($Summary.Newest -and (-not $Summary.Largest -or $Summary.Newest.Name -ne $Summary.Largest.Name)) {
        $culture = [cultureinfo]::GetCultureInfo($answer.Files.Culture)
        $more.Add(($report.Newest -f $Summary.Newest.Name, $Summary.Newest.When.ToString($answer.Files.DateFormat, $culture)))
    }
    return $more -join ' '
}
