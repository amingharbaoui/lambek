BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Send-HostRequest {
        param([hashtable] $Request, [string] $AuditPath)
        $line = $Request | ConvertTo-Json -Depth 5 -Compress
        $json = InModuleScope Lambek -Parameters @{ Line = $line; AuditPath = $AuditPath } {
            Invoke-LambekHostRequest -Line $Line -AuditPath $AuditPath
        }
        return $json | ConvertFrom-Json -AsHashtable
    }
}

Describe 'Invoke-LambekHostRequest' {

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $source = Join-Path $root 'src'
        $audit = Join-Path $root 'audit.jsonl'
        New-Item -Path $source -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.log') -Value 'a'
        Set-Content -Path (Join-Path $source 'b.tmp') -Value 'b'
    }

    It 'reports the stages of a request while it runs' {
        $stages = InModuleScope Lambek {
            $seen = [System.Collections.Generic.List[string]]::new()
            $script:ProgressHandler = { param($Stage, $Step) $seen.Add("$Stage $Step") }.GetNewClosure()
            try { New-LambekPlan 'list the files in C:\Temp then delete the .log files in C:\Temp' | Out-Null }
            finally { $script:ProgressHandler = $null }
            $seen
        }
        $stages | Should -Be @('Split 0', 'Read 1', 'Match 1', 'Check 1', 'Read 2', 'Match 2', 'Check 2', 'Order 0')
    }

    It 'reports a share of the work that only grows' {
        $percents = InModuleScope Lambek {
            $seen = [System.Collections.Generic.List[int]]::new()
            $script:ProgressHandler = { param($Stage, $Step, $Percent) $seen.Add($Percent) }.GetNewClosure()
            try { New-LambekPlan 'list the files in C:\Temp then delete the .log files in C:\Temp' | Out-Null }
            finally { $script:ProgressHandler = $null }
            $seen
        }
        $percents | Should -Be @(0, 12, 25, 38, 50, 62, 75, 88)
    }

    It 'sends the types of each step once they are checked' {
        $types = InModuleScope Lambek {
            $seen = [System.Collections.Generic.List[string]]::new()
            $script:ProgressHandler = { param($Stage, $Step, $Percent, $Types) if ($Types) { $seen.Add("$Step $Types") } }.GetNewClosure()
            try { New-LambekPlan 'list the files in C:\Temp' | Out-Null }
            finally { $script:ProgressHandler = $null }
            $seen
        }
        @($types).Count | Should -Be 1
        @($types)[0] | Should -Match '^1 .*\bs\b'
    }

    It 'keeps the language of the chat for a message that fits any language' {
        $response = Send-HostRequest @{ id = 4; method = 'ask'; params = @{ text = 'ok'; language = 'fr' } } $audit
        $response.result.answer | Should -Be 'Très bien. Dites-moi quand vous avez besoin de quelque chose.'
        $response.result.language | Should -Be 'fr'
    }

    It 'marks small talk, and only small talk' {
        (Send-HostRequest @{ id = 4; method = 'ask'; params = @{ text = 'how are you ?' } } $audit).result.talk | Should -BeTrue
        (Send-HostRequest @{ id = 5; method = 'ask'; params = @{ text = 'blorp the zork' } } $audit).result.talk | Should -BeFalse
        (Send-HostRequest @{ id = 6; method = 'ask'; params = @{ text = 'list the files in C:\Temp' } } $audit).result.talk | Should -BeFalse
    }

    It 'follows the language of the message when it is clear' {
        $response = Send-HostRequest @{ id = 5; method = 'ask'; params = @{ text = 'thank you'; language = 'fr' } } $audit
        $response.result.answer | Should -Be "You're welcome."
        $response.result.language | Should -Be 'en'
    }

    It 'says whether the chat is incognito' {
        $private = Send-HostRequest @{ id = 7; method = 'ask'; params = @{ text = 'Je suis incognito là ?'; incognito = $true } } $audit
        $private.result.answer | Should -Be 'Oui. Ce chat reste hors de votre historique.'
        $saved = Send-HostRequest @{ id = 8; method = 'ask'; params = @{ text = 'am i incognito?' } } $audit
        $saved.result.answer | Should -BeLike 'No, this chat is saved*'
    }

        It 'reads files sent without a message' {
        $photo = (Resolve-Path "$PSScriptRoot/Fixtures/Photo.jpg").Path
        $response = Send-HostRequest @{ id = 6; method = 'inspect'; params = @{ paths = @($photo); language = 'en' } } $audit
        $response.result.kind | Should -Be 'files'
        ($response.result.answer -split "`n")[0] | Should -BeLike 'Photo.jpg is a JPEG image of 1920 × 1080 pixels, *'
    }

    It 'answers ping with the version' {
        $response = Send-HostRequest @{ id = 1; method = 'ping' } $audit
        $response.id | Should -Be 1
        $response.result.name | Should -Be 'Lambek'
    }

    It 'lists the packs' {
        $response = Send-HostRequest @{ id = 1; method = 'packs' } $audit
        $response.result.name | Should -Contain 'files'
    }

    It 'returns a plan with a plain answer' {
        $response = Send-HostRequest @{ id = 2; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $response.result.status | Should -Be 'Ready'
        $response.result.answer | Should -BeNullOrEmpty
        $response.result.sentences[0] | Should -Be "delete the .log files in $source"
        $response.result.trace.stage | Should -Contain 'Type'
        $response.result.steps[0].parameters.Extension | Should -Be '.log'
        $response.result.steps[0].safe | Should -BeTrue
    }

    It 'answers a message it cannot match with or without a context' -ForEach @(
        @{ Params = @{ text = 'hello' } }
        @{ Params = @{ text = 'hello'; context = $null; step = $null } }
        @{ Params = @{ text = 'hello'; context = 'unknown'; step = 2 } }
    ) {
        $response = Send-HostRequest @{ id = 3; method = 'ask'; params = $Params } $audit
        $response.ContainsKey('error') | Should -BeFalse
        $response.result.status | Should -Be 'NeedsInput'
        $response.result.answer | Should -Not -BeNullOrEmpty
    }

    It 'asks for a code only when something would change' {
        $some = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        (Send-HostRequest @{ id = 2; method = 'simulate'; params = @{ id = $some.result.id } } $audit).result.answer | Should -BeLike '*Type * to confirm.*'

        $none = Send-HostRequest @{ id = 3; method = 'ask'; params = @{ text = "delete the .bak files in ""$source""" } } $audit
        $answer = (Send-HostRequest @{ id = 4; method = 'simulate'; params = @{ id = $none.result.id } } $audit).result.answer
        $answer | Should -BeLike '*Nothing matches, so nothing would change.*'
        $answer | Should -Not -BeLike '*to confirm*'
    }

    It 'runs the whole flow: ask, simulate, approve, run' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $planId = $ask.result.id

        $simulation = Send-HostRequest @{ id = 2; method = 'simulate'; params = @{ id = $planId } } $audit
        $simulation.result.steps[0].count | Should -Be 1
        $simulation.result.confirmationCode | Should -Match '^[0-9A-F]{6}$'
        Test-Path (Join-Path $source 'a.log') | Should -BeTrue

        $approve = Send-HostRequest @{ id = 3; method = 'approve'; params = @{ id = $planId; confirmation = $simulation.result.confirmationCode } } $audit
        $approve.result.approved | Should -BeTrue

        $run = Send-HostRequest @{ id = 4; method = 'run'; params = @{ id = $planId } } $audit
        $run.result.status | Should -Be 'Completed'
        $run.result.answer | Should -Be 'Done.'
        Test-Path (Join-Path $source 'a.log') | Should -BeFalse
        Test-Path (Join-Path $source 'b.tmp') | Should -BeTrue
    }

    It 'edits a parameter and returns a new plan' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $ask.result.steps[0].schema.name | Should -Contain 'MinSize'

        $edit = Send-HostRequest @{ id = 2; method = 'edit'; params = @{ id = $ask.result.id; step = 1; name = 'Extension'; value = '.tmp' } } $audit
        $edit.result.id | Should -Not -Be $ask.result.id
        $edit.result.steps[0].parameters.Extension | Should -Be '.tmp'
        $edit.result.sentences[0] | Should -Be "delete the .tmp files in $source"
    }

    It 'edits the current plan from a chat message' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $next = Send-HostRequest @{ id = 2; method = 'ask'; params = @{ text = 'use .tmp instead'; context = $ask.result.id } } $audit
        $next.result.kind | Should -Be 'edit'
        $next.result.steps[0].parameters.Extension | Should -Be '.tmp'
    }

    It 'explains the current plan' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $next = Send-HostRequest @{ id = 2; method = 'ask'; params = @{ text = 'explain'; context = $ask.result.id } } $audit
        $next.result.kind | Should -Be 'explain'
        $next.result.answer | Should -BeLike '*AST firewall*'
    }

    It 'lists the categories' {
        $response = Send-HostRequest @{ id = 1; method = 'categories' } $audit
        $response.result.title | Should -Contain 'Files'
        $response.result[0].examples.Count | Should -BeGreaterThan 0
    }

    It 'reports an invalid edit as an error' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $edit = Send-HostRequest @{ id = 2; method = 'edit'; params = @{ id = $ask.result.id; step = 1; name = 'MinSize'; value = 'huge' } } $audit
        $edit.error.message | Should -BeLike '*must be a size*'
    }

    It 'refuses to approve without the confirmation code' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        Send-HostRequest @{ id = 2; method = 'simulate'; params = @{ id = $ask.result.id } } $audit | Out-Null

        $approve = Send-HostRequest @{ id = 3; method = 'approve'; params = @{ id = $ask.result.id } } $audit
        $approve.error.message | Should -BeLike '*confirmation code*'
    }

    It 'refuses to run a high-risk plan without approval' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "delete the .log files in ""$source""" } } $audit
        $run = Send-HostRequest @{ id = 2; method = 'run'; params = @{ id = $ask.result.id } } $audit
        $run.result.status | Should -Be 'Refused'
        Test-Path (Join-Path $source 'a.log') | Should -BeTrue
    }

    It 'returns the audit entries' {
        $ask = Send-HostRequest @{ id = 1; method = 'ask'; params = @{ text = "list the files in ""$source""" } } $audit
        Send-HostRequest @{ id = 2; method = 'simulate'; params = @{ id = $ask.result.id } } $audit | Out-Null

        $response = Send-HostRequest @{ id = 3; method = 'audit' } $audit
        $response.result.valid | Should -BeTrue
        $response.result.entries[0].Event | Should -Be 'Simulated'
    }

    It 'reports errors as JSON' -ForEach @(
        @{ Line = 'not json'; Message = '*not valid JSON*' }
        @{ Line = '{"id":1}'; Message = '*needs a method*' }
        @{ Line = '{"id":1,"method":"nope"}'; Message = "*Unknown method*" }
        @{ Line = '{"id":1,"method":"ask","params":{}}'; Message = '*needs a text*' }
        @{ Line = '{"id":1,"method":"run","params":{"id":"missing"}}'; Message = '*Unknown plan id*' }
    ) {
        $json = InModuleScope Lambek -Parameters @{ Line = $Line; AuditPath = $audit } {
            Invoke-LambekHostRequest -Line $Line -AuditPath $AuditPath
        }
        ($json | ConvertFrom-Json).error.message | Should -BeLike $Message
    }
}

Describe 'Start-LambekHost through a real process' {

    It 'reads requests on standard input and writes one JSON line per answer' {
        $module = (Resolve-Path "$PSScriptRoot/../Lambek/Lambek.psd1").Path
        $files = (Resolve-Path "$PSScriptRoot/../../dsl/files").Path
        $audit = Join-Path $TestDrive 'host-audit.jsonl'

        $info = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        $info.ArgumentList.Add('-NoProfile')
        $info.ArgumentList.Add('-NoLogo')
        $info.ArgumentList.Add('-Command')
        $info.ArgumentList.Add("Import-Module '$module'; Start-LambekHost -PackPath '$files' -AuditPath '$audit'")
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.UseShellExecute = $false

        $process = [System.Diagnostics.Process]::Start($info)
        try {
            $process.StandardInput.WriteLine('{"id":1,"method":"ping"}')
            $process.StandardInput.WriteLine('{"id":2,"method":"ask","params":{"text":"list the files in C:\\Temp"}}')
            $process.StandardInput.Close()

            $lines = @()
            while ($null -ne ($line = $process.StandardOutput.ReadLine())) { $lines += $line }
            $process.WaitForExit(30000) | Out-Null
        }
        finally {
            if (-not $process.HasExited) { $process.Kill() }
        }

        # Progress lines come before each answer
        $messages = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
        $answers = @($messages | Where-Object { $_.PSObject.Properties['id'] -and -not $_.PSObject.Properties['event'] })
        $messages[0].event | Should -Be 'ready'
        @($messages | Where-Object { $_.PSObject.Properties['event'] -and $_.event -eq 'progress' }).stage | Should -Be @('Split', 'Read', 'Match', 'Check', 'Order')
        $answers.Count | Should -Be 2
        $answers[0].result.name | Should -Be 'Lambek'
        $answers[1].result.sentences[0] | Should -Be 'list the files in C:\Temp'
    }

    It 'reads and writes UTF-8 whatever the console code page' {
        $module = (Resolve-Path "$PSScriptRoot/../Lambek/Lambek.psd1").Path
        $files = (Resolve-Path "$PSScriptRoot/../../dsl/files").Path
        $audit = Join-Path $TestDrive 'host-utf8-audit.jsonl'

        $info = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        foreach ($argument in '-NoProfile', '-NoLogo', '-Command', "Import-Module '$module'; Start-LambekHost -PackPath '$files' -AuditPath '$audit'") {
            $info.ArgumentList.Add($argument)
        }
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.UseShellExecute = $false

        # Raw bytes in both directions, like the app
        $process = [System.Diagnostics.Process]::Start($info)
        try {
            $request = [System.Text.Encoding]::UTF8.GetBytes('{"id":1,"method":"ask","params":{"text":"crée un dossier nommé \"Été\" dans C:\\Temp"}}' + "`n")
            $process.StandardInput.BaseStream.Write($request, 0, $request.Length)
            $process.StandardInput.Close()

            $buffer = [System.IO.MemoryStream]::new()
            $process.StandardOutput.BaseStream.CopyTo($buffer)
            $process.WaitForExit(30000) | Out-Null
        }
        finally {
            if (-not $process.HasExited) { $process.Kill() }
        }

        # Strict decoding fails on any byte that is not UTF-8
        $strict = [System.Text.UTF8Encoding]::new($false, $true)
        $text = $strict.GetString($buffer.ToArray())
        $answer = @($text -split "`n" | Where-Object { $_ -like '{"id":1*' })[0] | ConvertFrom-Json
        $answer.result.sentences[0] | Should -Be 'créer un dossier nommé Été dans C:\Temp'
    }
}
