#Requires -Version 7.6
<#
.SYNOPSIS
    Measures how far Lambek reasons on problems written by others: the FraCaS test suite, in English and in French.
.DESCRIPTION
    Each problem is a few sentences told (the premises), then a question; the answer expected is yes (it follows), no
    (its opposite follows) or that it cannot be known (neither follows). Lambek is told the premises in a conversation
    of its own, as the app tells them, then asked the question, and its answer is read by its kind:
      yes / no    an answer said that starts with the word of the language for yes or no
      unknown     Lambek says it cannot conclude, or does not know
      unread      a premise or the question was not understood, or Lambek asked something back: no answer at all
    Counted for each language and each section of the suite:
      Right       the answer expected
      FalseYes    yes when it does not follow: the error that must never happen (a proof of something false)
      FalseNo     no when its opposite does not follow
      Unknown     unknown when yes or no follows: safe, but not reasoned far enough
      Unread      not understood: what is left to read
    The problems marked undefined by the suite are left out.

    FraCaS is under a licence that forbids using it for gain (CC BY-NC-SA 4.0). As decided for Lambek, it is used to
    measure only: downloaded by hand into a folder outside the repository, never committed, never used to learn or to
    set anything (no rule, no threshold, no word is taken from it); only its scores are said, with their source.
      https://huggingface.co/datasets/maximoss/fracas/resolve/main/fracas_in_english_and_french.tsv
      (the FraCaS test suite, Cooper et al. 1996, in the XML of MacCartney; French by Amblard, Beysson, de Groote,
      Guillaume and Pogodalla, LREC 2020)
.EXAMPLE
    ./tools/Measure-LambekNaturalLogic.ps1 -Path ../nli -Show
#>
param(
    # The folder the file was downloaded into
    [string] $Path = (Join-Path $PSScriptRoot '../../nli'),

    [ValidateSet('en', 'fr')]
    [string[]] $Language = @('en', 'fr'),

    # Only the first problems, to keep a run short
    [int] $Limit = 0,

    # Also print each problem not answered as expected
    [switch] $Show
)

$ErrorActionPreference = 'Stop'
$Language = @($Language | ForEach-Object { "$_" -split ',' } | Where-Object { $_ })
$root = Split-Path -Path $PSScriptRoot -Parent
$env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-natural-logic-$PID"
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force
Import-LambekPack -Path (Join-Path $root 'dsl/files') | Out-Null
Import-LambekPack -Path (Join-Path $root 'dsl/code') | Out-Null

$folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
$file = Join-Path $folder 'fracas_in_english_and_french.tsv'
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "$file is missing: download it first (see the help of this script)." }
if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'a11e35604049f24f060d98d2e445bdc56b4878a267b96e7d59765462b53acc8d') {
    throw "$file is not the file this bench was made with."
}
$problems = @(Import-Csv -LiteralPath $file -Delimiter "`t" -Encoding utf8 | Where-Object { $_.label -in '0', '1', '2' })
if ($Limit -gt 0) { $problems = @($problems | Select-Object -First $Limit) }
$expected = @{ '0' = 'yes'; '1' = 'unknown'; '2' = 'no' }

# What Lambek says to one sentence, and what kind of reply it is (the kinds the message bench reads)
$templates = & (Get-Module Lambek) { Get-LambekReplyTemplate }
$say = {
    param([string] $Text)
    # (a sentence that makes Lambek fail is counted, said, and the problem goes on)
    try { $reply = (New-LambekPlan -Text $Text | ConvertTo-LambekAnswer) -join "`n" }
    catch {
        $script:crashes.Add("$Text -> $($_.Exception.Message) at $(($_.ScriptStackTrace -split "`n")[0])")
        return [pscustomobject]@{ Reply = "error: $($_.Exception.Message)"; Kind = 'NotUnderstood' }
    }
    $kind = & (Get-Module Lambek) { param($r, $t) Get-LambekReplyKind -Text $r -Templates $t } $reply $templates
    [pscustomobject]@{ Reply = $reply; Kind = $kind }
}

$crashes = [System.Collections.Generic.List[string]]::new()
$rows = [System.Collections.Generic.List[object]]::new()
foreach ($tongue in $Language) {
    $categories = & (Get-Module Lambek) { param($l) (Get-LambekLexicon -Language $l).Dialogue['Categories'] } $tongue
    $yes = @($categories['YesWords'] | Where-Object { $_ } | ForEach-Object { [regex]::Escape("$_") })
    $no = @($categories['NoWords'] | Where-Object { $_ } | ForEach-Object { [regex]::Escape("$_") })
    foreach ($problem in $problems) {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:CategoryPending = $null }
        $suffix = $(if ($tongue -eq 'en') { '_original' } else { '' })
        $premises = @(foreach ($k in 1..5) { $text = "$($problem."premise$k$suffix")".Trim(); if ($text) { $text } })
        $question = "$($problem."question$suffix")".Trim()
        $unread = $false
        foreach ($premise in $premises) {
            $told = & $say $premise
            if ($told.Kind -in 'NotUnderstood', 'Empty', 'Asked') { $unread = $true }
        }
        $asked = & $say $question
        $plain = ($asked.Reply -split "`n")[0]
        $answer = 'unread'
        if (-not $unread) {
            if ($asked.Kind -eq 'Said' -and $yes.Count -gt 0 -and $plain -match "(?i)^($($yes -join '|'))\b") { $answer = 'yes' }
            elseif ($asked.Kind -eq 'Said' -and $no.Count -gt 0 -and $plain -match "(?i)^($($no -join '|'))\b") { $answer = 'no' }
            elseif ($asked.Kind -eq 'Abstained') { $answer = 'unknown' }
        }
        $rows.Add([pscustomobject]@{
                Language = $tongue; Id = $problem.id; Section = "$($problem.topic)".Trim(); Expected = $expected[$problem.label]; Answer = $answer
                Text = "$($premises -join ' / ') ? $question"; Reply = ($asked.Reply -replace "`n", ' / ')
            })
    }
}

$count = {
    param([object[]] $Rows)
    [pscustomobject]@{
        Problems = $Rows.Count
        Right    = @($Rows | Where-Object { $_.Answer -eq $_.Expected }).Count
        FalseYes = @($Rows | Where-Object { $_.Answer -eq 'yes' -and $_.Expected -ne 'yes' }).Count
        FalseNo  = @($Rows | Where-Object { $_.Answer -eq 'no' -and $_.Expected -ne 'no' }).Count
        Unknown  = @($Rows | Where-Object { $_.Answer -eq 'unknown' -and $_.Expected -ne 'unknown' }).Count
        Unread   = @($Rows | Where-Object { $_.Answer -eq 'unread' }).Count
    }
}
$table = foreach ($tongue in $Language) {
    $mine = @($rows | Where-Object Language -EQ $tongue)
    foreach ($section in @($mine | ForEach-Object Section | Select-Object -Unique)) {
        $line = & $count @($mine | Where-Object Section -EQ $section)
        $line | Add-Member -NotePropertyName Language -NotePropertyValue $tongue
        $line | Add-Member -NotePropertyName Section -NotePropertyValue $section -PassThru
    }
    $all = & $count $mine
    $all | Add-Member -NotePropertyName Language -NotePropertyValue $tongue
    $all | Add-Member -NotePropertyName Section -NotePropertyValue 'all' -PassThru
}
$table | Format-Table Language, Section, Problems, Right, FalseYes, FalseNo, Unknown, Unread -AutoSize | Out-String -Width 200 | Write-Host
if ($Show) {
    foreach ($row in @($rows | Where-Object { $_.Answer -ne $_.Expected })) {
        Write-Host "  [$($row.Language) $($row.Id) $($row.Expected) -> $($row.Answer)] $($row.Text)`n      $($row.Reply)"
    }
}
$bound = { param($f, $n) & (Get-Module Lambek) { param($f, $n) Get-LambekRateBound -Failures $f -Cases $n } $f $n }
foreach ($tongue in $Language) {
    $mine = @($rows | Where-Object Language -EQ $tongue)
    $claims = @($mine | Where-Object { $_.Answer -in 'yes', 'no' })
    $wrong = @($claims | Where-Object { $_.Answer -ne $_.Expected }).Count
    Write-Host ("{0}: yes or no said {1} times, {2} of them wrong, so under {3:P2} at 95 %" -f $tongue, $claims.Count, $wrong, (& $bound $wrong $claims.Count))
}
Write-Host "Sentences that made Lambek fail: $($crashes.Count)"
foreach ($line in $crashes) { Write-Host "  $line" }
# (a sentence that makes Lambek fail is a fault to mend, whatever the scores)
if ($crashes.Count -gt 0) { exit 1 }
exit 0
