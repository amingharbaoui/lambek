#Requires -Version 7.6
<#
.SYNOPSIS
    Proposes, for each action of the packs, the words WordNet and WOLF put next to its verbs, to review by hand.
.DESCRIPTION
    Only the senses the action means are used: the synsets two of its own verbs share (see Get-LambekDomainSense).
    "=" marks a synonym, "<" a narrower way to do it. A word goes into the BaseForms of a pack only once a person
    has checked that it means the action on files: WordNet alone would read "kill" as "erase".
.EXAMPLE
    ./tools/Find-LambekSynonym.ps1 -Pack ./dsl/files -Language fr
#>
param(
    [Parameter(Mandatory)] [string[]] $Pack,
    [ValidateSet('en', 'fr')] [string] $Language = 'en'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1') -Force
foreach ($path in $Pack) { Import-LambekPack -Path $path | Out-Null }

& (Get-Module Lambek) {
    param($Language)

    $dictionary = Get-LambekDictionary -Language $Language
    $domain = Get-LambekDomainSense -Language $Language
    $vocabulary = (Get-LambekLexicon -Language $Language).Vocabulary
    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            $found = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
            foreach ($verb in $action.Verbs) {
                if (-not $domain.ContainsKey($verb)) { continue }
                foreach ($synset in $domain[$verb]) {
                    foreach ($word in $dictionary.Members($synset, $Language)) {
                        if (-not $vocabulary.Contains($word)) { $found[$word] = "=$verb" }
                    }
                    foreach ($link in $dictionary.Links($synset)) {
                        if (-not $link.StartsWith('hypo:')) { continue }
                        foreach ($word in $dictionary.Members($link.Substring(5), $Language)) {
                            if (-not $vocabulary.Contains($word) -and -not $found.ContainsKey($word)) { $found[$word] = "<$verb" }
                        }
                    }
                }
            }
            [pscustomobject]@{ Action = $action.Id; Proposals = @($found.GetEnumerator() | ForEach-Object { "$($_.Key)$($_.Value)" }) }
        }
    }
} $Language
