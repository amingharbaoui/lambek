function Invoke-LambekQuery {
    <#
    .SYNOPSIS
        Asks the knowledge of Lambek a question in Datalog: what it knows about the machine and its rules.
    .EXAMPLE
        Invoke-LambekQuery 'protected(P)'
    .EXAMPLE
        Invoke-LambekQuery 'blocked("C:\Windows\System32", R)' -Changes 'C:\Windows\System32'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Query,

        # Paths to treat as changed, to see what the rules say about them
        [string[]] $Changes = @(),

        # Each answer with the proof that gives it
        [switch] $Explain
    )

    $literal = ConvertFrom-LambekLiteral -Text $Query.TrimEnd('.', ' ')
    $logic = Get-LambekKnowledge -Facts @{ changes = @($Changes | ForEach-Object { , @($_) }) }
    $found = [System.Collections.Generic.List[hashtable]]::new()
    $logic.Match([object[]] @($literal), 0, @{}, -1, $null, $found)
    foreach ($binding in $found) {
        $row = [ordered]@{}
        foreach ($term in $literal.Terms) {
            if ([LambekLogic]::IsVariable($term) -and $term -ne '_') { $row[$term] = $binding[$term] }
        }
        if ($Explain) {
            $terms = [string[]] @($literal.Terms | ForEach-Object { if ([LambekLogic]::IsVariable($_)) { $binding[$_] } else { [LambekLogic]::Value($_) } })
            $row['Proof'] = @($logic.Explain($literal.Name, $terms, 8))
        }
        [pscustomobject]$row
    }
}
