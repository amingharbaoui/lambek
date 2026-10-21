function Invoke-LambekMessageBenchmark {
    <#
    .SYNOPSIS
        Runs the free messages of the benchmark through Lambek as the app sends them, and measures what it does not
        understand and what it says wrong.
    .DESCRIPTION
        Each case is a conversation of its own, never written down: one message, or several turns. A turn with an
        expectation is Correct when Lambek says what was expected (or abstains where it should), Unanswered when an answer
        or an action was expected and Lambek said it did not understand or does not know, Wrong when it said something
        else or acted where nothing was to be done.

        The two rates of the roadmap come out of it: how often Lambek does not answer (UnansweredRate), and how often it
        says or does something wrong (WrongRate), with the highest wrong rate the cases cannot rule out (WrongBound).
        Every case is run twice, the second time in the other order: the replies must be the same.
    .EXAMPLE
        Invoke-LambekMessageBenchmark -Path ./bench/messages.json -Split calibration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('all', 'calibration', 'test', 'fresh')]
        [string] $Split = 'all'
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Benchmark file not found: $Path" }
    $data = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    $every = @($data.Cases)
    $cases = @($every | Where-Object { $Split -eq 'all' -or $_.Split -eq $Split })
    if ($cases.Count -eq 0) { throw "No message case for split '$Split'." }

    # The test split is frozen: its hash is written in the file, and a change to it is said
    $testHash = Get-LambekMessageBenchmarkHash -Cases @($every | Where-Object Split -EQ 'test')
    $frozen = $data.PSObject.Properties['TestHash'] -and $data.TestHash -eq $testHash

    $templates = Get-LambekReplyTemplate
    $now = [datetime]::new(2026, 10, 19, 12, 0, 0)
    if ($data.PSObject.Properties['Now'] -and $data.Now) { $now = [datetime]::Parse($data.Now, [cultureinfo]::InvariantCulture) }

    $saved = @{
        Told = $script:Told; Board = $script:Board; Journal = $script:ToldJournal; Incognito = $script:Incognito; Pending = $script:CategoryPending
        Proofs = $script:LastProofs; Problems = $script:ProblemStores; Frames = $script:SpeechFrames; Capture = $script:SpeechCapture
        Host = $script:HostState; Recent = $script:SpeechRecent; Turn = $script:SpeechTurn; Now = $script:Now; Said = $script:SpeechSaid
    }

    # One conversation, alone: nothing told before is in it, and nothing of it is written down
    $converse = {
        param($Case)
        $script:Told = $null; $script:Board = $null; $script:ToldJournal = [System.Collections.Generic.List[object]]::new()
        $script:CategoryPending = $null; $script:LastProofs = $null; $script:ProblemStores = $null; $script:SpeechFrames = $null
        $script:SpeechCapture = $null; $script:SpeechRecent = @{}; $script:SpeechTurn = 0; $script:Now = $now
        $script:HostState = @{ Plans = [ordered]@{}; Simulations = @{}; Approvals = @{} }

        $turns = @(if ($Case.PSObject.Properties['Turns']) { $Case.Turns } else { [pscustomobject]@{ Text = $Case.Text; Expect = $(if ($Case.PSObject.Properties['Expect']) { $Case.Expect }) } })
        $context = $null
        $index = 0
        foreach ($turn in $turns) {
            $index++
            $parameters = [ordered]@{ text = [string] $turn.Text; chat = "bench-$($Case.Id)"; incognito = $true }
            if ($Case.PSObject.Properties['Language'] -and $Case.Language) { $parameters.language = $Case.Language }
            # A turn about the plan shown just before (an edit, "and in C:\Data?") is sent with it, as the app does
            if ($turn.PSObject.Properties['FollowUp'] -and $turn.FollowUp -and $context) { $parameters.context = $context }
            $line = ConvertTo-Json -InputObject ([ordered]@{ id = $index; method = 'ask'; params = $parameters }) -Compress -Depth 5

            $script:SpeechSaid = 0
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-LambekHostRequest -Line $line -AuditPath (Join-Path ([IO.Path]::GetTempPath()) "lambek-bench-$PID.jsonl") | ConvertFrom-Json -AsHashtable
            $elapsed = $stopwatch.Elapsed.TotalMilliseconds

            $status = $null
            $actions = @()
            $reply = $null
            if ($response.ContainsKey('error') -and $response.error) {
                $reply = "error: $($response.error.message)"
            }
            else {
                $result = $response.result
                $status = $result['status']
                $actions = @($result['steps'] | Where-Object { $_ -and $_['action'] } | ForEach-Object { [string] $_['action'] })
                $reply = [string] $result['answer']
                # A question back is said through the questions of the plan when there is no answer
                if (-not $reply) { $reply = (@($result['questions']) + @($result['steps'] | ForEach-Object { if ($_) { $_['questions'] } }) | Where-Object { $_ }) -join "`n" }
                if ($result['id']) { $context = $result['id'] }
            }

            [pscustomobject]@{
                Turn     = $index
                Text     = [string] $turn.Text
                Expect   = $(if ($turn.PSObject.Properties['Expect']) { $turn.Expect } else { $null })
                Status   = $status
                Actions  = $actions
                Reply    = $reply
                Kind     = Get-LambekReplyKind -Text $reply -Templates $templates
                Composed = $script:SpeechSaid -gt 0
                Ms       = $elapsed
            }
        }
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $deterministic = 0
    $compared = 0
    try {
        # The first message of a session in each language loads what reads it and what says the answer: that time is
        # not the time of an answer
        foreach ($warm in @(
                [pscustomobject]@{ Id = 'warm'; Text = 'bonjour'; Language = 'fr' }
                [pscustomobject]@{ Id = 'warm'; Text = 'ma soeur habite a Lyon'; Language = 'fr' }
                [pscustomobject]@{ Id = 'warm'; Text = 'hello'; Language = 'en' }
                [pscustomobject]@{ Id = 'warm'; Text = 'my brother lives in Paris'; Language = 'en' }
            )) { $null = & $converse $warm }

        $first = [ordered]@{}
        foreach ($case in $cases) { $first[$case.Id] = @(& $converse $case) }
        $second = @{}
        for ($i = $cases.Count - 1; $i -ge 0; $i--) { $second[$cases[$i].Id] = @(& $converse $cases[$i]) }

        foreach ($case in $cases) {
            $once = $first[$case.Id]
            $again = $second[$case.Id]
            $compared++
            $sign = { param($runs) ($runs | ForEach-Object { "$($_.Status)|$($_.Actions -join ',')|$($_.Reply)" }) -join "`n" }
            if ((& $sign $once) -ceq (& $sign $again)) { $deterministic++ }

            foreach ($turn in $once) {
                if (-not $turn.Expect) { continue }
                $results.Add([pscustomobject]@{
                        Id       = $case.Id
                        Turn     = $turn.Turn
                        Language = $case.Language
                        Tags     = @($case.Tags)
                        Text     = $turn.Text
                        Expect   = $turn.Expect
                        Status   = $turn.Status
                        Actions  = $turn.Actions
                        Reply    = $turn.Reply
                        Kind     = $turn.Kind
                        Composed = $turn.Composed
                        Ms       = $turn.Ms
                        Outcome  = Get-LambekMessageOutcome -Expect $turn.Expect -Turn $turn
                    })
            }
        }
    }
    finally {
        $script:Told = $saved.Told; $script:Board = $saved.Board; $script:ToldJournal = $saved.Journal; $script:Incognito = $saved.Incognito
        $script:CategoryPending = $saved.Pending; $script:LastProofs = $saved.Proofs; $script:ProblemStores = $saved.Problems
        $script:SpeechFrames = $saved.Frames; $script:SpeechCapture = $saved.Capture; $script:HostState = $saved.Host
        $script:SpeechRecent = $saved.Recent; $script:SpeechTurn = $saved.Turn; $script:Now = $saved.Now; $script:SpeechSaid = $saved.Said
    }

    $measure = {
        param([object[]] $Rows)
        $rows = @($Rows)
        $asked = @($rows | Where-Object { -not ($_.Expect.PSObject.Properties['Reply'] -and $_.Expect.Reply -eq 'abstain') })
        $unanswered = @($rows | Where-Object Outcome -EQ 'Unanswered').Count
        $wrong = @($rows | Where-Object Outcome -EQ 'Wrong').Count
        [pscustomobject]@{
            Turns          = $rows.Count
            Correct        = @($rows | Where-Object Outcome -EQ 'Correct').Count
            Unanswered     = $unanswered
            Wrong          = $wrong
            UnansweredRate = $(if ($asked.Count) { [math]::Round($unanswered / $asked.Count, 4) } else { 0 })
            WrongRate      = $(if ($rows.Count) { [math]::Round($wrong / $rows.Count, 4) } else { 0 })
        }
    }

    $all = & $measure $results.ToArray()
    $byTag = foreach ($tag in @($results | ForEach-Object { $_.Tags } | Sort-Object -Unique)) {
        $metrics = & $measure @($results | Where-Object { $_.Tags -contains $tag })
        [pscustomobject]@{ Tag = $tag; Turns = $metrics.Turns; Correct = $metrics.Correct; Unanswered = $metrics.Unanswered; Wrong = $metrics.Wrong }
    }

    # Answers said: how many were made by the composer and read back by the second Lambek
    $said = @($results | Where-Object { $_.Kind -eq 'Said' })
    $times = @($results | ForEach-Object { $_.Ms } | Sort-Object)
    $median = 0
    $p95 = 0
    if ($times.Count -gt 0) {
        $median = $times[[int][math]::Floor(($times.Count - 1) / 2)]
        $p95 = $times[[int][math]::Ceiling(0.95 * $times.Count) - 1]
    }

    [pscustomobject]@{
        PSTypeName     = 'Lambek.MessageBenchmarkReport'
        Split          = $Split
        Cases          = $cases.Count
        Turns          = $all.Turns
        Correct        = $all.Correct
        Unanswered     = $all.Unanswered
        Wrong          = $all.Wrong
        # Of the turns that were not answered: Lambek said it did not understand, that it does not know, or asked back
        NotUnderstood  = @($results | Where-Object { $_.Outcome -eq 'Unanswered' -and $_.Kind -eq 'NotUnderstood' }).Count
        Abstained      = @($results | Where-Object { $_.Outcome -eq 'Unanswered' -and $_.Kind -eq 'Abstained' }).Count
        Asked          = @($results | Where-Object { $_.Outcome -eq 'Unanswered' -and $_.Kind -eq 'Asked' }).Count
        WrongActions   = @($results | Where-Object { $_.Outcome -eq 'Wrong' -and $_.Status -eq 'Ready' -and @($_.Actions).Count -gt 0 }).Count
        UnansweredRate = $all.UnansweredRate
        WrongRate      = $all.WrongRate
        # The highest rate of wrong replies these turns cannot rule out, at 95 %
        WrongBound     = [math]::Round((Get-LambekRateBound -Failures $all.Wrong -Cases $all.Turns), 4)
        Said           = $said.Count
        Composed       = @($said | Where-Object Composed).Count
        Determinism    = [math]::Round($deterministic / [math]::Max(1, $compared), 4)
        MedianMs       = [math]::Round($median, 1)
        P95Ms          = [math]::Round($p95, 1)
        TestFrozen     = [bool] $frozen
        TestHash       = $testHash
        ByTag          = @($byTag)
        Results        = $results.ToArray()
        Failures       = @($results | Where-Object Outcome -NE 'Correct')
    }
}
