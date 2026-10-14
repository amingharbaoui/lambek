function ConvertTo-LambekSpoken {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Language,

        # "tu" when the user says tu, "vous" by default
        [ValidateSet('vous', 'tu')]
        [string] $Register = 'vous'
    )

    # The rules of the language on what Lambek says: contractions, elisions, agreement, plural after a number.
    # Quotes, paths and names are never touched
    if (-not $Text) { return $Text }
    $dictionary = Get-LambekDictionary -Language $Language
    $spoken = [LambekSpeech]::Polish($Text, $Language, $dictionary)
    if ($Language -eq 'fr' -and $Register -eq 'tu' -and $dictionary) { $spoken = [LambekSpeech]::Familiar($spoken, $dictionary) }
    return $spoken
}

function Format-LambekPlural {
    param([string] $Template, [string] $Language, [object[]] $Values)

    # "{0} {0:fichier|fichiers}": the form each number asks for, then the values
    $numbers = [long[]] @($Values | ForEach-Object { if ($_ -is [int] -or $_ -is [long] -or $_ -is [double]) { [long] $_ } else { 2 } })
    return [LambekSpeech]::Plural($Template, $Language, $numbers) -f $Values
}

function Get-LambekRegister {
    param([string] $Text, [string] $Language)

    # The user's own words say tu or vous; nothing said, nothing known
    if ($Language -ne 'fr' -or -not $Text) { return $null }
    # (the "t" of "vole-t-il", "a-t-elle" is said for the sound only: it is nobody)
    $Text = [regex]::Replace($Text, '(?i)-t-(?=(?:il|elle|on|ils|elles)(?![\p{L}]))', '-')
    $words = @((ConvertTo-LambekNormalizedText -Text $Text) -split '[^\p{L}]+' | Where-Object { $_ })
    if (@($words | Where-Object { $_ -in 'tu', 't', 'toi', 'ton', 'ta', 'tes', 'stp' }).Count -gt 0) { return 'tu' }
    if (@($words | Where-Object { $_ -in 'vous', 'votre', 'vos', 'svp' }).Count -gt 0) { return 'vous' }
    return $null
}
