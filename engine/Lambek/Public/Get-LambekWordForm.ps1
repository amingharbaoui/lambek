function Get-LambekWordForm {
    <#
    .SYNOPSIS
        Reads the words of a sentence as Lambek learned to: the lemma, the part of speech and the features of each word,
        without a dictionary written by hand.
    .DESCRIPTION
        The text is cut into words as the treebanks cut them ("du" is "de le"), then each word is read by the forms
        model of its language, learned from annotated treebanks (tools/Build-LambekForms.ps1). Known says whether the
        word was seen when learning: an unknown word is read from its ends and its neighbours. With -Explain, each word
        says why it was read so: what weighed most for its tag, then for its rule of form.
    .EXAMPLE
        Get-LambekWordForm 'Mes amies habitaient Lyon.'
    .EXAMPLE
        Get-LambekWordForm 'Ils zorglubaient.' -Explain | Select-Object Form, Lemma, Upos, Why
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [AllowEmptyString()]
        [string] $Text,

        # en or fr; by default the language of the text
        [string] $Language,

        # Say why each word was read as it was
        [switch] $Explain
    )

    process {
        if (-not $Language) { $Language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) }
        $model = Get-LambekFormModel -Language $Language
        if (-not $model) { throw "No forms model for '$Language': only $((Get-ChildItem -Path (Join-Path $PSScriptRoot '../Data/Forms') -Filter '*.forms.gz' | ForEach-Object { $_.Name.Split('.')[0] }) -join ', ') are learned." }
        $forms = $model.Tokenize($Text)
        $readings = $model.Read($forms)
        for ($i = 0; $i -lt $readings.Length; $i++) {
            $reading = $readings[$i]
            $word = [pscustomobject]@{
                PSTypeName = 'Lambek.WordForm'
                Form       = $reading.Form
                Lemma      = $reading.Lemma
                Upos       = $reading.Upos
                Feats      = $reading.Feats
                Known      = $model.Knows($reading.Form)
            }
            if ($Explain) { $word | Add-Member -NotePropertyName Why -NotePropertyValue @($model.Why($forms, $i, 4)) }
            $word
        }
    }
}
