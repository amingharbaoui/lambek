function ConvertTo-LambekTerm {
    param([AllowNull()] [object] $Value)

    # A value as a constant of the logic: plain letters, so "Lyon" told and "lyon" asked are the same thing
    $text = ConvertTo-LambekNormalizedText -Text (Format-LambekValue -Value $Value)
    return '"' + "$text".Trim().Replace('"', '""') + '"'
}

function Get-LambekAskedRule {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Asked
    )

    # The meaning of a question is the body of a rule: "where does my sister live" is
    #   answer(E) :- event(E, "verb:live"), agent(E, "my sister"), says(E, "place").
    # Every event that satisfies it is an answer, with the proof of why
    if ($Asked.All) { return 'answer(E) :- event(E, V).' }
    $rules = foreach ($action in @($Asked.Actions)) {
        $body = [System.Collections.Generic.List[string]]::new()
        $body.Add("event(E, $(ConvertTo-LambekTerm -Value $action))")
        $either = $Asked.PSObject.Properties['Either'] -and $Asked.Either -and $Asked.Wanted -eq 'agent' -and $Asked.Parameters.Contains('object')
        if ($either) {
            # "what is my name": the other side of "my name is Amin", whichever side it was told on
            $body.Add("about(E, $(ConvertTo-LambekTerm -Value $Asked.Parameters['object']))")
        }
        else {
            if ($Asked.PSObject.Properties['Name'] -and $Asked.Name) { $body.Add("agent(E, $(ConvertTo-LambekTerm -Value $Asked.Name))") }
            elseif ($Asked.Person) { $body.Add("by(E, ""$($Asked.Person)"")") }
            if ($Asked.PSObject.Properties['Wanted'] -and $Asked.Wanted -in 'object', 'place') { $body.Add("says(E, ""$($Asked.Wanted)"")") }
            foreach ($name in $Asked.Parameters.Keys) { $body.Add("holds(E, $(ConvertTo-LambekTerm -Value $name), $(ConvertTo-LambekTerm -Value $Asked.Parameters[$name]))") }
        }
        # The same words of time mean the same day only when they were said the same day
        if ($Asked.Time) { $body.Add("on(E, ""$($Asked.Day)"")") }
        "answer(E) :- $($body -join ', ')."
    }
    return (@($rules) -join "`n")
}

function Get-LambekToldLogic {
    [CmdletBinding()]
    param(
        # The things told, each one an event of the logic: e0, e1, ...
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Facts
    )

    # Everything told, as facts of the logic (an event, who, what goes with it, when), with the rules
    # that say what follows from them and the words each language has for "be" and "in"
    $logic = [LambekLogic]::new()
    if ($null -eq $script:KnowledgeRules) {
        $script:KnowledgeRules = ConvertFrom-LambekLogic -Text (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Data/knowledge.dl') -Raw)
    }
    foreach ($clause in $script:KnowledgeRules) { $logic.Rules.Add($clause) }
    foreach ($language in Get-LambekAvailableLanguage) {
        $dialogue = (Get-LambekLexicon -Language $language).Dialogue
        if (-not $dialogue -or -not $dialogue['General'] -or -not $dialogue['General']['Logic']) { continue }
        foreach ($name in $dialogue['General']['Logic'].Keys) {
            foreach ($word in @($dialogue['General']['Logic'][$name])) { [void] $logic.Add($name, [string[]] @("$word")) }
        }
    }
    $plain = { param($value) (ConvertTo-LambekNormalizedText -Text (Format-LambekValue -Value $value)).Trim() }
    for ($i = 0; $i -lt $Facts.Count; $i++) {
        $fact = $Facts[$i]
        $id = "e$i"
        [void] $logic.Add('event', [string[]] @($id, (& $plain $fact.Action)))
        $who = 'speaker'
        if ($fact.Agent -ne 'speaker') { $who = & $plain $fact.Name; if (-not $who) { $who = 'other' } }
        [void] $logic.Add('agent', [string[]] @($id, $who))
        # A thing read back from the journal carries its values as text; one of this conversation, as they were read
        if ($fact.PSObject.Properties['Values']) { $roles = $fact.Values } else { $roles = $fact.Parameters }
        foreach ($name in @($roles.Keys)) { [void] $logic.Add('role', [string[]] @($id, (& $plain $name), (& $plain $roles[$name]))) }
        if ($fact.Day) { [void] $logic.Add('on', [string[]] @($id, "$($fact.Day)")) }
    }
    return $logic
}

function Find-LambekTold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Asked,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Facts
    )

    # The question is added to the logic as a rule, and the logic is run: the answers are the events it proves.
    # An answer that needed more than the event itself (Lyon is in France) comes with the events it was deduced from
    $logic = Get-LambekToldLogic -Facts $Facts
    $question = ConvertFrom-LambekLogic -Text (Get-LambekAskedRule -Asked $Asked)
    foreach ($clause in $question) { $logic.Rules.Add($clause) }
    $logic.Run()
    $answers = @($logic.Get('answer') | ForEach-Object { [int] "$($_[0])".Substring(1) } | Sort-Object -Unique)
    foreach ($index in $answers) {
        $because = [System.Collections.Generic.SortedSet[int]]::new()
        foreach ($line in $logic.Explain('answer', [string[]] @("e$index"), 8)) {
            foreach ($match in [regex]::Matches($line, '\("e(\d+)"')) {
                $other = [int] $match.Groups[1].Value
                if ($other -ne $index) { [void] $because.Add($other) }
            }
        }
        [pscustomobject]@{ Fact = $Facts[$index]; Because = @($because | ForEach-Object { $Facts[$_] }) }
    }
}
