function Get-LambekSentenceReading {
    # What the words of a sentence may be, for the readers of sentences: read by the learned forms model, in this very
    # sentence ($script:WordSource 'forms', the default), or listed by the dictionaries out of context ('dictionary',
    # kept to measure one against the other, and for the languages without a forms model). While the dictionaries are
    # still there, they are asked only the lemma of a verb never seen that the model could not find ("dors"). What a
    # message read is kept until the next message, as the readers ask about the same sentence several times
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Language
    )

    if ($script:WordSource -ne 'dictionary') {
        $key = "words`n$Language`n$Text"
        $words = $null
        if ($script:ReadCache.TryGetValue($key, [ref] $words)) { return $words }
        $model = Get-LambekFormModel -Language $Language
        if ($model) {
            # (the dictionaries, while they are there; the words learned would only say again what the model read)
            $dictionary = Get-LambekDictionary -Language $Language
            if ($dictionary -isnot [LambekDictionary]) { $dictionary = $null }
            $words = [LambekSentenceWords]::Read($model, $Text, $dictionary, $Language)
            $script:ReadCache[$key] = $words
            return $words
        }
    }
    return Get-LambekDictionary -Language $Language
}
