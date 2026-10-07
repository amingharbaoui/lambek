function Get-LambekBoundedTypeGuess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Request,

        [Parameter(Mandatory)]
        [pscustomobject] $Grammar,

        # At most this many simple types in a type ("o^r o d^l" is 3 wide)
        [ValidateRange(1, 16)]
        [int] $MaxWidth = 3,

        # At most this many types for one word, the ones it already has included
        [ValidateRange(1, 16)]
        [int] $MaxTypes = 2,

        [switch] $Keeping
    )

    # The types Get-LambekTypeGuess finds (one unknown word, the sentence must reduce to s), kept inside the
    # bounds that make pregroup grammars learnable (Bechet, Foret, Tellier): narrow types, few types per word
    $guess = Get-LambekTypeGuess -Request $Request -Grammar $Grammar -Keeping:$Keeping
    if ($null -eq $guess) { return $null }
    $known = @()
    $lexicon = Get-LambekGrammarLexicon -Language $Request.Language
    if ($lexicon.Words.ContainsKey($guess.Word)) { $known = @($lexicon.Words[$guess.Word]) }
    $types = @(Select-LambekBoundedType -Type $guess.Types -MaxWidth $MaxWidth -MaxTypes $MaxTypes -Known $known)
    if ($types.Count -eq 0) { return $null }

    [pscustomobject]@{
        Word     = $guess.Word
        Token    = $guess.Token
        Language = $guess.Language
        Types    = [string[]] $types
        IsAction = @($types | Where-Object { $_ -match '(^|\s)s(\s|$)' }).Count -gt 0
        MaxWidth = $MaxWidth
        MaxTypes = $MaxTypes
        # The types that solve the sentence but fall outside the bounds
        Rejected = [string[]] @($guess.Types | Where-Object { $types -cnotcontains $_ })
    }
}

function Select-LambekBoundedType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Type,

        [int] $MaxWidth = 3,

        [int] $MaxTypes = 2,

        # The types the word already has: they count in the bound
        [string[]] $Known = @()
    )

    # Width of a type: its number of simple types. Kept: width <= MaxWidth, not already known;
    # the narrowest first (then by text), and no more than MaxTypes - |Known| of them
    $room = $MaxTypes - @($Known).Count
    if ($room -le 0) { return @() }
    $kept = [System.Collections.Generic.List[string]]::new()
    foreach ($one in $Type) {
        $width = @(ConvertFrom-LambekType -Type $one).Count
        if ($width -gt $MaxWidth) { continue }
        if ($Known -ccontains $one -or $kept.Contains($one)) { continue }
        $kept.Add($one)
    }
    $kept.Sort([System.Comparison[string]] {
            param($a, $b)
            $widthA = @(ConvertFrom-LambekType -Type $a).Count
            $widthB = @(ConvertFrom-LambekType -Type $b).Count
            if ($widthA -ne $widthB) { return $widthA.CompareTo($widthB) }
            return [string]::CompareOrdinal($a, $b)
        })
    if ($kept.Count -gt $room) { $kept.RemoveRange($room, $kept.Count - $room) }
    return $kept.ToArray()
}
