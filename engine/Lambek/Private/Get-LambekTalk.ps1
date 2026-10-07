function Get-LambekTalk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Language,

        # What Lambek can help with, and one example request
        [string] $Topics = '',

        [string] $Example = '',

        # Pick among the phrasings (only when the answer is said, once per message)
        [switch] $Vary
    )

    $lexicon = Get-LambekLexicon -Language $Language
    if ($lexicon.Talk.Count -eq 0) { return $null }

    # Plain words, without accents or punctuation
    $normalized = (ConvertTo-LambekNormalizedText -Text $Text) -replace '[^\p{L}\p{N}\s]', ' '
    $words = @($normalized -split '\s+' | Where-Object { $_ })
    if ($words.Count -eq 0) { return $null }

    # Phrases found in the message; the first kind in the file wins
    $covered = [bool[]]::new($words.Count)
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $lexicon.Talk.Keys) {
        foreach ($phrase in $lexicon.Talk[$name].Phrases) {
            for ($start = 0; $start -le $words.Count - $phrase.Count; $start++) {
                $same = $true
                for ($i = 0; $i -lt $phrase.Count; $i++) {
                    if (-not (Test-LambekTalkWord -Word $words[$start + $i] -Expected $phrase[$i])) { $same = $false; break }
                }
                if (-not $same) { continue }
                for ($i = 0; $i -lt $phrase.Count; $i++) { $covered[$start + $i] = $true }
                if (-not $found.Contains($name)) { $found.Add($name) }
            }
        }
    }
    if ($found.Count -eq 0) { return $null }

    # Small talk only: at most one other meaningful word
    $other = 0
    for ($i = 0; $i -lt $words.Count; $i++) {
        if ($covered[$i] -or $words[$i] -eq 'lambek' -or $lexicon.StopWords.Contains($words[$i])) { continue }
        $other++
    }
    if ($other -gt 1) { return $null }

    # Some answers depend on the chat: incognito or saved
    $talk = $lexicon.Talk[$found[0]]
    if ($talk.ReplyOff -and -not $script:Incognito) { return $talk.ReplyOff }
    $reply = @($talk.Reply)[0]
    if ($Vary) { $reply = Select-LambekVariant -Key "$Language|talk|$($found[0])" -Variants @($talk.Reply) }
    return $reply -f $Topics, $Example
}

function Select-LambekVariant {
    param([string] $Key, [string[]] $Variants)

    # Variety without chance: the first phrasing the first time, then a stable hash picks one not said in the last two turns
    if ($Variants.Count -le 1) { return $Variants[0] }
    if (-not $script:SpeechRecent.ContainsKey($Key)) { $script:SpeechRecent[$Key] = [System.Collections.Generic.List[int]]::new() }
    $recent = $script:SpeechRecent[$Key]
    $index = 0
    if ($recent.Count -gt 0) { $index = [LambekSpeech]::Pick("$Key|$($script:SpeechTurn)", $Variants.Count, [int[]] @($recent | Select-Object -Last 2)) }
    $recent.Add($index)
    if ($recent.Count -gt 8) { $recent.RemoveAt(0) }
    $script:SpeechTurn++
    return $Variants[$index]
}

function Test-LambekTalkWord {
    param(
        [string] $Word,
        [string] $Expected
    )

    # Same word, or one typo in a long word: "fracais" for "francais"
    if ($Word -eq $Expected) { return $true }
    if ($Expected.Length -lt 5 -or [math]::Abs($Word.Length - $Expected.Length) -gt 1) { return $false }
    return (Measure-LambekEditDistance -Source $Word -Target $Expected).Distance -le 1
}
