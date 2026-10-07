function Invoke-LambekHostRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line,

        [Parameter(Mandatory)]
        [string] $AuditPath
    )

    $id = $null
    try {
        # Request: { "id": 1, "method": "ask", "params": { ... } }
        try {
            $request = $Line | ConvertFrom-Json -AsHashtable
        }
        catch {
            throw 'The request is not valid JSON.'
        }
        if ($request -isnot [hashtable] -or -not $request.ContainsKey('method')) {
            throw 'The request needs a method.'
        }

        $id = $request['id']
        $script:HostRequestId = $id
        $params = @{}
        if ($request.ContainsKey('params') -and $request.params -is [hashtable]) {
            $params = $request.params
        }
        $state = $script:HostState

        # The language of the chat, used when a message could be in any language
        $script:LanguageHint = $null
        $script:Incognito = $params['incognito'] -eq $true
        $hint = [string] $params['language']
        if ($hint -in (Get-LambekAvailableLanguage)) { $script:LanguageHint = $hint }

        switch ($request.method) {
            'ping' {
                $result = [ordered]@{ name = 'Lambek'; version = (Get-Module Lambek).Version.ToString() }
            }
            'categories' {
                $language = 'en'
                if ($params.ContainsKey('language')) { $language = [string] $params.language }
                $result = @(Get-LambekCategory -Language $language | ForEach-Object {
                        [ordered]@{ pack = $_.Pack; title = $_.Title; summary = $_.Summary; examples = @($_.Examples); actions = @($_.Actions) }
                    })
            }
            'mcp' {
                # A starter config the user can open and fill
                $path = $script:Mcp.ConfigPath
                if ($params.ContainsKey('create') -and $params.create -eq $true -and -not (Test-Path -LiteralPath $path)) {
                    New-Item -Path (Split-Path -Path $path -Parent) -ItemType Directory -Force | Out-Null
                    Set-Content -LiteralPath $path -Value "{`n  `"mcpServers`": {}`n}" -Encoding utf8NoBOM
                }
                if ($params.ContainsKey('refresh') -and $params.refresh -eq $true) {
                    Connect-LambekMcp -Path $script:Mcp.ConfigPath -Refresh | Out-Null
                }
                $result = [ordered]@{
                    config  = $script:Mcp.ConfigPath
                    exists  = (Test-Path -LiteralPath $script:Mcp.ConfigPath -PathType Leaf)
                    servers = @(Get-LambekMcpServer | ForEach-Object {
                            [ordered]@{
                                name    = $_.Name
                                status  = $_.Status
                                running = $_.Running
                                version = $_.Version
                                error   = $_.Error
                                tools   = @($_.Tools | ForEach-Object { [ordered]@{ name = $_.Name; action = $_.Action; title = $_.Title; risk = $_.Risk; description = $_.Description } })
                                skipped = @($_.Skipped | ForEach-Object { [ordered]@{ tool = $_.Tool; reason = $_.Reason } })
                            }
                        })
                }
            }
            'packs' {
                $result = @(Get-LambekPack | ForEach-Object {
                        [ordered]@{ name = $_.Name; version = $_.Version; description = $_.Description; actions = @($_.Actions) }
                    })
            }
            'ask' {
                if (-not $params.ContainsKey('text') -or [string]::IsNullOrWhiteSpace($params.text)) {
                    throw 'ask needs a text.'
                }
                # A message about the current plan edits it, explains it, or runs it
                $kind = 'new'
                $answer = $null
                $followUp = $null
                $context = [string] $params['context']
                $selected = 0
                if ($params['step']) { $selected = [int] $params['step'] }
                # What the chat believes the user wants: it may settle a close call between two reading actions
                $chat = [string] $params['chat']
                if (-not $chat) { $chat = $context }
                if (-not $state.Contains('Beliefs')) { $state.Beliefs = @{} }
                $belief = $null
                if ($chat -and $state.Beliefs.ContainsKey($chat)) { $belief = $state.Beliefs[$chat] }
                $script:Belief = $(if ($belief) { $belief.Belief } else { $null })

                # The languages of the chat: a hidden Markov model filtered one turn at a time. The user mostly stays in a
                # language, a word of one language only is evidence for it, "ok" or a path says nothing. The most probable
                # language settles a message that could be in several (the app's own hint starts a chat it has no belief for)
                if (-not $state.Contains('Languages')) { $state.Languages = @{} }
                $words = @(Get-LambekLanguageToken -Text $params.text)
                $previous = $null
                if ($chat -and $state.Languages.ContainsKey($chat)) { $previous = $state.Languages[$chat] }
                elseif ($script:LanguageHint) { $previous = @{ $script:LanguageHint = 1.0 } }
                $languages = Get-LambekLanguageBelief -Belief $previous -Tokens $words
                $script:LanguageHint = Select-LambekLanguage -Belief $languages
                if ($chat) { $state.Languages[$chat] = $languages }

                # What the user told in this chat: each chat has its own, kept in memory only
                if (-not $state.Contains('Told')) { $state.Told = @{} }
                if ($chat -and -not $state.Told.ContainsKey($chat)) { $state.Told[$chat] = [System.Collections.Generic.List[object]]::new() }
                $script:Told = $(if ($chat) { $state.Told[$chat] } else { [System.Collections.Generic.List[object]]::new() })

                if ($context -and $state.Plans.Contains($context)) {
                    $followUp = Resolve-LambekFollowUp -Plan $state.Plans[$context] -Text $params.text -Step $selected
                    $kind = $followUp.Kind
                    $plan = $followUp.Plan
                    $answer = $followUp.Answer
                }
                else {
                    # "write a python script that deletes ...": the plan of the task, and its program as the answer
                    $followUp = Resolve-LambekCodeRequest -Text $params.text
                    if ($followUp) {
                        $plan = $followUp.Plan
                        $answer = $followUp.Answer
                    }
                    else {
                        $plan = New-LambekPlan -Text $params.text
                    }
                }

                $script:Belief = $null

                # The belief follows the chat: predicted from the turns before, weighed by this one (a Bayes filter)
                $rows = @($plan.Steps | Where-Object { $_.PSObject.Properties['Reading'] -and $_.Reading } | Select-Object -First 1 | ForEach-Object { $_.Reading.Rows })
                if ($chat -and $rows.Count -gt 0 -and $kind -ne 'explain') {
                    $turns = 0
                    if ($belief) { $turns = $belief.Turns + 1 }
                    $state.Beliefs[$chat] = [pscustomobject]@{ Belief = Get-LambekBelief -Belief $(if ($belief) { $belief.Belief } else { $null }) -Rows $rows -Turns $turns; Turns = $turns; Plan = $plan.PlanHash }
                }

                if ($kind -in 'explain', 'run') {
                    $result = [ordered]@{ kind = $kind; id = $context; answer = $answer }
                }
                else {
                    # Plans are kept in memory by id (at most 50)
                    $planId = $plan.PlanHash
                    if (-not $planId) { $planId = Get-LambekHash -Text "draft|$($params.text)|$context" }
                    $state.Plans[$planId] = $plan
                    while ($state.Plans.Count -gt 50) { $state.Plans.RemoveAt(0) }

                    $result = ConvertTo-LambekHostPlan -Id $planId -Plan $plan
                    $result.kind = $kind
                    # A new or edited plan speaks through its status; only questions and small talk need words
                    if ($answer -and $plan.Status -ne 'Ready') { $result.answer = $answer }
                    if ($plan.Status -ne 'Ready' -and $kind -ne 'new') { $result.answer = ConvertTo-LambekAnswer -Plan $plan -Brief }
                    # The plan written as a program: the code is the answer
                    if ($followUp -and $followUp.PSObject.Properties['Code'] -and $followUp.Code) { $result.answer = $answer }
                    # A word just learned: say it, the plan follows
                    if ($followUp -and $followUp.PSObject.Properties['Learned']) {
                        $result.answer = @(($answer -split "`n")[0], $result['answer'] | Where-Object { $_ }) -join "`n"
                    }
                }

                # The language of the message (its frame, the chat's on a tie), so the app can keep the chat in it
                $result.language = Get-LambekLanguage -Tokens $words

                # Small talk: nothing to prove, the app shows no reading for it
                $result.talk = $false
                if ($kind -eq 'new' -and @($plan.Steps | Where-Object { $_.Action }).Count -eq 0) {
                    $result.talk = [bool](Get-LambekTalk -Text $params.text -Language $result.language)
                    # A definition or a calculation is words too, not a plan
                    if ($plan.PSObject.Properties['Reply'] -and $plan.Reply) { $result.talk = $true }
                }
            }
            'edit' {
                $plan = Get-LambekHostPlan -State $state -Params $params
                foreach ($key in 'step', 'name') {
                    if (-not $params.ContainsKey($key)) { throw "edit needs $key." }
                }
                $value = $null
                if ($params.ContainsKey('value')) { $value = [string] $params.value }

                $edited = Set-LambekPlanParameter -Plan $plan -Step ([int] $params.step) -Name $params.name -Value $value
                $planId = $edited.PlanHash
                if (-not $planId) { $planId = Get-LambekHash -Text "draft|$($params.id)|$($params.step)|$($params.name)|$value" }
                $state.Plans[$planId] = $edited
                while ($state.Plans.Count -gt 50) { $state.Plans.RemoveAt(0) }

                $result = ConvertTo-LambekHostPlan -Id $planId -Plan $edited
            }
            'simulate' {
                $plan = Get-LambekHostPlan -State $state -Params $params
                $simulation = Invoke-LambekPlan -Plan $plan -Simulate -AuditPath $AuditPath
                $state.Simulations[$params.id] = $simulation

                $result = [ordered]@{
                    id               = $params.id
                    status           = $simulation.Status
                    risk             = $simulation.Risk
                    confirmationCode = $simulation.ConfirmationCode
                    answer           = ConvertTo-LambekAnswer -Plan $plan -Simulation $simulation -Brief
                    steps            = @($simulation.Steps | ForEach-Object {
                            [ordered]@{ step = $_.Step; action = $_.Action; status = $_.Status; count = $_.Count; affected = @($_.Affected | Select-Object -First 50); message = $_.Message }
                        })
                }
            }
            'approve' {
                $plan = Get-LambekHostPlan -State $state -Params $params
                if (-not $state.Simulations.ContainsKey($params.id)) {
                    throw 'Simulate the plan before approving it.'
                }
                $confirmation = ''
                if ($params.ContainsKey('confirmation')) { $confirmation = [string] $params.confirmation }

                $approval = Approve-LambekPlan -Simulation $state.Simulations[$params.id] -Confirmation $confirmation -AuditPath $AuditPath
                $state.Approvals[$params.id] = $approval
                $result = [ordered]@{ id = $params.id; approved = $true; expiresAt = $approval.ExpiresAt.ToString('o') }
            }
            'run' {
                $plan = Get-LambekHostPlan -State $state -Params $params
                $approval = $null
                if ($state.Approvals.ContainsKey($params.id)) { $approval = $state.Approvals[$params.id] }

                $execution = Invoke-LambekPlan -Plan $plan -Approval $approval -AuditPath $AuditPath
                # A plan the user ran is a confirmation: the belief of its chat is sure again (no drift since)
                if ($execution.Status -eq 'Completed' -and $state.Contains('Beliefs')) {
                    foreach ($entry in $state.Beliefs.Values) { if ($entry.Plan -eq $plan.PlanHash) { $entry.Turns = 0 } }
                }
                $result = [ordered]@{
                    id     = $params.id
                    status = $execution.Status
                    reason = $execution.Reason
                    answer = ConvertTo-LambekAnswer -Plan $plan -Execution $execution -Brief
                    steps  = @($execution.Steps | ForEach-Object {
                            [ordered]@{
                                step   = $_.Step
                                action = $_.Action
                                status = $_.Status
                                error  = $_.Error
                                output = @($_.Output | Select-Object -First 100 | ForEach-Object { ConvertTo-LambekHostValue -Value $_ })
                            }
                        })
                }
            }
            'audit' {
                $limit = 50
                if ($params.ContainsKey('limit')) { $limit = [int] $params.limit }
                $entries = @()
                $valid = $true
                if (Test-Path -LiteralPath $AuditPath) {
                    $entries = @(Get-Content -LiteralPath $AuditPath -Tail $limit | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
                    $valid = (Test-LambekAudit -Path $AuditPath).IsValid
                }
                $result = [ordered]@{ valid = $valid; entries = $entries }
            }
            'inspect' {
                # Files sent without a message: what Lambek can read from them
                $paths = @($params['paths'] | Where-Object { $_ } | ForEach-Object { [string] $_ })
                if ($paths.Count -eq 0) { throw 'inspect needs paths.' }
                $language = 'en'
                if ($script:LanguageHint) { $language = $script:LanguageHint }
                $result = [ordered]@{ kind = 'files'; language = $language; answer = (Get-LambekFileReport -Path $paths -Language $language) }
            }
            default {
                throw "Unknown method '$($request.method)'."
            }
        }

        $response = [ordered]@{ id = $id; result = $result }
    }
    catch {
        $response = [ordered]@{ id = $id; error = [ordered]@{ message = $_.Exception.Message } }
    }
    finally {
        $script:LanguageHint = $null
        $script:Incognito = $false
    }

    return ($response | ConvertTo-Json -Depth 12 -Compress)
}

function Get-LambekHostPlan {
    param(
        [hashtable] $State,
        [hashtable] $Params
    )

    if (-not $Params.ContainsKey('id') -or -not $State.Plans.Contains($Params.id)) {
        throw 'Unknown plan id. Ask again.'
    }
    return $State.Plans[$Params.id]
}
