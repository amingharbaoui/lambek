function Find-LambekRenameRule {
    <#
    .SYNOPSIS
        Finds the simplest rule that turns each example name into its new name, applies it to the other names,
        and says which name to ask about when another rule would name it differently.
    .EXAMPLE
        Find-LambekRenameRule -Example @{ 'IMG_001.jpg' = 'holiday_001.jpg' } -Name 'IMG_001.jpg', 'IMG_002.jpg'
    #>
    [CmdletBinding()]
    param(
        # Old name = new name (file names, not paths); an ordered table keeps its order
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Example,

        # Every file name of the folder, in the order the counters follow
        [string[]] $Name = @(),

        # File name = date of the file, for rules that write a date
        [System.Collections.IDictionary] $Time = @{}
    )

    # The examples in a fixed order: as given when the table is ordered, else by name
    $olds = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $Example.Keys) { $olds.Add([string] $key) }
    if ($Example -isnot [System.Collections.Specialized.OrderedDictionary]) { $olds.Sort([System.StringComparer]::Ordinal) }
    if ($olds.Count -eq 0) { throw 'Give at least one example: old name = new name.' }

    # The whole list: the names given, with the examples that are not among them put first
    $all = [System.Collections.Generic.List[string]]::new()
    foreach ($old in $olds) {
        if ($Name -cnotcontains $old) { $all.Add($old) }
    }
    foreach ($one in $Name) {
        if (-not $all.Contains($one)) { $all.Add($one) }
    }

    $items = for ($i = 0; $i -lt $all.Count; $i++) {
        $target = ''
        if ($Example.Contains($all[$i])) { $target = [string] $Example[$all[$i]] }
        $when = $null
        if ($Time.Contains($all[$i])) { $when = [datetime] $Time[$all[$i]] }
        [LambekRenameItem]::new($all[$i], $target, $i, $when)
    }

    # An empty new name is refused before any search
    $empty = @($olds | Where-Object { [string]::IsNullOrWhiteSpace([string] $Example[$_]) })
    if ($empty.Count -gt 0) {
        $result = [LambekRenameResult]::new()
        $result.Reason = 'The new name of an example is empty.'
        $result.Names = [string[]] $all.ToArray()
        $result.Targets = [string[]]::new($all.Count)
    }
    else { $result = [LambekRename]::Find([LambekRenameItem[]] @($items)) }

    # The program as a small readable structure
    $atoms = @()
    $text = ''
    $cost = 0
    if ($null -ne $result.Program) {
        $text = $result.Program.Text
        $cost = $result.Program.Cost
        $atoms = @(foreach ($atom in $result.Program.Atoms) { ConvertTo-LambekRenameAtomView -Atom $atom })
    }
    $renames = for ($i = 0; $i -lt $result.Names.Count; $i++) {
        [pscustomobject]@{ Name = $result.Names[$i]; NewName = $result.Targets[$i]; Index = $i; IsExample = $Example.Contains($result.Names[$i]) }
    }
    $issues = foreach ($issue in $result.Issues) {
        [pscustomobject]@{ Kind = $issue.Kind; Name = $issue.Name; NewName = $issue.Target; Other = $issue.Other }
    }

    # The question: the first name the two cheapest rules name differently
    $question = $null
    $alternative = ''
    $alternativeCost = 0
    if ($null -ne $result.Alternative) {
        $alternative = $result.Alternative.Text
        $alternativeCost = $result.Alternative.Cost
        $question = [pscustomobject]@{ Name = $result.Question; First = $result.QuestionFirst; Second = $result.QuestionSecond }
    }

    [pscustomobject]@{
        PSTypeName      = 'Lambek.RenameRule'
        Found           = $null -ne $result.Program
        Reason          = $result.Reason
        Program         = $text
        Atoms           = $atoms
        Cost            = $cost
        Renames         = @($renames)
        Issues          = @($issues)
        IsSafe          = ($null -ne $result.Program) -and (@($issues).Count -eq 0)
        Ambiguous       = $null -ne $question
        Alternative     = $alternative
        AlternativeCost = $alternativeCost
        Question        = $question
        Rule            = $result.Program
    }
}

function ConvertTo-LambekRenameAtomView {
    param([LambekRenameAtom] $Atom)

    # One piece of the program, with only the fields its kind uses
    $view = [ordered]@{ Kind = $Atom.Kind; Text = $Atom.Key; Cost = $Atom.Cost }
    switch ($Atom.Kind) {
        'Const' { $view['Value'] = $Atom.Text }
        'Substr' {
            $view['From'] = $Atom.From.Key
            $view['To'] = $Atom.To.Key
            $view['Case'] = $Atom.Case
            if ($Atom.Case -eq 'Number') { $view['Width'] = $Atom.Width }
        }
        'Extension' { $view['Case'] = $Atom.Case }
        'Counter' {
            $view['Start'] = $Atom.Start
            $view['Width'] = $Atom.Width
        }
        'Date' { $view['Format'] = $Atom.Format }
    }
    return [pscustomobject] $view
}
