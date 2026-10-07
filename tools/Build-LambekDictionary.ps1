#Requires -Version 7.4
<#
.SYNOPSIS
    Compiles the free dictionaries into the packs Lambek reads: engine/Lambek/Data/Dictionaries/*.dict.gz
.DESCRIPTION
    Sources (all free, none paid):
      - Open English WordNet 2022 (CC BY 4.0, derived from Princeton WordNet under the WordNet License)
      - Princeton WordNet 3.0 index.sense, only to move WOLF onto the synsets of Open English WordNet
      - WOLF, from the Open Multilingual Wordnet 1.4 (CeCILL-C)
      - Lefff 3.4 (LGPL-LR)
      - Open Multilingual Wordnet 1.4: MCR Spanish (CC BY 3.0), MultiWordNet Italian (CC BY 3.0),
        OpenWN-PT Portuguese (CC BY-SA), Open Dutch WordNet (CC BY-SA 4.0)
      - OdeNet German (CC BY-SA 4.0), carried to Princeton WordNet 3.0 by the Collaborative Interlingual Index (CC BY 4.0)
      - UniMorph (CC BY-SA 3.0) for the forms of Spanish, Italian, Portuguese, Dutch and German
    The same sources always give the same files: every list is sorted, and gzip writes no date.
.EXAMPLE
    ./tools/Build-LambekDictionary.ps1 -WordNet ./wordnet2022 -WordNet30 ./wordnet -Wolf ./omw-1.4/fra/wn-data-fra.tab -Lefff ./lefff-3.4.mlex -Omw ./omw-1.4 -UniMorph . -OdeNet ./odenet/odenet_oneline.xml -Cili ./cili/ili-map-pwn30.tab
.NOTES
    Free sources: https://github.com/omwn/omw-data, https://github.com/unimorph (spa, ita, por, nld, deu: cloned as um-spa...),
    https://github.com/hdaSprachtechnologie/odenet, https://github.com/globalwordnet/cili
#>
param(
    [Parameter(Mandatory)] [string] $WordNet,
    [Parameter(Mandatory)] [string] $WordNet30,
    [Parameter(Mandatory)] [string] $Wolf,
    [Parameter(Mandatory)] [string] $Lefff,
    # The other languages; without them, only English and French are built
    [string] $Omw,
    [string] $UniMorph,
    [string] $OdeNet,
    [string] $Cili,
    [string] $Output = (Join-Path $PSScriptRoot '../engine/Lambek/Data/Dictionaries')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ordinal = [System.StringComparer]::Ordinal

# Relations kept: hypernym, instance hypernym, also see, verb group, similar to, antonym.
# Hyponyms are the hypernyms read backwards: the engine finds them when it loads the graph
$kept = [System.Collections.Generic.HashSet[string]]::new([string[]] @('@', '@i', '^', '$', '&', '!'))
$names = @{ '@' = 'hyper'; '@i' = 'hyper'; '^' = 'also'; '$' = 'group'; '&' = 'similar'; '!' = 'anti' }
$files = @{ n = 'noun'; v = 'verb'; a = 'adj'; r = 'adv' }

function Write-LambekPack {
    param([string] $Path, [System.Collections.Generic.List[string]] $Lines)

    # Gzip without a date or a name, so the file only changes when its lines do
    $stream = [IO.File]::Create($Path)
    try {
        $zip = [IO.Compression.GZipStream]::new($stream, [IO.Compression.CompressionLevel]::SmallestSize)
        $writer = [IO.StreamWriter]::new($zip, [Text.UTF8Encoding]::new($false))
        $writer.NewLine = "`n"
        foreach ($line in $Lines) { $writer.WriteLine($line) }
        $writer.Dispose()
    }
    finally { $stream.Dispose() }
    '{0,-12} {1,8} lines {2,6:N2} MB' -f (Split-Path $Path -Leaf), $Lines.Count, ((Get-Item $Path).Length / 1MB)
}

function ConvertTo-LambekPlainForm {
    param([string] $Text)

    # Same as the engine: no accents, lower case
    $builder = [Text.StringBuilder]::new()
    foreach ($character in $Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void] $builder.Append($character) }
    }
    return $builder.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
}

function Get-LambekHeader {
    param([string] $Kind, [string[]] $Sources)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("#lambek-dictionary 1 $Kind")
    foreach ($source in $Sources) { $lines.Add("#source $source") }
    return , $lines
}

New-Item -ItemType Directory -Path $Output -Force | Out-Null

# The synsets of Open English WordNet: relations and definitions
$graph = [System.Collections.Generic.SortedDictionary[string, string]]::new($ordinal)
$glosses = [System.Collections.Generic.SortedDictionary[string, string]]::new($ordinal)
foreach ($pos in 'n', 'v', 'a', 'r') {
    foreach ($line in [IO.File]::ReadLines((Join-Path $WordNet "data.$($files[$pos])"))) {
        if ($line.Length -eq 0 -or $line[0] -eq ' ') { continue }
        $bar = $line.IndexOf('|')
        $fields = $line.Substring(0, $bar).Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        $id = $fields[0] + $pos
        $count = [Convert]::ToInt32($fields[3], 16)
        $at = 4 + 2 * $count
        $pointers = [int] $fields[$at]
        $at++
        $links = [System.Collections.Generic.SortedSet[string]]::new($ordinal)
        for ($k = 0; $k -lt $pointers; $k++) {
            $symbol = $fields[$at]
            $target = $fields[$at + 1] + $(if ($fields[$at + 2] -eq 's') { 'a' } else { $fields[$at + 2] })
            if ($kept.Contains($symbol)) { [void] $links.Add("$($names[$symbol]):$target") }
            $at += 4
        }
        $graph[$id] = $links -join ','
        $glosses[$id] = $line.Substring($bar + 1).Trim()
    }
}

$lines = Get-LambekHeader -Kind 'graph' -Sources @('Open English WordNet 2022, CC BY 4.0, https://en-word.net', 'Princeton WordNet 3.1, WordNet License, https://wordnet.princeton.edu')
foreach ($id in $graph.Keys) { $lines.Add("S`t$id`t$($graph[$id])") }
Write-LambekPack -Path (Join-Path $Output 'wordnet.dict.gz') -Lines $lines

# The definitions apart: they are read only when someone asks what a word means
$lines = Get-LambekHeader -Kind 'glosses' -Sources @('Open English WordNet 2022, CC BY 4.0, https://en-word.net')
foreach ($id in $glosses.Keys) { $lines.Add("G`t$id`t$($glosses[$id])") }
Write-LambekPack -Path (Join-Path $Output 'glosses.dict.gz') -Lines $lines

# English words: their senses, most frequent first, and the irregular forms
$senses = [System.Collections.Generic.Dictionary[string, string[]]]::new($ordinal)
$lines = Get-LambekHeader -Kind 'en' -Sources @('Open English WordNet 2022, CC BY 4.0, https://en-word.net')
$words = [System.Collections.Generic.SortedDictionary[string, string]]::new($ordinal)
foreach ($pos in 'n', 'v', 'a', 'r') {
    foreach ($line in [IO.File]::ReadLines((Join-Path $WordNet "index.$($files[$pos])"))) {
        if ($line.Length -eq 0 -or $line[0] -eq ' ') { continue }
        $fields = $line.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        $count = [int] $fields[2]
        $pointers = [int] $fields[3]
        $ids = @($fields[(4 + $pointers + 2)..(4 + $pointers + 1 + $count)] | ForEach-Object { "$_$pos" })
        $senses["$($fields[0])|$pos"] = $ids
        $words["$($fields[0])`t$pos"] = $ids -join ','
    }
}
foreach ($key in $words.Keys) { $lines.Add("W`t$key`t$($words[$key])") }
$exceptions = [System.Collections.Generic.SortedSet[string]]::new($ordinal)
foreach ($pos in 'n', 'v', 'a', 'r') {
    foreach ($line in [IO.File]::ReadLines((Join-Path $WordNet "$($files[$pos]).exc"))) {
        $fields = $line.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        for ($k = 1; $k -lt $fields.Count; $k++) { [void] $exceptions.Add("X`t$($fields[0])`t$($fields[$k])`t$pos") }
    }
}
foreach ($line in $exceptions) { $lines.Add($line) }
Write-LambekPack -Path (Join-Path $Output 'en.dict.gz') -Lines $lines

# WOLF names the synsets of Princeton WordNet 3.0: the sense keys carry them to Open English WordNet
$keysOld = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new($ordinal)
$types = @{ '1' = 'n'; '2' = 'v'; '3' = 'a'; '4' = 'r'; '5' = 'a' }
foreach ($line in [IO.File]::ReadLines((Join-Path $WordNet30 'index.sense'))) {
    $fields = $line.Split(' ')
    $id = $fields[1] + $types[$fields[0].Split('%')[1].Substring(0, 1)]
    if (-not $keysOld.ContainsKey($id)) { $keysOld[$id] = [System.Collections.Generic.List[string]]::new() }
    $keysOld[$id].Add($fields[0])
}
$keysNew = [System.Collections.Generic.Dictionary[string, string]]::new($ordinal)
foreach ($line in [IO.File]::ReadLines((Join-Path $WordNet 'index.sense'))) {
    $fields = $line.Split(' ')
    $keysNew[$fields[0]] = $fields[1] + $types[$fields[0].Split('%')[1].Substring(0, 1)]
}

# The rank of a synset: its best place among the senses of its English words (0 is the most frequent)
$rank = [System.Collections.Generic.Dictionary[string, int]]::new($ordinal)
foreach ($entry in $senses.GetEnumerator()) {
    for ($k = 0; $k -lt $entry.Value.Count; $k++) {
        $id = $entry.Value[$k]
        if (-not $rank.ContainsKey($id) -or $k -lt $rank[$id]) { $rank[$id] = $k }
    }
}

function Move-LambekSense {
    param([System.Collections.Generic.List[object]] $Entries, [string] $Name)

    # Lemmas on synsets of Princeton WordNet 3.0 ("00001740-n"), moved to Open English WordNet by their sense keys
    $table = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.SortedSet[string]]]::new($ordinal)
    $moved = 0
    $lost = 0
    foreach ($entry in $Entries) {
        $old = $entry.Old.Replace('-', '').Replace('s', 'a')
        if (-not $keysOld.ContainsKey($old)) { $lost++; continue }

        # The new synset most of its sense keys point to, the smallest on a tie
        $votes = [System.Collections.Generic.SortedDictionary[string, int]]::new($ordinal)
        foreach ($key in $keysOld[$old]) {
            if ($keysNew.ContainsKey($key)) { $votes[$keysNew[$key]] = 1 + $(if ($votes.ContainsKey($keysNew[$key])) { $votes[$keysNew[$key]] } else { 0 }) }
        }
        if ($votes.Count -eq 0) { $lost++; continue }
        $best = $null
        foreach ($vote in $votes.GetEnumerator()) { if (-not $best -or $vote.Value -gt $votes[$best]) { $best = $vote.Key } }

        $lemma = $entry.Lemma.Trim().Replace(' ', '_')
        if (-not $lemma -or $lemma.Contains("`t") -or $lemma.Contains(',')) { $lost++; continue }
        $pos = $best.Substring($best.Length - 1)
        $key = "$lemma`t$pos"
        if (-not $table.ContainsKey($key)) { $table[$key] = [System.Collections.Generic.SortedSet[string]]::new($ordinal) }
        [void] $table[$key].Add($best)
        $moved++
    }
    "${Name}: $moved senses moved to Open English WordNet, $lost without a match"
    $script:Moved = $table
}

function Add-LambekWordLine {
    param([System.Collections.Generic.List[string]] $Lines, [object] $Table)

    $sorted = [System.Collections.Generic.SortedDictionary[string, object]]::new($ordinal)
    foreach ($entry in $Table.GetEnumerator()) { $sorted[$entry.Key] = $entry.Value }
    foreach ($entry in $sorted.GetEnumerator()) {
        # The most frequent English sense first, then the synset number
        $ordered = [System.Collections.Generic.SortedSet[string]]::new($ordinal)
        foreach ($id in $entry.Value) {
            $place = 999
            if ($rank.ContainsKey($id)) { $place = $rank[$id] }
            [void] $ordered.Add(('{0:D3}{1}' -f $place, $id))
        }
        $Lines.Add("W`t$($entry.Key)`t$((@($ordered) | ForEach-Object { $_.Substring(3) }) -join ',')")
    }
}

function Add-LambekFormLine {
    param([System.Collections.Generic.List[string]] $Lines, [object] $Lemmas)

    # Every form of a lemma on one line ("form:tag"), then every form without accents, sorted,
    # with the lemmas (their line numbers) it may come from
    $index = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.SortedSet[int]]]::new($ordinal)
    $number = 0
    foreach ($entry in $Lemmas.GetEnumerator()) {
        $forms = [System.Collections.Generic.SortedSet[string]]::new([string[]] $entry.Value, $ordinal)
        $Lines.Add("L`t$($entry.Key)`t$($forms -join '|')")
        foreach ($item in $forms) {
            $form = ConvertTo-LambekPlainForm -Text $item.Substring(0, $item.LastIndexOf(':'))
            if (-not $index.ContainsKey($form)) { $index[$form] = [System.Collections.Generic.SortedSet[int]]::new() }
            [void] $index[$form].Add($number)
        }
        $number++
    }
    foreach ($entry in $index.GetEnumerator()) { $Lines.Add("F`t$($entry.Key)`t$($entry.Value -join ',')") }
}

$wolfSenses = [System.Collections.Generic.List[object]]::new()
foreach ($line in [IO.File]::ReadLines($Wolf)) {
    if ($line.StartsWith('#')) { continue }
    $fields = $line.Split("`t")
    if ($fields.Count -lt 3 -or $fields[1] -ne 'fra:lemma') { continue }
    $wolfSenses.Add([pscustomobject]@{ Old = $fields[0]; Lemma = $fields[2] })
}
Move-LambekSense -Entries $wolfSenses -Name 'WOLF'
$french = $script:Moved

$lines = Get-LambekHeader -Kind 'fr' -Sources @('WOLF 1.0b from the Open Multilingual Wordnet 1.4, CeCILL-C, https://almanach.inria.fr', 'Lefff 3.4, LGPL-LR, https://almanach.inria.fr')
Add-LambekWordLine -Lines $lines -Table $french

# Lefff: every form of a lemma on one line, "form:tag", for speaking.
# Proper nouns are left out: they are names, not words to understand
$lemmas = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new($ordinal)
foreach ($line in [IO.File]::ReadLines($Lefff)) {
    $fields = $line.Split("`t")
    if ($fields.Count -lt 3 -or $fields[1] -eq 'np' -or $fields[1].StartsWith('ponct') -or $fields[1].StartsWith('parent')) { continue }
    # "|", "," and ":" hold the line together
    if ($fields[0].Contains('|') -or $fields[0].Contains(':') -or $fields[0].Contains(',')) { continue }
    $tag = ''
    if ($fields.Count -gt 3) { $tag = $fields[3] }
    $key = "$($fields[2])`t$($fields[1])"
    if (-not $lemmas.ContainsKey($key)) { $lemmas[$key] = [System.Collections.Generic.List[string]]::new() }
    $lemmas[$key].Add("$($fields[0]):$tag")
}

Add-LambekFormLine -Lines $lines -Lemmas $lemmas
Write-LambekPack -Path (Join-Path $Output 'fr.dict.gz') -Lines $lines

# The other languages: the wordnet of each (on Princeton WordNet 3.0), and the forms of UniMorph for reading
if (-not $Omw -or -not $UniMorph) { return }
$sources = @{
    es = @{ File = 'mcr/wn-data-spa.tab'; Code = 'spa'; Source = 'Multilingual Central Repository 3.0 from the Open Multilingual Wordnet 1.4, CC BY 3.0, https://adimen.si.ehu.es/web/MCR' }
    it = @{ File = 'ita/wn-data-ita.tab'; Code = 'ita'; Source = 'MultiWordNet from the Open Multilingual Wordnet 1.4, CC BY 3.0, https://multiwordnet.fbk.eu' }
    pt = @{ File = 'por/wn-data-por.tab'; Code = 'por'; Source = 'OpenWN-PT from the Open Multilingual Wordnet 1.4, CC BY-SA, https://github.com/own-pt/openWordnet-PT' }
    nl = @{ File = 'nld/wn-data-nld.tab'; Code = 'nld'; Source = 'Open Dutch WordNet from the Open Multilingual Wordnet 1.4, CC BY-SA 4.0, https://github.com/cltl/OpenDutchWordnet' }
    de = @{ File = $null; Code = 'deu'; Source = 'OdeNet 1.3, CC BY-SA 4.0, https://github.com/hdaSprachtechnologie/odenet' }
}
$categories = @{ V = 'v'; N = 'n'; ADJ = 'a'; ADV = 'r' }

# German: the synsets of OdeNet name an interlingual index, the index names Princeton WordNet 3.0
$ili = [System.Collections.Generic.Dictionary[string, string]]::new($ordinal)
if ($Cili -and (Test-Path -LiteralPath $Cili)) {
    foreach ($line in [IO.File]::ReadLines($Cili)) {
        $fields = $line.Split("`t")
        if ($fields.Count -ge 2) { $ili[$fields[0]] = $fields[1] }
    }
}

foreach ($language in 'de', 'es', 'it', 'nl', 'pt') {
    $source = $sources[$language]
    $entries = [System.Collections.Generic.List[object]]::new()
    $origins = [System.Collections.Generic.List[string]]::new()
    if ($language -eq 'de') {
        if (-not $OdeNet -or -not (Test-Path -LiteralPath $OdeNet) -or $ili.Count -eq 0) { continue }
        # One entry or synset per line; the file is not always well-formed XML, so it is read line by line
        $synsets = [System.Collections.Generic.Dictionary[string, string]]::new($ordinal)
        $words = [System.Collections.Generic.List[object]]::new()
        foreach ($line in [IO.File]::ReadLines($OdeNet)) {
            $synset = [regex]::Match($line, '<Synset id="(?<id>[^"]+)" ili="(?<ili>i\d+)"')
            if ($synset.Success -and $ili.ContainsKey($synset.Groups['ili'].Value)) { $synsets[$synset.Groups['id'].Value] = $ili[$synset.Groups['ili'].Value] }
            $lemma = [regex]::Match($line, '<Lemma writtenForm="(?<w>[^"]+)"')
            if ($lemma.Success) {
                foreach ($sense in [regex]::Matches($line, 'synset="(?<s>[^"]+)"')) { $words.Add(@([System.Net.WebUtility]::HtmlDecode($lemma.Groups['w'].Value), $sense.Groups['s'].Value)) }
            }
        }
        foreach ($word in $words) {
            if ($synsets.ContainsKey($word[1])) { $entries.Add([pscustomobject]@{ Old = $synsets[$word[1]]; Lemma = $word[0] }) }
        }
        $origins.Add($source.Source)
        $origins.Add('Collaborative Interlingual Index, CC BY 4.0, https://github.com/globalwordnet/cili')
    }
    else {
        foreach ($line in [IO.File]::ReadLines((Join-Path $Omw $source.File))) {
            if ($line.StartsWith('#')) { continue }
            $fields = $line.Split("`t")
            if ($fields.Count -lt 3 -or $fields[1] -notmatch '(^|:)lemma$') { continue }
            $entries.Add([pscustomobject]@{ Old = $fields[0]; Lemma = $fields[2] })
        }
        $origins.Add($source.Source)
    }
    Move-LambekSense -Entries $entries -Name $language
    $table = $script:Moved

    # The forms of the lemmas the wordnet knows (the others would only fill the memory)
    $known = [System.Collections.Generic.HashSet[string]]::new($ordinal)
    foreach ($key in $table.Keys) { [void] $known.Add((ConvertTo-LambekPlainForm -Text $key.Split("`t")[0].Replace('_', ' '))) }
    $lemmas = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new($ordinal)
    $path = Join-Path $UniMorph "um-$($source.Code)/$($source.Code)"
    if (Test-Path -LiteralPath $path) {
        foreach ($line in [IO.File]::ReadLines($path)) {
            $fields = $line.Split("`t")
            if ($fields.Count -lt 3) { continue }
            $features = $fields[2].Split(';')
            # "V.PTCP" and "V.CVB" (participles, gerunds) are forms of the verb
            $category = $categories[($features[0] -replace '^V\..*$', 'V')]
            if (-not $category -or -not $known.Contains((ConvertTo-LambekPlainForm -Text $fields[0]))) { continue }
            if ($fields[1] -match '[|:,\t]' -or $fields[0] -match '[|:,\t]') { continue }
            $key = "$($fields[0])`t$category"
            if (-not $lemmas.ContainsKey($key)) { $lemmas[$key] = [System.Collections.Generic.List[string]]::new() }
            $lemmas[$key].Add("$($fields[1]):$(($features | Select-Object -Skip 1) -join '.')")
        }
        $origins.Add("UniMorph $($source.Code), CC BY-SA 3.0, https://unimorph.github.io")
    }

    $lines = Get-LambekHeader -Kind $language -Sources $origins
    Add-LambekWordLine -Lines $lines -Table $table
    Add-LambekFormLine -Lines $lines -Lemmas $lemmas
    Write-LambekPack -Path (Join-Path $Output "$language.dict.gz") -Lines $lines
}
