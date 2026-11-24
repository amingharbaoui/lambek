#Requires -Version 7.6
<#
.SYNOPSIS
    Lambek learns which adjectives say the contrary of each other ("grand" and "petit"), to read one compared the
    other way round ("Rex est plus petit que Max": Max is more grand than Rex): engine/Lambek/Data/Forms/<language>.antonyms.
    Nothing in it is written by hand.
.DESCRIPTION
    Two sources that do not come from each other must say it, or it is not kept:
      - Wiktionary (CC BY-SA 4.0 and GFDL), as Wiktextract reads it, the English edition: the antonyms of each
        adjective of the language, of the word or of one of its senses, kaikki.org giving a file for each language:
        https://kaikki.org/dictionary/<Language>/kaikki.org-dictionary-<Language>.jsonl
      - the wordnet of the language Lambek reads (engine/Lambek/Data/Dictionaries): the members of the meanings an
        adjective's meanings are the antonym of (WordNet's "!", kept as "anti").
    A word and another are each other's contrary when both sources link them (either way round), and each has no
    other contrary both sources give: a word of several contraries ("old": "young" and "new") is left out, as one of
    them would be wrong where the other is meant. A language whose wordnet has no antonyms learns none.
.EXAMPLE
    ./tools/Learn-LambekAntonyms.ps1 -Language fr -Wiktionary ../kaikki/kaikki.org-dictionary-French.jsonl
#>
param(
    [Parameter(Mandatory)]
    [string] $Language,

    # The file of kaikki.org for the language (JSON lines, one word a line; gzipped or not)
    [Parameter(Mandatory)]
    [string] $Wiktionary,

    [string] $OutFile = (Join-Path $PSScriptRoot "../engine/Lambek/Data/Forms/$Language.antonyms")
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force
$module = Get-Module Lambek
$plain = { param([string] $text) & $module { param($t) ConvertTo-LambekNormalizedText -Text $t } $text }
$dictionary = & $module { param($l) Get-LambekDictionary -Language $l } $Language
if ($dictionary -isnot [LambekDictionary]) { throw "No wordnet for '$Language' (engine/Lambek/Data/Dictionaries)." }

# What Wiktionary says: each adjective with its antonyms, both ways round, one word each
$said = @{}
$link = {
    param([string] $a, [string] $b)
    if (-not $a -or -not $b -or $a -eq $b -or $a -match '[\s_]' -or $b -match '[\s_]') { return }
    if (-not $said.ContainsKey($a)) { $said[$a] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
    [void] $said[$a].Add($b)
}
$path = [IO.Path]::GetFullPath($Wiktionary)
$stream = [IO.File]::OpenRead($path)
$text = $(if ($path.EndsWith('.gz')) { [IO.Compression.GZipStream]::new($stream, [IO.Compression.CompressionMode]::Decompress) } else { $stream })
$reader = [IO.StreamReader]::new($text, [Text.Encoding]::UTF8)
try {
    while ($null -ne ($line = $reader.ReadLine())) {
        if (-not $line.Contains('"antonyms"') -or -not $line.Contains('"pos": "adj"')) { continue }
        $entry = $line | ConvertFrom-Json -AsHashtable
        if ($entry['pos'] -ne 'adj') { continue }
        $word = & $plain "$($entry['word'])"
        $named = [System.Collections.Generic.List[object]]::new()
        if ($entry['antonyms']) { foreach ($one in $entry['antonyms']) { $named.Add($one) } }
        foreach ($sense in @($entry['senses'])) { if ($sense -and $sense['antonyms']) { foreach ($one in $sense['antonyms']) { $named.Add($one) } } }
        foreach ($one in $named) {
            $other = & $plain "$($one['word'])"
            & $link $word $other
            & $link $other $word
        }
    }
}
finally { $reader.Dispose() }

# What the wordnet says of the same words: the members of the meanings each adjective meaning is the antonym of
$wordnet = {
    param([string] $word)
    $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($sense in $dictionary.Senses($word, $Language, 'a')) {
        foreach ($to in $dictionary.Links($sense)) {
            if (-not $to.StartsWith('anti:')) { continue }
            foreach ($member in $dictionary.Members($to.Substring(5), $Language)) { [void] $found.Add((& $plain $member)) }
        }
    }
    , $found
}
$both = @{}
foreach ($word in @($said.Keys | Sort-Object)) {
    $net = & $wordnet $word
    $agreed = @($said[$word] | Where-Object { $net.Contains($_) } | Sort-Object -Unique)
    if ($agreed.Count -gt 0) { $both[$word] = $agreed }
}
# Each other's only contrary, the two sources agreeing (a link the wordnet gives one way round only counts too)
foreach ($word in @($both.Keys)) {
    foreach ($other in $both[$word]) {
        if (-not $both.ContainsKey($other)) { $both[$other] = @($word) }
        elseif ($word -notin $both[$other]) { $both[$other] = @(@($both[$other]) + $word | Sort-Object -Unique) }
    }
}
$pairs = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
foreach ($word in $both.Keys) {
    if (@($both[$word]).Count -ne 1) { continue }
    $other = @($both[$word])[0]
    if (-not $both.ContainsKey($other) -or @($both[$other]).Count -ne 1 -or @($both[$other])[0] -ne $word) { continue }
    $first, $second = @($word, $other) | Sort-Object -CaseSensitive
    [void] $pairs.Add("$first`t$second")
}

$named = (& $module { param($l) Get-LambekDictionarySource -Language $l } $Language)
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("#lambek-antonyms 1 $Language")
$lines.Add('#source Wiktionary, English edition, by Wiktextract (kaikki.org), CC BY-SA 4.0 and GFDL')
$lines.Add("#source $named")
foreach ($pair in $pairs) { $lines.Add($pair) }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
"Written $OutFile"
"  $($pairs.Count) pairs from $($said.Count) adjectives Wiktionary gives antonyms of"
