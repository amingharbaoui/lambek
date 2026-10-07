function ConvertTo-LambekLearnedRule {
    <#
    .SYNOPSIS
        Turns the proof of a fact into one rule that gives it directly (explanation-based generalisation):
        the proof keeps its shape, and the values the rules did not fix become variables.
    .EXAMPLE
        ConvertTo-LambekLearnedRule 'blocked("C:\Windows\System32", R)' -Changes 'C:\Windows\System32'
    .EXAMPLE
        ConvertTo-LambekLearnedRule 'path(a, d)' -Program 'edge(a, b). edge(b, d). path(X, Y) :- edge(X, Y). path(X, Z) :- edge(X, Y), path(Y, Z).'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Query,

        # Paths to treat as changed, as for Invoke-LambekQuery
        [string[]] $Changes = @(),

        # Facts and rules in Datalog to use instead of what Lambek knows
        [string] $Program
    )

    # The facts and rules: the text given, else the knowledge of Lambek
    $literal = ConvertFrom-LambekLiteral -Text $Query.TrimEnd('.', ' ')
    if ($PSBoundParameters.ContainsKey('Program')) {
        $logic = [LambekLogic]::new()
        foreach ($clause in (ConvertFrom-LambekLogic -Text $Program)) {
            if ($clause.Body.Count -eq 0) {
                [void] $logic.Add($clause.Head.Name, [string[]] @($clause.Head.Terms | ForEach-Object { [LambekLogic]::Value($_) }))
            }
            else { $logic.Rules.Add($clause) }
        }
        foreach ($path in $Changes) { [void] $logic.Add('changes', [string[]] @($path)) }
        $logic.Run()
    }
    else { $logic = Get-LambekKnowledge -Facts @{ changes = @($Changes | ForEach-Object { , @($_) }) } }

    # Each answer of the query has a proof; each proof gives one rule (the same rule is said once)
    $found = [System.Collections.Generic.List[hashtable]]::new()
    $logic.Match([object[]] @($literal), 0, @{}, -1, $null, $found)
    $said = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($binding in $found) {
        $terms = [string[]] @($literal.Terms | ForEach-Object { if ([LambekLogic]::IsVariable($_)) { $binding[$_] } else { [LambekLogic]::Value($_) } })
        $steps = 0
        $clause = [LambekLearning]::Generalise($logic, $literal.Name, $terms, [ref] $steps)
        # A fact that was given, not derived, has no proof to generalise
        if ($null -eq $clause) { continue }
        $rule = [LambekLearning]::Format($clause)
        if (-not $said.Add($rule)) { continue }
        [pscustomobject]@{
            PSTypeName = 'Lambek.LearnedRule'
            Fact       = "$($literal.Name)($(@($terms | ForEach-Object { '"' + $_.Replace('"', '""') + '"' }) -join ', '))"
            Rule       = $rule
            # How many rules the proof used: 1 means the rule is one Lambek already has
            Steps      = $steps
            IsNew      = $steps -gt 1
            Proof      = @($logic.Explain($literal.Name, $terms, 8))
        }
    }
}
