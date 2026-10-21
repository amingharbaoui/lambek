function Get-LambekSentenceReading {
    # What the words of a sentence may be, for the readers of sentences: read by the learned forms model, in this very
    # sentence ($script:WordSource 'forms', the default), or listed by the dictionaries out of context ('dictionary',
    # kept to measure one against the other, and for the languages without a forms model). While the dictionaries are
    # still there, they are asked only the lemma of a verb never seen that the model could not find ("dors"). The last
    # sentence read is kept, as the readers ask about the same sentence several times
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Language
    )

    if ($script:WordSource -ne 'dictionary') {
        $key = "$Language|$Text"
        if ($script:SentenceWords -and $script:SentenceWords.Key -ceq $key) { return $script:SentenceWords.Words }
        $model = Get-LambekFormModel -Language $Language
        if ($model) {
            $words = [LambekSentenceWords]::Read($model, $Text, (Get-LambekDictionary -Language $Language), $Language)
            $script:SentenceWords = [pscustomobject]@{ Key = $key; Words = $words }
            return $words
        }
    }
    return Get-LambekDictionary -Language $Language
}
