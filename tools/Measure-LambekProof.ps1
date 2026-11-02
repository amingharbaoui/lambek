#Requires -Version 7.6
<#
.SYNOPSIS
    Judges the proofs of Lambek's answers: each answer that rests on things told is worked out again from the things its
    proof cites and nothing else, in a conversation of its own.
.DESCRIPTION
    The calibration conversations of bench/messages.json that tell things and then ask about them ("tous les hommes sont
    mortels", "Socrate est un homme", "Socrate est-il mortel ?"). Lambek answers the last question and keeps what the
    answer rests on (its proof). Then, each time in a new conversation where nothing else was said:
      Enough      the sentences the proof cites, then the question: the same answer must come back. A proof that left
                  out a premise it needed gives another answer here
      Needed      the sentences the proof cites but one, then the question: the answer must change. A premise cited
                  that the answer does not need gives the same answer here
      Swapped     the sentences of another conversation's proof, then this question: this answer must not come back.
                  A proof that would fit any question is caught here
      Checked     the facts the proof cites and what the answer concludes, in the shape Lambek holds them, given to a
                  checker that shares no code with Lambek (tools/Test-LambekProof.ps1): the conclusion must follow
                  from them by its few rules, and each one must be needed. What it does not know how to check is
                  counted apart
    Each conversation is also said with one sentence of another conversation told first, which has nothing to do with
    the question: a proof that cites it, or that cites everything told, is caught by Needed. An answer about things told
    whose proof cites nothing is counted apart.
    Each sentence a proof cites is found as the sentence of the conversation that said it. Conversations about why
    something holds ("pourquoi ?") are left out: their answer is the proof of the answer before. The test splits stay
    unseen.
.EXAMPLE
    ./tools/Measure-LambekProof.ps1 -Show
    Also run at the end of ./build.ps1 -Task Benchmark, which stops when a proof does not hold.
#>
param(
    # At most this many conversations (the first ones), to keep a run short
    [int] $Limit = 0,

    # For each conversation, the proofs of this many others put under its question
    [int] $Swaps = 3,

    # Also print each answer that did not hold
    [switch] $Show
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$env:LAMBEK_DATA = Join-Path ([IO.Path]::GetTempPath()) "lambek-proof-$PID"
Import-Module (Join-Path $root 'engine/Lambek/Lambek.psd1') -Force
Import-LambekPack -Path (Join-Path $root 'dsl/files') | Out-Null
Import-LambekPack -Path (Join-Path $root 'dsl/code') | Out-Null
. (Join-Path $PSScriptRoot 'Test-LambekProof.ps1')

# One conversation, alone: the sentences said in turn, then what the last answer was and what its proof cites. For each
# fact the proof cites, the sentence that told it: the one whose new facts hold it, else the one that says it word for
# word, else the one that has it inside ("je prends le bus" in "s'il pleut, je prends le bus")
$converse = {
    param([string[]] $Sentences, [string] $Language, [string] $Name)
    & (Get-Module Lambek) {
        param($Sentences, $Language, $Name)
        $script:Told = $null; $script:Board = $null; $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
        $script:CategoryPending = $null; $script:LastProofs = $null; $script:ProblemStores = $null; $script:SpeechFrames = $null
        $script:SpeechCapture = $null; $script:SpeechRecent = @{}; $script:SpeechTurn = 0
        $script:HostState = @{ Plans = [ordered]@{}; Simulations = @{}; Approvals = @{} }

        $added = [System.Collections.Generic.List[object]]::new()
        $answer = ''
        for ($i = 0; $i -lt $Sentences.Count; $i++) {
            $before = [System.Collections.Generic.HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
            foreach ($fact in @((Get-LambekTold).ToArray())) { [void] $before.Add($fact) }
            $parameters = [ordered]@{ text = $Sentences[$i]; chat = "proof-$Name"; incognito = $true }
            if ($Language) { $parameters.language = $Language }
            $line = ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $i + 1; method = 'ask'; params = $parameters })
            $response = Invoke-LambekHostRequest -Line $line -AuditPath (Join-Path ([IO.Path]::GetTempPath()) "lambek-proof-$PID.jsonl") | ConvertFrom-Json -AsHashtable
            $answer = $(if ($response.ContainsKey('result') -and $response.result) { [string] $response.result['answer'] } else { 'error' })
            $added.Add(@(@((Get-LambekTold).ToArray()) | Where-Object { -not $before.Contains($_) }))
        }

        $proof = Get-LambekLastProof
        $facts = @(if ($proof) { @($proof.Facts) })
        $plain = { param($Text) ((ConvertTo-LambekNormalizedText -Text "$Text") -replace '[^\p{L}\p{N}]+', ' ').Trim() }
        $cited = [System.Collections.Generic.SortedSet[int]]::new()
        $lost = 0
        foreach ($fact in $facts) {
            $at = -1
            for ($i = 0; $i -lt $Sentences.Count - 1 -and $at -lt 0; $i++) { if (@($added[$i] | Where-Object { [object]::ReferenceEquals($_, $fact) }).Count -gt 0) { $at = $i } }
            $text = $(if ($fact.PSObject.Properties['Text']) { & $plain $fact.Text } else { '' })
            if ($at -lt 0 -and $text) { for ($i = 0; $i -lt $Sentences.Count - 1 -and $at -lt 0; $i++) { if ((& $plain $Sentences[$i]) -eq $text) { $at = $i } } }
            if ($at -lt 0 -and $text) { for ($i = 0; $i -lt $Sentences.Count - 1 -and $at -lt 0; $i++) { if (" $(& $plain $Sentences[$i]) " -like "* $text *") { $at = $i } } }
            if ($at -ge 0) { [void] $cited.Add($at) } else { $lost++ }
        }
        # (the facts and the conclusion in the shape they are held in, for the checker)
        $cores = @($facts | ForEach-Object { if ($_.PSObject.Properties['Core'] -and $_.Core) { "$($_.Core)" } else { '' } })
        # (as the reasoning read them, when it read them in another shape than the one they are held in)
        # (a proof that gives readings for some of its facts and not others cannot be checked: it is said)
        if ($proof -and $proof.PSObject.Properties['Forms'] -and @($proof.Forms).Count -gt 0) {
            $cores = $(if (@($proof.Forms).Count -eq $facts.Count) { @($proof.Forms) } else { @($facts | ForEach-Object { '' }) })
        }
        $concluded = @(if ($proof -and $proof.PSObject.Properties['Conclusion']) { @($proof.Conclusion) })
        [pscustomobject]@{ Answer = $answer; Facts = $facts.Count; Cited = @($cited); Lost = $lost; Cores = $cores; Conclusion = $concluded }
    } $Sentences $Language $Name
}

$same = { param($A, $B) (($A -replace '\s+', ' ').Trim()) -ceq (($B -replace '\s+', ' ').Trim()) }

$data = Get-Content -LiteralPath (Join-Path $root 'bench/messages.json') -Raw | ConvertFrom-Json
$cases = @($data.Cases | Where-Object {
        $_.Split -eq 'calibration' -and $_.PSObject.Properties['Turns'] -and @($_.Turns).Count -ge 2 -and 'why' -notin @($_.Tags)
    })
if ($Limit -gt 0) { $cases = @($cases | Select-Object -First $Limit) }

# Each conversation with a sentence of another one told first, and the proof of its last answer. The sentence comes
# from the next conversation in the same language that shares no word of its own sentences (so it cannot bear on it)
$plain = { param($Text) @(("$Text".ToLowerInvariant() -split '[^\p{L}\p{N}]+') | Where-Object { $_.Length -gt 3 }) }
$proved = [System.Collections.Generic.List[object]]::new()
$unproved = [System.Collections.Generic.List[string]]::new()
for ($c = 0; $c -lt $cases.Count; $c++) {
    $case = $cases[$c]
    $sentences = [string[]] @($case.Turns | ForEach-Object { [string] $_.Text })
    $words = @($sentences | ForEach-Object { & $plain $_ })
    $aside = $null
    for ($k = 1; $k -lt $cases.Count -and -not $aside; $k++) {
        $other = $cases[($c + $k) % $cases.Count]
        if ($other.Language -ne $case.Language) { continue }
        $told = [string] @($other.Turns)[0].Text
        if (@(& $plain $told | Where-Object { $_ -in $words }).Count -eq 0) { $aside = $told }
    }
    if ($aside) { $sentences = [string[]] @(@($aside) + $sentences) }
    $first = & $converse $sentences $case.Language $case.Id
    if ($first.Facts -eq 0) { $unproved.Add("[$($case.Id)] $($sentences -join ' / ') -> $($first.Answer -replace "`n", ' / ')"); continue }
    $proved.Add([pscustomobject]@{
            Id = $case.Id; Language = $case.Language; Sentences = $sentences; Question = $sentences[-1]
            Answer = $first.Answer; Cited = $first.Cited; Lost = $first.Lost; Aside = [int] ($aside -and 0 -in $first.Cited)
            Cores = $first.Cores; Conclusion = $first.Conclusion
        })
}

$rows = [System.Collections.Generic.List[object]]::new()
$unchecked = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()
foreach ($case in $proved) {
    $premises = @($case.Cited | ForEach-Object { $case.Sentences[$_] })

    # Enough: the cited sentences alone give the same answer
    $again = & $converse ([string[]] @($premises + $case.Question)) $case.Language "$($case.Id)-enough"
    $enough = & $same $again.Answer $case.Answer
    if (-not $enough) { $failed.Add("[$($case.Id) enough] $($premises -join ' / ') / $($case.Question)`n    was: $($case.Answer -replace "`n", ' / ')`n    now: $($again.Answer -replace "`n", ' / ')") }

    # Needed: without any one of them, the answer changes
    $needed = 0
    foreach ($drop in $premises) {
        $rest = @($premises | Where-Object { $_ -ne $drop })
        $without = & $converse ([string[]] @($rest + $case.Question)) $case.Language "$($case.Id)-needed"
        if (-not (& $same $without.Answer $case.Answer)) { $needed++ }
        else { $failed.Add("[$($case.Id) needed] without ""$drop"" the answer is the same: $($case.Answer -replace "`n", ' / ')") }
    }

    # Swapped: the proofs of other conversations do not give this answer
    $swapped = 0; $tried = 0
    $others = @($proved | Where-Object { $_.Id -ne $case.Id -and $_.Language -eq $case.Language })
    $start = [array]::IndexOf(@($others | ForEach-Object Id), ($others | Where-Object { [string]::CompareOrdinal($_.Id, $case.Id) -gt 0 } | Select-Object -First 1).Id)
    if ($start -lt 0) { $start = 0 }
    for ($k = 0; $k -lt [math]::Min($Swaps, $others.Count); $k++) {
        $other = $others[($start + $k) % $others.Count]
        $theirs = @($other.Cited | ForEach-Object { $other.Sentences[$_] })
        # (a proof that cites every sentence of this one could rightly give the same answer)
        if (@($premises | Where-Object { $_ -notin $theirs }).Count -eq 0) { continue }
        $tried++
        $foreign = & $converse ([string[]] @($theirs + $case.Question)) $case.Language "$($case.Id)-swap"
        if (-not (& $same $foreign.Answer $case.Answer)) { $swapped++ }
        else { $failed.Add("[$($case.Id) swapped] with the proof of $($other.Id) ($($theirs -join ' / ')) the answer is the same: $($case.Answer -replace "`n", ' / ')") }
    }

    # Checked: by a checker of its own, from the facts as they are held
    $checked = 'unchecked'
    $unneededHere = 0
    if (@($case.Cores | Where-Object { -not $_ }).Count -eq 0) {
        $check = Test-LambekProof -Premises ([string[]] $case.Cores) -Conclusions ([string[]] $case.Conclusion) -Each
        if ($check.Holds -eq $true) { $checked = 'holds'; $unneededHere = $check.Unneeded.Count }
        elseif ($check.Holds -eq $false) { $checked = 'refused'; $failed.Add("[$($case.Id) checked] $($check.Reason) from $($case.Cores -join ' ; ')") }
        else { $unchecked.Add("[$($case.Id)] $($check.Reason)") }
        foreach ($premise in $check.Unneeded) { $failed.Add("[$($case.Id) checked] not needed by the checker: $premise") }
    }
    else { $unchecked.Add("[$($case.Id)] a fact cited has no shape the checker reads") }

    $rows.Add([pscustomobject]@{
            Id = $case.Id; Cited = $premises.Count; Lost = $case.Lost; Aside = $case.Aside; Checked = $checked; Unneeded = $unneededHere; Enough = [int] $enough
            Needed = $needed; Swapped = $swapped; Tried = $tried
        })
}

$rows | Format-Table Id, Cited, Lost, Aside, Checked, Unneeded, Enough, Needed, Swapped, Tried -AutoSize | Out-String -Width 200 | Write-Host
if ($Show) {
    $failed | ForEach-Object { Write-Host "  $_" }
    $unproved | ForEach-Object { Write-Host "  [no proof] $_" }
    $unchecked | ForEach-Object { Write-Host "  [not checked] $_" }
}

$total = [pscustomobject]@{
    Proofs  = $rows.Count
    Enough  = @($rows | Where-Object Enough).Count
    Cited   = ($rows | Measure-Object Cited -Sum).Sum
    Needed  = ($rows | Measure-Object Needed -Sum).Sum
    Lost    = ($rows | Measure-Object Lost -Sum).Sum
    Tried   = ($rows | Measure-Object Tried -Sum).Sum
    Swapped = ($rows | Measure-Object Swapped -Sum).Sum
}
$bound = { param($f, $n) & (Get-Module Lambek) { param($f, $n) Get-LambekRateBound -Failures $f -Cases $n } $f $n }
Write-Host ("Answers with a proof: {0} of {1} conversations; facts cited without the sentence that told them: {2}; sentence told aside and cited: {3}" -f $total.Proofs, $cases.Count, $total.Lost, ($rows | Measure-Object Aside -Sum).Sum)
$holds = @($rows | Where-Object Checked -EQ 'holds').Count
$refused = @($rows | Where-Object Checked -EQ 'refused').Count
Write-Host ("Checked by a checker of its own: {0} hold, {1} refused, {2} it cannot check; premises it finds not needed: {3}" -f $holds, $refused, $unchecked.Count, ($rows | Measure-Object Unneeded -Sum).Sum)
Write-Host ("Proof refused by the checker: {0} of {1}, so under {2:P3} at 95 %" -f $refused, ($holds + $refused), (& $bound $refused ($holds + $refused)))
Write-Host ("Proof not enough on its own: {0} of {1}, so under {2:P3} at 95 %" -f ($total.Proofs - $total.Enough), $total.Proofs, (& $bound ($total.Proofs - $total.Enough) $total.Proofs))
Write-Host ("Premise cited and not needed: {0} of {1}, so under {2:P3} at 95 %" -f ($total.Cited - $total.Needed), $total.Cited, (& $bound ($total.Cited - $total.Needed) $total.Cited))
Write-Host ("Answer given by another conversation's proof: {0} of {1}, so under {2:P3} at 95 %" -f ($total.Tried - $total.Swapped), $total.Tried, (& $bound ($total.Tried - $total.Swapped) $total.Tried))
# (a proof not enough on its own, a premise cited and not needed, or an answer another proof gives fails the run:
# build.ps1 stops on it)
if ($failed.Count -gt 0) { exit 1 }
