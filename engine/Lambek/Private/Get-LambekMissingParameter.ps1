function Get-LambekMissingParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Action,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Parameters,

        [Parameter(Mandatory)]
        [string] $Language
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    $questions = [System.Collections.Generic.List[string]]::new()

    # Required parameters
    foreach ($parameter in $Action.Parameters) {
        # Required always, or only with another one ("how many?" once an order is given)
        $isRequired = $parameter.ContainsKey('Required') -and $parameter.Required
        # (a reading keeps every item in order when no count is given: "the largest files" are all of them, largest first)
        if ($parameter.ContainsKey('RequiredWith') -and $Parameters.Contains($parameter.RequiredWith) -and -not $parameter['AllWhenMissing']) { $isRequired = $true }
        if (-not $isRequired -or $Parameters.Contains($parameter.Name)) { continue }

        $missing.Add($parameter.Name)
        $question = "Missing: $($parameter.Name)"
        if ($parameter.ContainsKey('Question')) {
            if ($parameter.Question.ContainsKey($Language)) { $question = $parameter.Question[$Language] }
            elseif ($parameter.Question.ContainsKey('en')) { $question = $parameter.Question['en'] }
        }
        $questions.Add($question)
    }

    # A value that only means something with another one ("5 files": which 5?)
    foreach ($parameter in $Action.Parameters) {
        if (-not $parameter.ContainsKey('RequiredWith') -or -not $Parameters.Contains($parameter.Name)) { continue }
        $other = @($Action.Parameters | Where-Object { $_.Name -eq $parameter.RequiredWith })[0]
        if ($Parameters.Contains($other.Name) -or $missing.Contains($other.Name)) { continue }
        $missing.Add($other.Name)
        $question = "Missing: $($other.Name)"
        if ($other.ContainsKey('Question')) {
            if ($other.Question.ContainsKey($Language)) { $question = $other.Question[$Language] }
            elseif ($other.Question.ContainsKey('en')) { $question = $other.Question['en'] }
        }
        $questions.Add($question)
    }

    # At least one complete set of parameters (for example Path, or Parent and Name)
    if ($Action.ContainsKey('RequireOneOf')) {
        $hasSet = $false
        foreach ($set in $Action.RequireOneOf.Sets) {
            if (@($set | Where-Object { -not $Parameters.Contains($_) }).Count -eq 0) { $hasSet = $true }
        }
        if (-not $hasSet) {
            $missing.Add('RequireOneOf')
            $texts = $Action.RequireOneOf.Question
            if ($texts.ContainsKey($Language)) { $questions.Add($texts[$Language]) }
            else { $questions.Add($texts['en']) }
        }
    }

    return [pscustomobject]@{
        Missing   = $missing.ToArray()
        Questions = $questions.ToArray()
    }
}
