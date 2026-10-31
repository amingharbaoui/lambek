function ConvertTo-LambekBenchText {
    # A reply or an expected text, compared the same way: lower case, no accents, straight apostrophes, single spaces
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $decomposed = $Text.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $kept = [Text.StringBuilder]::new()
    foreach ($character in $decomposed.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void] $kept.Append($character)
        }
    }
    $plain = $kept.ToString() -replace "[$([char] 0x2019)$([char] 0x2018)]", "'" -replace "[$([char] 0x00AB)$([char] 0x00BB)$([char] 0x201C)$([char] 0x201D)]", '"'
    return ($plain -replace '\s+', ' ').Trim()
}

function Get-LambekReplyTemplate {
    # The replies Lambek gives when it did not understand, and those it gives when it understood but cannot answer,
    # read from every language file: each one a pattern where what is filled in ({0}, {0:one|many}) may be anything
    [CmdletBinding()]
    param()

    $kinds = [ordered]@{
        # Not understood: nothing was read that Lambek can work with
        NotUnderstood = @('Answer.Unknown', 'Dialogue.Say.Question', 'Dialogue.Say.Other', 'Dialogue.Say.Report', 'Dialogue.Say.WhoIs')
        # Understood, and said honestly that it cannot be answered from what was told
        Abstained     = @('Dialogue.Say.NotKnown', 'Dialogue.Say.NotTold', 'Dialogue.Say.NothingTold', 'Dialogue.Say.OnlyIf', 'Dialogue.Say.OnlyIfQuoted',
            'Dialogue.Say.WhyNothing', 'Dialogue.Say.ConditionalOrder', 'Answer.Define.Unknown', 'Dialogue.Categories.Unknown', 'Dialogue.Categories.Conflict', 'Dialogue.Categories.Imagine.Unknown',
            # what the router of acts knows Lambek cannot do: a story or advice, an order for elsewhere, a language not read yet
            'Answer.Open', 'Answer.Elsewhere', 'Answer.Foreign',
            # a problem where nothing told fixes what is asked ("il manque une information")
            'Dialogue.Problems.Missing')
        # A question back before going on: safe, but nothing was answered yet
        Asked         = @('Answer.NeedOne', 'Answer.NeedMany', 'GuessQuestion', 'GuessOpenQuestion', 'RephraseQuestion', 'SentenceQuestion',
            'AmbiguityQuestion', 'AmbiguityQuestion3')
    }

    $templates = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot '../Data/Languages') -Filter '*.json' | Sort-Object Name) {
        $data = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        foreach ($kind in $kinds.Keys) {
            foreach ($path in $kinds[$kind]) {
                $value = $data
                foreach ($part in $path -split '\.') {
                    if ($value -is [System.Collections.IDictionary] -and $value.Contains($part)) { $value = $value[$part] } else { $value = $null; break }
                }
                foreach ($text in @($value | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })) {
                    # Said with vous, and with tu when the user says tu
                    $forms = @($text)
                    if ($file.BaseName -eq 'fr') { $forms += [LambekSpeech]::Familiar($text, (Get-LambekDictionary -Language 'fr')) }
                    foreach ($form in @($forms | Select-Object -Unique)) {
                        # What is filled in is not known in advance: anything may stand there
                        $pattern = [regex]::Escape((ConvertTo-LambekBenchText -Text $form)) -replace '\\\{\d+(:[^}]*)?\}', '.*'
                        $templates.Add([pscustomobject]@{ Kind = $kind; Key = $path; Language = $file.BaseName; Pattern = [regex]::new("^$pattern", 'Singleline') })
                    }
                }
            }
        }
    }
    return , $templates.ToArray()
}

function Get-LambekReplyKind {
    # What a reply is: Empty, NotUnderstood, Abstained, Asked (a question back), or Said (an answer of its own)
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Text,

        [Parameter(Mandatory)]
        [object[]] $Templates
    )

    $plain = ConvertTo-LambekBenchText -Text $Text
    if (-not $plain) { return 'Empty' }
    foreach ($template in $Templates) {
        if ($template.Pattern.IsMatch($plain)) { return $template.Kind }
    }
    return 'Said'
}

function Get-LambekMessageOutcome {
    # How a turn went against what was expected of it:
    #   Correct     what was expected was said or done, or Lambek abstained where it should
    #   Unanswered  an answer or an action was expected, and Lambek said it did not understand or does not know
    #   Wrong       something else was said, or something was done that should not have been
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Expect,

        [Parameter(Mandatory)]
        [pscustomobject] $Turn
    )

    # What the case asks, read the same whether a field is written or not
    $asked = @{}
    foreach ($name in 'Reply', 'Action', 'Contains', 'Avoid', 'Accept') {
        $asked[$name] = $null
        if ($Expect.PSObject.Properties[$name]) { $asked[$name] = $Expect.$name }
    }
    $reply = $Turn.Reply
    $plain = ConvertTo-LambekBenchText -Text $reply
    $contains = {
        param([string[]] $Wanted)
        foreach ($item in $Wanted) {
            $choices = @(($item -split '\|') | ForEach-Object { ConvertTo-LambekBenchText -Text $_ } | Where-Object { $_ })
            if (@($choices | Where-Object { $plain.Contains($_) }).Count -eq 0) { return $false }
        }
        return $true
    }
    $avoided = @(@($asked['Avoid']) | Where-Object { $_ } | Where-Object { $plain.Contains((ConvertTo-LambekBenchText -Text $_)) })
    $acted = @($Turn.Actions)

    switch ($asked['Reply']) {
        'action' {
            if ($Turn.Status -eq 'Ready') {
                if ($acted.Count -eq 1 -and $acted[0] -eq $asked['Action']) { return 'Correct' }
                return 'Wrong'
            }
            # A question back before acting is safe, but the request was not done
            return 'Unanswered'
        }
        'abstain' {
            if ($Turn.Status -eq 'Ready' -and $acted.Count -gt 0) { return 'Wrong' }
            if ($avoided.Count -gt 0) { return 'Wrong' }
            if ($Turn.Kind -in 'NotUnderstood', 'Abstained', 'Asked', 'Empty') { return 'Correct' }
            $accept = @(@($asked['Accept']) | Where-Object { $_ })
            if ($accept.Count -gt 0 -and (& $contains @($accept -join '|'))) { return 'Correct' }
            return 'Wrong'
        }
        default {
            # An answer is expected
            if ($Turn.Status -eq 'Ready' -and $acted.Count -gt 0) { return 'Wrong' }
            if ($Turn.Kind -in 'NotUnderstood', 'Abstained', 'Asked', 'Empty') { return 'Unanswered' }
            if ($avoided.Count -gt 0) { return 'Wrong' }
            if (& $contains @(@($asked['Contains']) | Where-Object { $_ })) { return 'Correct' }
            return 'Wrong'
        }
    }
}

function Get-LambekMessageBenchmarkHash {
    # The hash of the cases of a split, as written: the test split is frozen, and this says whether it changed
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]] $Cases
    )

    $text = ConvertTo-Json -InputObject @($Cases) -Depth 20 -Compress
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
}
