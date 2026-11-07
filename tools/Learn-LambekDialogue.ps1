#Requires -Version 7.6
<#
.SYNOPSIS
    Lambek learns the words it talks with in a language that has no dialogue written for it, to be told rules and
    facts and to answer about them: engine/Lambek/Data/Forms/<language>.dialogue.json. Nothing in it is written by hand.
.DESCRIPTION
    - The small words, from the tags of the forms model of the language: its articles are the words most often tagged
      DET with PronType=Art, its speaker the pronouns tagged Person=1 and Number=Sing, and so on (Native/DialogueWords.cs);
      kept only when said at least -Least times in the sentences of the language, so that a word of another language
      quoted in its treebanks ("the" in German) is not one of them.
    - The word that says whose ("von"), from the sentences translated from English: the preposition met the most often
      where English says "of". The verbs that are not what a sentence says (its copulas and auxiliaries), from the same tags and from
      its words of logic (<language>.logic).
    - What it answers, from the sentences translated from English (Tatoeba): "Yes." is "Ja.", "No." is "Nein.",
      "I don't know." is "Ich weiss nicht.", "I understand." is "Ich verstehe." Short answers, the proof after them: a
      sentence that is not said in the translated sentences is not said.
    - How it says that one is of a kind ("Rex ist ein Tier"), from the same sentences: the form of the copula for one
      the most often after a name ("Tom ist", "Tom es") when the English side says "Tom is".

    The keys are those of the dialogue of English, the language the engine is written for; a key Lambek cannot learn
    yet is left empty, and what it would say is not said.
.EXAMPLE
    ./tools/Learn-LambekDialogue.ps1 -Language de -English ../tatoeba/Tatoeba.de-en.en -Other ../tatoeba/Tatoeba.de-en.de -Treebank ./ud/de_gsd-ud-train.conllu
#>
param(
    [Parameter(Mandatory)]
    [string] $Language,

    # The English side and the side of the language, one sentence a line, the same line for the same pair
    [Parameter(Mandatory)]
    [string] $English,

    [Parameter(Mandatory)]
    [string] $Other,

    # Treebanks of the language (CoNLL-U)
    [Parameter(Mandatory)]
    [string[]] $Treebank,

    # The least times a small word must be said in the sentences of the language
    [int] $Least = 100,

    [string] $OutFile = (Join-Path $PSScriptRoot "../engine/Lambek/Data/Forms/$Language.dialogue.json")
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-dialogue-$PID"
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force

$module = Get-Module Lambek
$model = & $module { param($l) Get-LambekFormModel -Language $l } $Language
if (-not $model) { throw "No forms model for '$Language': learn it first (tools/Build-LambekForms.ps1)." }
$logic = & $module { param($l) Get-LambekLogicWord -Language $l } $Language
if (-not $logic) { throw "No words of logic for '$Language': learn them first (tools/Learn-LambekLogicWords.ps1)." }
$treebanks = @(foreach ($path in $Treebank) { [IO.Path]::GetFullPath($path) })
$englishSide = [IO.File]::ReadAllLines([IO.Path]::GetFullPath($English))
$otherSide = [IO.File]::ReadAllLines([IO.Path]::GetFullPath($Other))

# The keys: those of the dialogue of English, every value empty
$shape = (Get-Content -LiteralPath (Join-Path $root 'engine/Lambek/Data/Languages/en.json') -Raw | ConvertFrom-Json -AsHashtable).Dialogue
function Clear-Value {
    param($Value)
    if ($Value -is [string]) { return '' }
    if ($Value -is [System.Collections.IDictionary]) {
        $empty = [ordered]@{}
        foreach ($key in $Value.Keys) { $empty[$key] = Clear-Value $Value[$key] }
        return $empty
    }
    if ($Value -is [System.Collections.IEnumerable]) { return , @() }
    return $Value
}
$dialogue = Clear-Value $shape

# The small words
$lists = [LambekDialogueWords]::Lists($model, $otherSide, $Least)
$of = @([LambekDialogueWords]::Aligned($englishSide, $otherSide, 'of', [string[]] $lists['Prepositions'], 20, 12) | Where-Object { $_ })
# (with the forms it is written in with an article: "vom" is "von dem")
$ofForms = @($of) + @($model.Contractions.Keys | Where-Object { $parts = @($model.Contractions[$_] -split ' '); $parts.Count -eq 2 -and $parts[0] -in $of -and $parts[1] -in $lists['Articles'] })
# A language that does not tag the number of its pronouns ("ik"): the speaker is the one of them met more with "I"
# or "me" than with "we" or "us" in the translated sentences
if ($lists['Speaker'].Count -eq 0) {
    $lists['Speaker'] = [string[]] @(foreach ($word in $lists['Speakers']) {
            $one = [LambekDialogueWords]::With($englishSide, $otherSide, [string[]] @('i', 'me', 'my'), $word, 12)
            $many = [LambekDialogueWords]::With($englishSide, $otherSide, [string[]] @('we', 'us', 'our'), $word, 12)
            if ($one[0] -gt $many[0]) { $word }
        })
}
$copulas = @($logic.Copulas)
$auxiliaries = @(foreach ($form in $lists['Auxiliaries']) { $model.LemmaFor($form, @($model.Tags[$form])[0]) }) | Sort-Object -Unique
$plain = { param($words) @($words | ForEach-Object { & $module { param($t) ConvertTo-LambekNormalizedText -Text $t } $_ } | Where-Object { $_ } | Sort-Object -Unique) }

$categories = $dialogue['Categories']
$categories['Articles'] = & $plain $lists['Articles']
$categories['Definite'] = & $plain (@($lists['Definite']) + @($lists['Demonstratives']))
$categories['Of'] = & $plain $ofForms
$negated = @(if ($logic.Negated) { $logic.Negated }) + @($logic.Elided.Values)
$categories['ObjectArticles'] = & $plain (@($lists['Articles']) + $negated)
$categories['Speaker'] = & $plain $lists['Speaker']
$categories['Addressee'] = & $plain $lists['Addressee']
$categories['Lead'] = & $plain $lists['Conjunctions']
$categories['NotVerbs'] = & $plain (@($copulas) + @($auxiliaries))

$general = $dialogue['General']
$general['Owners'] = & $plain $lists['Owners']
$general['Speakers'] = & $plain $lists['Speakers']
$general['Addressee'] = & $plain $lists['Addressee']
$general['Pronouns'] = & $plain $lists['Pronouns']
$general['Determiners'] = & $plain $lists['Determiners']
$general['Prepositions'] = & $plain $lists['Prepositions']
$general['Auxiliaries'] = & $plain $lists['Auxiliaries']
$general['Negations'] = & $plain $lists['Negations']
$general['Conjunctions'] = & $plain $lists['Conjunctions']
$general['NounLinks'] = & $plain $ofForms
foreach ($name in 'Speakers', 'Addressee', 'Articles', 'Determiners') { if ($dialogue.Contains($name)) { $dialogue[$name] = $general[$(if ($name -eq 'Articles') { 'Determiners' } else { $name })] } }
$dialogue['Articles'] = & $plain $lists['Definite']
$dialogue['Asked'] = & $plain $lists['Interrogatives']
$dialogue['QuestionStarts'] = & $plain $lists['Interrogatives']

# What it answers: the sentences the language says for the English ones
$phrase = { param([string] $Asked) [LambekDialogueWords]::Phrase($englishSide, $otherSide, $Asked) }
$yes = & $phrase 'Yes.'
$no = & $phrase 'No.'
$unknown = & $phrase "I don't know."
$understood = & $phrase 'I understand.'
if ($yes) { $categories['YesShort'] = $yes; $categories['Yes'] = "$yes {0}." }
if ($no) { $categories['NoShort'] = $no; $categories['No'] = $no }
if ($unknown) { $categories['Unknown'] = $unknown; $categories['WhoUnknown'] = $unknown; $dialogue['Say']['NotKnown'] = $unknown }
if ($understood) { $dialogue['Say']['Noted'] = "$understood {0}"; $dialogue['Say']['NotedHere'] = "$understood {0}" }
# (what was told is said back in the user's own words, as they were written: no marks of quotation, which differ
# from one language to another)
$dialogue['Say']['Quote'] = '{0}'
$dialogue['Say']['Quoted'] = '{0}.'
$categories['YesWords'] = & $plain @($yes -replace '[\p{P}]', '')
$categories['NoWords'] = & $plain @($no -replace '[\p{P}]', '')

# How it says that one is of a kind: the copula for one, as the language says it after a name where English says
# "<name> is"
$after = @{}
for ($i = 0; $i -lt $englishSide.Length -and $i -lt $otherSide.Length; $i++) {
    $found = [regex]::Match($englishSide[$i].Trim(), '^(?<name>\p{Lu}\p{Ll}+) is (?:a|an) \p{Ll}+\.$')
    if (-not $found.Success) { continue }
    $words = @($otherSide[$i].Trim() -split '\s+')
    if ($words.Count -lt 3 -or $words[0] -cne $found.Groups['name'].Value) { continue }
    $form = $words[1].ToLowerInvariant()
    $after[$form] = 1 + $(if ($after.ContainsKey($form)) { $after[$form] } else { 0 })
}
$is = @($after.GetEnumerator() | Where-Object { $model.LemmaFor($_.Key, @($model.Tags[$_.Key])[0]) -in $copulas } | Sort-Object { -$_.Value }, { $_.Key } | Select-Object -First 1)
if ($is.Count -gt 0) {
    $categories['Sentences']['is'] = "{0} $($is[0].Key) {1}"
    $categories['VerbForms'] = [ordered]@{ one = 'P3s'; speaker = 'P1s'; many = 'P3p' }
    $categories['Sentences']['does'] = '{0} {1}{2}'
}

$learned = [ordered]@{
    Format   = 'lambek-dialogue-1'
    Language = $Language
    Source   = "small words from the forms model of $Language and the sentences of $(Split-Path -Path $Other -Leaf); whose from $(@($treebanks | ForEach-Object { Split-Path -Path $_ -Leaf }) -join ', '); answers from $(Split-Path -Path $English -Leaf) and $(Split-Path -Path $Other -Leaf)"
    Dialogue = $dialogue
}
$full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
New-Item -ItemType Directory -Path (Split-Path -Path $full -Parent) -Force | Out-Null
[IO.File]::WriteAllText($full, ($learned | ConvertTo-Json -Depth 20) + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Written $full"
Write-Host "  articles $($categories['Articles'] -join ' ') | of $($categories['Of'] -join ' ') | speaker $($categories['Speaker'] -join ' ')"
Write-Host "  yes '$yes', no '$no', unknown '$unknown', understood '$understood', is '$($categories['Sentences']['is'])'"
