#Requires -Version 7.6
<#
.SYNOPSIS
    Measures how often Lambek tells the language of a sentence said alone, with nothing said before it.
.DESCRIPTION
    Every sentence of bench/reasoning.json, each once, with the language of its conversation: the language the readers
    of general rules read it in (Get-LambekLanguage with the forms, the letters and the text as typed), with no chat to lean on.
    Short sentences are the hard ones ("Rex e alto?" with a grave accent, "Rex no es alto"): in a chat, the language of what was said
    before decides a tie, here nothing does. Prints the count wrong for each split and each language, and the sentences
    read in another language for the calibration split only (the test split is counted, never looked at).
.EXAMPLE
    ./tools/Measure-LambekLanguage.ps1
#>
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force
$data = Get-Content -LiteralPath (Join-Path $root 'bench/reasoning.json') -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($split in 'calibration', 'test') {
    $said = @(foreach ($case in @($data.Cases | Where-Object Split -EQ $split)) {
            foreach ($turn in $case.Turns) { [pscustomobject]@{ Language = $case.Language; Text = [string] $turn.Text } }
        })
    $said = @($said | Sort-Object Language, Text -Unique)
    $read = & (Get-Module Lambek) {
        param($said)
        $script:LanguageHint = $null
        $script:Told = $null
        foreach ($one in $said) {
            $found = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $one.Text) -Text $one.Text -Forms -Letters
            [pscustomobject]@{ Language = $one.Language; Text = $one.Text; Read = $found }
        }
    } $said
    $wrong = @($read | Where-Object { $_.Read -ne $_.Language })
    Write-Host ("{0}: {1} of {2} sentences read in another language" -f $split, $wrong.Count, $read.Count)
    foreach ($group in @($read | Group-Object Language | Sort-Object Name)) {
        Write-Host ("  {0}  {1} of {2}" -f $group.Name, @($group.Group | Where-Object { $_.Read -ne $_.Language }).Count, $group.Count)
    }
    if ($split -eq 'calibration') { foreach ($one in $wrong) { Write-Host "    $($one.Language) read as $($one.Read): $($one.Text)" } }
}
