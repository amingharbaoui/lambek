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
        $isRequired = $parameter.ContainsKey('Required') -and $parameter.Required
        if (-not $isRequired -or $Parameters.Contains($parameter.Name)) { continue }

        $missing.Add($parameter.Name)
        $question = "Missing: $($parameter.Name)"
        if ($parameter.ContainsKey('Question')) {
            if ($parameter.Question.ContainsKey($Language)) { $question = $parameter.Question[$Language] }
            elseif ($parameter.Question.ContainsKey('en')) { $question = $parameter.Question['en'] }
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
