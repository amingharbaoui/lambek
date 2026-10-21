function Get-LambekWarmUp {
    [CmdletBinding()]
    param()

    # What the first request would build, in small pieces: each one runs only while no request is waiting.
    # Pieces are data, not script blocks: a closure would lose the functions of the module
    $pieces = [System.Collections.Generic.List[object]]::new()
    $pieces.Add([pscustomobject]@{ Work = 'System'; Language = ''; Text = '' })
    $pieces.Add([pscustomobject]@{ Work = 'Knowledge'; Language = ''; Text = '' })
    $pieces.Add([pscustomobject]@{ Work = 'Memory'; Language = ''; Text = '' })
    # The router of acts learns its vectors once
    $pieces.Add([pscustomobject]@{ Work = 'Router'; Language = ''; Text = '' })
    # The dictionaries load on their own thread; the senses of the actions are read from them once they are in
    foreach ($language in Get-LambekAvailableLanguage) { $pieces.Add([pscustomobject]@{ Work = 'Dictionary'; Language = $language; Text = '' }) }

    foreach ($language in Get-LambekAvailableLanguage) {
        $pieces.Add([pscustomobject]@{ Work = 'Lexicon'; Language = $language; Text = '' })
        $pieces.Add([pscustomobject]@{ Work = 'Forms'; Language = $language; Text = '' })
        $pieces.Add([pscustomobject]@{ Work = 'Index'; Language = $language; Text = '' })
        $pieces.Add([pscustomobject]@{ Work = 'Speech'; Language = $language; Text = '' })

        # The first example of each action read as a request, then answered: the grammar, the checks and the sentences run once
        foreach ($pack in $script:Packs.Values) {
            foreach ($action in $pack.Actions) {
                if (-not $action.Examples.ContainsKey($language)) { continue }
                $pieces.Add([pscustomobject]@{ Work = 'Plan'; Language = $language; Text = @($action.Examples[$language])[0] })
            }
        }
    }
    foreach ($language in Get-LambekAvailableLanguage) { $pieces.Add([pscustomobject]@{ Work = 'Domain'; Language = $language; Text = '' }) }
    return $pieces.ToArray()
}

function Invoke-LambekWarmUpPiece {
    param([pscustomobject] $Piece)

    # Quietly: no progress lines for a request nobody sent, and a piece that fails only means a slower first request
    $handler = $script:ProgressHandler
    $script:ProgressHandler = $null
    try {
        switch ($Piece.Work) {
            'System' { $null = Get-LambekSystemVocabulary; $null = Get-LambekEntityRule }
            'Knowledge' { $null = Get-LambekKnowledge }
            'Memory' { $null = Get-LambekMemoryStore; $null = Get-LambekPursuitStore }
            'Router' { $null = Get-LambekRoute -Text 'bonjour' -Language 'fr' }
            'Forms' { $null = Get-LambekFormModel -Language $Piece.Language }
            'Lexicon' { $null = Get-LambekLexicon -Language $Piece.Language; $null = Get-LambekGrammarLexicon -Language $Piece.Language }
            'Index' { $null = Get-LambekActionIndex -Language $Piece.Language; $null = Get-LambekExampleMemory -Language $Piece.Language }
            'Dictionary' { Get-LambekDictionary -Language $Piece.Language -Background }
            'Speech' { $null = Get-LambekFluency -Language $Piece.Language; $null = Get-LambekSpeechFusion -Language $Piece.Language }
            'Domain' { $null = Get-LambekDomainSense -Language $Piece.Language }
            'Plan' { $null = New-LambekPlan -Text $Piece.Text | ConvertTo-LambekAnswer }
        }
    }
    catch { Write-Verbose "Warm-up: $($_.Exception.Message)" }
    finally { $script:ProgressHandler = $handler }
}
