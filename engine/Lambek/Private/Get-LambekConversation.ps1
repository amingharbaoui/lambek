function Get-LambekPlanReferent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    # The files each step is about, weighted as in Lappin and Leass (1994): recency 100, direct object 50,
    # head noun 80, not in an adverbial 50. A step before the last one is one turn older: its weight is halved
    $steps = @($Plan.Steps | Where-Object { $_.Action -and $_.Parameters -and ($_.Parameters.Contains('Path') -or $_.Parameters.Contains('Source')) })
    $weight = 100 + 50 + 80 + 50
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $parameters = [ordered]@{}
        foreach ($key in $steps[$i].Parameters.Keys) {
            if ($key -notin 'Destination', 'NewName', 'Parent') { $parameters[$key] = $steps[$i].Parameters[$key] }
        }
        # One file ("le fichier rapport.pdf", "the newest one") or several
        $number = 'plural'
        if ($parameters.Contains('Name') -or ($parameters.Contains('Count') -and [int] $parameters['Count'] -eq 1)) { $number = 'singular' }
        [pscustomobject]@{
            Number     = $number
            Parameters = $parameters
            Salience   = $weight / [math]::Pow(2, $steps.Count - 1 - $i)
            Step       = $steps[$i].Step
        }
    }
}

function Add-LambekConversation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        [pscustomobject] $Previous
    )

    # What was said before loses half its weight at each turn; what this plan is about comes in at full weight
    $older = @()
    if ($Previous) {
        $before = @(Get-LambekConversationReferent -Plan $Previous)
        $older = @($before | ForEach-Object {
                [pscustomobject]@{ Number = $_.Number; Parameters = $_.Parameters; Salience = $_.Salience / 2; Step = 0 }
            })
    }
    $all = @(@(Get-LambekPlanReferent -Plan $Plan) + $older | Sort-Object @{ Expression = 'Salience'; Descending = $true } | Select-Object -First 10)
    $Plan | Add-Member -NotePropertyName Conversation -NotePropertyValue $all -Force
    return $Plan
}

function Get-LambekConversationReferent {
    param([pscustomobject] $Plan)

    # The referents the plan carries from the conversation, or those of the plan alone
    if ($Plan.PSObject.Properties['Conversation'] -and $Plan.Conversation) { return @($Plan.Conversation) }
    return @(Get-LambekPlanReferent -Plan $Plan)
}

function Select-LambekReferent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        [string[]] $Tokens = @(),

        [Parameter(Mandatory)]
        [string] $Language
    )

    # The most salient referent that agrees in number with the pronoun ("them" wants several files, "it" one)
    $candidates = @(Get-LambekConversationReferent -Plan $Plan)
    if ($candidates.Count -eq 0) { return $null }
    $singular = @((Get-LambekLexicon -Language $Language).FollowUp['Singular'])
    $number = 'plural'
    if (@($Tokens | Where-Object { $_ -in $singular }).Count -gt 0) { $number = 'singular' }
    $agreeing = @($candidates | Where-Object Number -EQ $number)
    if ($agreeing.Count -eq 0) { $agreeing = $candidates }
    return @($agreeing | Sort-Object @{ Expression = 'Salience'; Descending = $true } | Select-Object -First 1)[0]
}
