function Resolve-LambekCodeRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        # The plan the chat is about, when there is one
        [pscustomobject] $Plan
    )

    # Nothing here unless the message names one of the six languages
    $asked = Get-LambekCodeAsk -Text $Text
    if (-not $asked) { return $null }

    # "write a python script that deletes the .log files in C:\Temp": the task is read by the normal pipeline,
    # and only a plan that is ready and can be a program is answered here
    if ($asked.Inner) {
        $inner = New-LambekPlan -Text $asked.Inner
        if ($inner.Status -eq 'Ready') {
            $code = ConvertTo-LambekCode -Plan $inner -Language $asked.InnerLanguage
            if ($code.Unsupported.Count -eq 0) {
                return [pscustomobject]@{ Kind = 'new'; Plan = $inner; Answer = (Format-LambekCodeAnswer -Code $code -Plan $inner); Code = $code }
            }
        }
    }
    if (-not $asked.Language) { return $null }

    # "in python": about the plan of the chat. A plan that is code already changes its language the usual way
    if (-not $Plan) { return $null }
    $steps = @($Plan.Steps | Where-Object { $_.Action })
    if ($steps.Count -eq 0) { return $null }
    foreach ($step in $steps) {
        if ((Get-LambekAction -Id $step.Action).Action.Output -eq 'code') { return $null }
    }
    if ($Plan.Status -ne 'Ready') {
        $answer = (Get-LambekLexicon -Language $steps[0].Language).Answer
        return [pscustomobject]@{ Kind = 'explain'; Plan = $Plan; Answer = $answer.CodeNotReady; Code = $null }
    }
    $code = ConvertTo-LambekCode -Plan $Plan -Language $asked.Language
    return [pscustomobject]@{ Kind = 'explain'; Plan = $Plan; Answer = (Format-LambekCodeAnswer -Code $code -Plan $Plan); Code = $code }
}

function Get-LambekCodeAsk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # The words that ask for code, in every language: the question may come in another one than the plan
    $allowed = [System.Collections.Generic.HashSet[string]]::new()
    $makes = [System.Collections.Generic.HashSet[string]]::new()
    $these = [System.Collections.Generic.HashSet[string]]::new()
    $thats = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($language in Get-LambekAvailableLanguage) {
        $lexicon = Get-LambekLexicon -Language $language
        $followUp = $lexicon.FollowUp
        foreach ($word in @($followUp['Export']) + @($followUp['Filler']) + @($lexicon.StopWords)) { if ($word) { [void] $allowed.Add($word) } }
        foreach ($word in @($followUp['ExportMake'])) { if ($word) { [void] $makes.Add($word) } }
        foreach ($word in @($followUp['ExportThis'])) { if ($word) { [void] $these.Add($word) } }
        foreach ($word in @($followUp['ExportThat'])) { if ($word) { [void] $thats.Add($word) } }
    }

    # "C#" and "Node.js" are one word each
    $plain = $Text -replace '(?i)(?<![\w#])c\s?#(?![\w#])|\bc[- ]sharp\b', 'csharp'
    $plain = $plain -replace '(?i)\bnode\.js\b', 'node'

    # Form 1, the whole task in one sentence: "<make> a <language> script <that> <task>".
    # The words before the first "that" after the language only ask for code; what follows is the task
    $named = $null
    $inner = $null
    $innerLanguage = $null
    foreach ($piece in [regex]::Matches($plain, '[\p{L}\p{N}_#]+')) {
        $word = ConvertTo-LambekNormalizedText -Text $piece.Value
        if (-not $named) {
            if (Resolve-LambekCodeLanguage -Name $word) { $named = $piece }
            continue
        }
        if (-not $thats.Contains($word)) { continue }
        $head = $plain.Substring(0, $piece.Index)
        $rest = $plain.Substring($piece.Index + $piece.Length).Trim()
        $language = Get-LambekCodeAskLanguage -Text $head -Allowed $allowed -Makes $makes -These $these -Lone
        if ($language -and $rest -match '\p{L}') {
            $inner = $rest
            $innerLanguage = $language
        }
        break
    }

    # Form 2, about the plan of the chat: "in python", "show me this in bash"
    $language = Get-LambekCodeAskLanguage -Text $plain -Allowed $allowed -Makes $makes -These $these
    if (-not $language -and -not $inner) { return $null }
    return [pscustomobject]@{ Language = $language; Inner = $inner; InnerLanguage = $innerLanguage }
}

function Get-LambekCodeAskLanguage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [System.Collections.Generic.HashSet[string]] $Allowed,
        [System.Collections.Generic.HashSet[string]] $Makes,
        [System.Collections.Generic.HashSet[string]] $These,

        # The words stand before a task of their own: "write" needs no "this"
        [switch] $Lone
    )

    # Paths, quoted names and extensions are no words: ".py" names files, not a language
    $words = @(Get-LambekLanguageToken -Text $Text)
    $language = $null
    $made = $false
    $pointed = $false
    foreach ($word in $words) {
        $known = Resolve-LambekCodeLanguage -Name $word
        if ($known) {
            # Two languages in one message: nothing is guessed
            if ($language -and $language -ne $known.Name) { return $null }
            $language = $known.Name
            continue
        }
        $isKnown = $false
        if ($Makes.Contains($word)) { $made = $true; $isKnown = $true }
        if ($These.Contains($word)) { $pointed = $true; $isKnown = $true }
        if ($Allowed.Contains($word)) { $isKnown = $true }
        # Any other word: the message says more than "give me code"
        if (-not $isKnown) { return $null }
    }
    if (-not $language) { return $null }

    # "write a python script" starts new code; "write it in python" is about the plan
    if ($made -and -not $pointed -and -not $Lone) { return $null }
    return $language
}

function Format-LambekCodeAnswer {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Code,

        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    # The answer is in the language of the plan
    $language = 'en'
    $first = @($Plan.Steps | Where-Object { $_.Language } | Select-Object -First 1)
    if ($first.Count -gt 0) { $language = $first[0].Language }
    $answer = (Get-LambekLexicon -Language $language).Answer
    $known = Resolve-LambekCodeLanguage -Name $Code.Language
    $lines = [System.Collections.Generic.List[string]]::new()

    # A step that cannot be a program: no code at all, and the reason
    if ($Code.Unsupported.Count -gt 0) {
        foreach ($step in $Code.Unsupported) { $lines.Add(($answer.CodeUnsupported -f $step.Step, $step.Reason)) }
        return $lines -join "`n"
    }

    # The code between fences longer than any run of backticks inside it
    $longest = 2
    foreach ($run in [regex]::Matches($Code.Code, '`+')) {
        if ($run.Length -gt $longest) { $longest = $run.Length }
    }
    $fence = '`' * ($longest + 1)
    $lines.Add(($answer.Code -f $known.Shown, $Code.FileName))
    $lines.Add("$fence$($known.Fence)")
    $lines.Add($Code.Code.TrimEnd("`n"))
    $lines.Add($fence)

    # Whether the syntax was checked, and by which tool
    $syntax = $Code.Syntax
    if (-not $syntax -or -not $syntax.Checked) {
        $why = ''
        if ($syntax) { $why = [string] $syntax.Message }
        $lines.Add(($answer.CodeUnchecked -f $why).TrimEnd(' ', ':'))
    }
    elseif ($syntax.Valid) { $lines.Add(($answer.CodeChecked -f $syntax.Tool)) }
    else { $lines.Add(($answer.CodeInvalid -f $syntax.Tool, ($syntax.Errors -join '; '))) }

    # What starting it does
    $switch = '--apply'
    if ($known.Name -eq 'PowerShell') { $switch = '-Apply' }
    $model = ConvertTo-LambekCodeModel -Plan $Plan
    $need = Get-LambekCodeNeed -Model $model
    if ($need.Changes) { $lines.Add(($answer.CodeApply -f $switch)) }
    if ($need.Delete) { $lines.Add(($answer.CodeDelete -f $switch)) }
    foreach ($note in $Code.Notes) { $lines.Add($note) }
    return $lines -join "`n"
}
