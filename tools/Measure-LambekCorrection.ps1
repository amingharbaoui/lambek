#Requires -Version 7.6
<#
.SYNOPSIS
    Measures whether Lambek lets go of what the user takes back: a conversation where something told is corrected
    ("non, en fait Tom est un chien"), then asked again.
.DESCRIPTION
    Each case tells Lambek what one is ("Tom est un chat"), a general rule about its kind ("tous les chats aiment le
    lait") and the same of another one ("Minou est un chat"); then the user corrects the first, in one of several ways,
    and asks. Three figures for each way of correcting:
      Dropped     what was taken back is no longer said: "Tom est-il un chat ?" is not answered yes
      Withdrawn   what was found from it is no longer said: "Tom aime-t-il le lait ?" is not answered yes, while the
                  same is still found of the other one (else the rule was not read, and nothing is measured)
      Kept        what was not taken back still holds: "Minou aime-t-il le lait ?" is still answered yes
    Kept must stay whole: a correction takes back one thing, not all. The names and kinds of the calibration and the
    test are apart (-Split): tune on calibration, never on the test.
.EXAMPLE
    ./tools/Measure-LambekCorrection.ps1 -Show
#>
param(
    # calibration or test
    [ValidateSet('calibration', 'test')]
    [string] $Split = 'calibration',

    # Only these languages
    [string[]] $Language = @('fr', 'en'),

    # Also print each case that did not let go, or let go of too much
    [switch] $Show
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-correction-$PID"
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force
Import-LambekPack -Path (Join-Path $root 'dsl/files') | Out-Null

# The ones, their kind, the kind they are in truth, and what all of the first kind do; apart for each split
$worlds = @{
    calibration = @{
        fr = @(
            @{ One = 'Tom'; Other = 'Minou'; Kind = 'chat'; Kinds = 'chats'; True = 'chien'; Rule = 'aiment le lait'; Asked = 'aime-t-il le lait' }
            @{ One = 'Rex'; Other = 'Médor'; Kind = 'chien'; Kinds = 'chiens'; True = 'loup'; Rule = 'aboient'; Asked = 'aboie-t-il' }
            @{ One = 'Coco'; Other = 'Titi'; Kind = 'oiseau'; Kinds = 'oiseaux'; True = 'poisson'; Rule = 'ont des plumes'; Asked = 'a-t-il des plumes' }
            @{ One = 'Nemo'; Other = 'Dory'; Kind = 'poisson'; Kinds = 'poissons'; True = 'dauphin'; Rule = 'nagent'; Asked = 'nage-t-il' }
        )
        en = @(
            @{ One = 'Tom'; Other = 'Felix'; Kind = 'cat'; Kinds = 'cats'; True = 'dog'; Rule = 'like milk'; Asked = 'does {0} like milk' }
            @{ One = 'Rex'; Other = 'Buddy'; Kind = 'dog'; Kinds = 'dogs'; True = 'wolf'; Rule = 'bark'; Asked = 'does {0} bark' }
            @{ One = 'Coco'; Other = 'Tweety'; Kind = 'bird'; Kinds = 'birds'; True = 'fish'; Rule = 'have feathers'; Asked = 'does {0} have feathers' }
            @{ One = 'Nemo'; Other = 'Dory'; Kind = 'fish'; Kinds = 'fish'; True = 'dolphin'; Rule = 'swim'; Asked = 'does {0} swim' }
        )
    }
    test        = @{
        fr = @(
            @{ One = 'Pégase'; Other = 'Tornado'; Kind = 'cheval'; Kinds = 'chevaux'; True = 'âne'; Rule = 'galopent'; Asked = 'galope-t-il' }
            @{ One = 'Kaa'; Other = 'Nagini'; Kind = 'serpent'; Kinds = 'serpents'; True = 'lézard'; Rule = 'rampent'; Asked = 'rampe-t-il' }
            @{ One = 'Maya'; Other = 'Willy'; Kind = 'abeille'; Kinds = 'abeilles'; True = 'guêpe'; Rule = 'font du miel'; Asked = 'fait-elle du miel' }
            @{ One = 'Dumbo'; Other = 'Babar'; Kind = 'éléphant'; Kinds = 'éléphants'; True = 'rhinocéros'; Rule = 'ont une trompe'; Asked = 'a-t-il une trompe' }
        )
        en = @(
            @{ One = 'Pegasus'; Other = 'Tornado'; Kind = 'horse'; Kinds = 'horses'; True = 'donkey'; Rule = 'gallop'; Asked = 'does {0} gallop' }
            @{ One = 'Kaa'; Other = 'Nagini'; Kind = 'snake'; Kinds = 'snakes'; True = 'lizard'; Rule = 'crawl'; Asked = 'does {0} crawl' }
            @{ One = 'Maya'; Other = 'Willy'; Kind = 'bee'; Kinds = 'bees'; True = 'wasp'; Rule = 'make honey'; Asked = 'does {0} make honey' }
            @{ One = 'Dumbo'; Other = 'Babar'; Kind = 'elephant'; Kinds = 'elephants'; True = 'rhino'; Rule = 'have a trunk'; Asked = 'does {0} have a trunk' }
        )
    }
}

# The ways a user takes something back
$ways = [ordered]@{
    actually = @{ fr = 'non, en fait {0} est un {1}'; en = 'no, actually {0} is a {1}' }
    wrong    = @{ fr = 'je me suis trompé, {0} n''est pas un {2}'; en = 'I was wrong, {0} is not a {2}' }
    correct  = @{ fr = 'correction : {0} est un {1}, pas un {2}'; en = 'correction: {0} is a {1}, not a {2}' }
    rather   = @{ fr = 'pardon, {0} n''est pas un {2} mais un {1}'; en = 'sorry, {0} is not a {2} but a {1}' }
}
$sentences = @{
    fr = @{ Is = '{0} est un {1}'; All = 'tous les {0} {1}'; AskIs = '{0} est-il un {1} ?'; AskDo = '{0} {1} ?'; Yes = '^Oui\b' }
    en = @{ Is = '{0} is a {1}'; All = 'all {0} {1}'; AskIs = 'is {0} a {1}?'; AskDo = '{0}?'; Yes = '^Yes\b' }
}

$say = { param([string] $Text) New-LambekPlan -Text $Text | ConvertTo-LambekAnswer }
$rows = [System.Collections.Generic.List[object]]::new()
foreach ($tongue in $Language) {
    $s = $sentences[$tongue]
    foreach ($way in $ways.Keys) {
        foreach ($world in $worlds[$Split][$tongue]) {
            & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null }
            $null = & $say ($s.Is -f $world.One, $world.Kind)
            $null = & $say ($s.Is -f $world.Other, $world.Kind)
            $null = & $say ($s.All -f $world.Kinds, $world.Rule)
            $null = & $say ($ways[$way][$tongue] -f $world.One, $world.True, $world.Kind)
            $askDo = { param($who) if ($tongue -eq 'fr') { $s.AskDo -f $who, $world.Asked } else { $s.AskDo -f ($world.Asked -f $who) } }
            $is = & $say ($s.AskIs -f $world.One, $world.Kind)
            $does = & $say (& $askDo $world.One)
            $other = & $say (& $askDo $world.Other)
            $rows.Add([pscustomobject]@{
                    Language  = $tongue
                    Way       = $way
                    One       = $world.One
                    Dropped   = "$is" -notmatch $s.Yes
                    Withdrawn = "$does" -notmatch $s.Yes -and "$other" -match $s.Yes
                    Kept      = "$other" -match $s.Yes
                    Said      = ("$is | $does | $other" -replace "`n", ' ')
                })
        }
    }
}

$table = foreach ($group in @($rows | Group-Object Way) + @([pscustomobject]@{ Name = 'all'; Group = $rows })) {
    $n = @($group.Group).Count
    [pscustomobject]@{
        Way       = $group.Name
        Cases     = $n
        Dropped   = @($group.Group | Where-Object Dropped).Count
        Withdrawn = @($group.Group | Where-Object Withdrawn).Count
        Kept      = @($group.Group | Where-Object Kept).Count
    }
}
$table | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
if ($Show) {
    foreach ($row in $rows | Where-Object { -not $_.Dropped -or -not $_.Withdrawn -or -not $_.Kept }) { Write-Host "  $($row.Language) $($row.Way) $($row.One): $($row.Said)" }
}
