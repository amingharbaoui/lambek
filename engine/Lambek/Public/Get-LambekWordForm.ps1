function Get-LambekWordForm {
    <#
    .SYNOPSIS
        Reads the words of a sentence as Lambek learned to: the lemma, the part of speech and the features of each word,
        without a dictionary written by hand.
    .DESCRIPTION
        The text is cut into words as the treebanks cut them ("du" is "de le"), then each word is read by the forms
        model of its language, learned from annotated treebanks (tools/Build-LambekForms.ps1). Known says whether the
        word was seen when learning: an unknown word is read from its ends and its neighbours.
    .EXAMPLE
        Get-LambekWordForm 'Mes amies habitaient Lyon.'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [AllowEmptyString()]
        [string] $Text,

        # en or fr; by default the language of the text
        [string] $Language
    )

    process {
        if (-not $Language) { $Language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) }
        $model = Get-LambekFormModel -Language $Language
        if (-not $model) { throw "No forms model for '$Language': only $((Get-ChildItem -Path (Join-Path $PSScriptRoot '../Data/Forms') -Filter '*.forms.gz' | ForEach-Object { $_.Name.Split('.')[0] }) -join ', ') are learned." }
        foreach ($reading in $model.ReadText($Text)) {
            [pscustomobject]@{
                PSTypeName = 'Lambek.WordForm'
                Form       = $reading.Form
                Lemma      = $reading.Lemma
                Upos       = $reading.Upos
                Feats      = $reading.Feats
                Known      = $model.Knows($reading.Form)
            }
        }
    }
}
