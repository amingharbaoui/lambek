#Requires -Version 7.6
<#
.SYNOPSIS
    Lambek learns whether a language leaves out the one a sentence is about ("ladra", "it barks"; "abbaia"), from the
    treebanks of the language, never from a list written by hand: engine/Lambek/Data/Forms/<language>.subject.
.DESCRIPTION
    In the treebanks (CoNLL-U, Universal Dependencies), every main clause whose verb is conjugated, not said to the
    listener nor by the speaker (no Person=1, no Person=2, no Mood=Imp), is counted, and so is every one of them with
    no subject: the head of the clause (the verb, or what a copula joins to) has no child tagged nsubj, csubj or expl,
    with any subtype. The file keeps both counts; the reader takes the one asked of in a sentence that names nobody
    ("ladra?") as the one told of before only in a language that leaves the subject out (Get-LambekSubjectDropped).

    The treebanks: the train files of the treebanks of the forms model of the language, release 2.18 of Universal
    Dependencies (https://github.com/UniversalDependencies, tag r2.18), the same files as Learn-LambekLogicWords.ps1.
.EXAMPLE
    ./tools/Learn-LambekSubject.ps1 -Language es -Treebank ./ud/es_ancora-ud-train.conllu, ./ud/es_gsd-ud-train.conllu
#>
param(
    [Parameter(Mandatory)]
    [string] $Language,

    # Treebanks of the language (CoNLL-U)
    [Parameter(Mandatory)]
    [string[]] $Treebank,

    [string] $OutFile = (Join-Path $PSScriptRoot "../engine/Lambek/Data/Forms/$Language.subject")
)

$ErrorActionPreference = 'Stop'
$out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
$total = 0
$dropped = 0
$sources = [System.Collections.Generic.List[string]]::new()
foreach ($path in @($Treebank | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })) {
    $sentence = [System.Collections.Generic.List[string[]]]::new()
    $count = {
        # (the words of one sentence: id, form, lemma, upos, xpos, feats, head, deprel)
        $byId = @{}
        $children = @{}
        foreach ($word in $sentence) {
            $byId[$word[0]] = $word
            if (-not $children.ContainsKey($word[6])) { $children[$word[6]] = [System.Collections.Generic.List[string[]]]::new() }
            $children[$word[6]].Add($word)
        }
        foreach ($word in $sentence) {
            $feats = "|$($word[5])|"
            if ($feats -notmatch '\|VerbForm=Fin\|' -or $feats -match '\|Person=[12]\|' -or $feats -match '\|Mood=Imp\|') { continue }
            $head = $word
            if (($word[7] -split ':')[0] -in 'cop', 'aux') {
                if (-not $byId.ContainsKey($word[6])) { continue }
                $head = $byId[$word[6]]
            }
            if ($head[7] -ne 'root') { continue }
            $script:total++
            $subject = $children.ContainsKey($head[0]) -and @($children[$head[0]] | Where-Object { ($_[7] -split ':')[0] -in 'nsubj', 'csubj', 'expl' }).Count -gt 0
            if (-not $subject) { $script:dropped++ }
        }
    }
    foreach ($line in [IO.File]::ReadLines($path)) {
        if (-not $line) {
            if ($sentence.Count -gt 0) { & $count; $sentence.Clear() }
            continue
        }
        if ($line.StartsWith('#')) { continue }
        $cells = $line.Split("`t")
        # (the words only: neither the words cut into two nor the empty ones)
        if ($cells.Count -lt 8 -or $cells[0].Contains('-') -or $cells[0].Contains('.')) { continue }
        $sentence.Add($cells)
    }
    if ($sentence.Count -gt 0) { & $count }
    $sources.Add("$(Split-Path $path -Leaf) $((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())")
}
if ($total -eq 0) { throw 'No main clause with a conjugated verb was found in these treebanks.' }
$text = "# lambek-subject-1`tUniversal Dependencies 2.18, train files: $($sources -join ', ')`ndropped`t$dropped`t$total`n"
[IO.File]::WriteAllText($out, $text, [Text.UTF8Encoding]::new($false))
Write-Host ("{0}: {1} of {2} main clauses with no subject ({3:P1})" -f $Language, $dropped, $total, ($dropped / $total))
