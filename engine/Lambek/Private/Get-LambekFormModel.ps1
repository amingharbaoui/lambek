function Get-LambekFormModel {
    # The learned forms model of a language (Data/Forms/<language>.forms.gz, with the words of <language>.learned.gz), loaded once; nothing when there is none
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    if ($null -eq $script:FormModels) { $script:FormModels = @{} }
    if ($script:FormModels.ContainsKey($Language)) { return $script:FormModels[$Language] }
    $path = Join-Path $PSScriptRoot "../Data/Forms/$Language.forms.gz"
    $model = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $model = [LambekForms]::Load([IO.Path]::GetFullPath($path))
        # What Lambek learned on its own from plain text (tools/Learn-LambekWords.ps1), when it was written down
        $learned = Join-Path $PSScriptRoot "../Data/Forms/$Language.learned.gz"
        if (Test-Path -LiteralPath $learned -PathType Leaf) { $model.AddLearned([LambekSelfReader]::Load([IO.Path]::GetFullPath($learned))) }
        # The words of the language as a dictionary says them (tools/Learn-LambekLexicon.ps1), when there is one
        $lexicon = Join-Path $PSScriptRoot "../Data/Forms/$Language.lexicon.gz"
        if (Test-Path -LiteralPath $lexicon -PathType Leaf) { $model.Lexicon = [LambekLexicon]::Load([IO.Path]::GetFullPath($lexicon)) }
    }
    $script:FormModels[$Language] = $model
    return $model
}

function Get-LambekWrittenWord {
    # How often the treebanks of a language wrote each word, bare, and the words its lexicon holds, bare (what a word
    # says of the language a message is in), loaded once without the tagger; nothing when there is no forms model
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    if ($null -eq $script:WrittenWords) { $script:WrittenWords = @{} }
    if ($script:WrittenWords.ContainsKey($Language)) { return $script:WrittenWords[$Language] }
    $path = Join-Path $PSScriptRoot "../Data/Forms/$Language.forms.gz"
    $known = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $bare = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $lexicon = Join-Path $PSScriptRoot "../Data/Forms/$Language.lexicon.gz"
        if (Test-Path -LiteralPath $lexicon -PathType Leaf) {
            foreach ($form in [LambekLexicon]::Load([IO.Path]::GetFullPath($lexicon)).Forms.Keys) { [void] $bare.Add([LambekForms]::Bare($form)) }
        }
        $known = [pscustomobject]@{ Counts = [LambekFormCounts]::Load([IO.Path]::GetFullPath($path)); Lexicon = $bare }
    }
    $script:WrittenWords[$Language] = $known
    return $known
}
