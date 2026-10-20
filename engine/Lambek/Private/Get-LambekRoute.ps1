function Get-LambekSmallWord {
    # The small words of a language, as the router reads them: articles, pronouns, question words, negations.
    # They weigh as small words; every other word weighs as a word of its own
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    if ($null -eq $script:SmallWords) { $script:SmallWords = @{} }
    if ($script:SmallWords.ContainsKey($Language)) { return , $script:SmallWords[$Language] }
    $words = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($Language -in (Get-LambekAvailableLanguage)) {
        $lexicon = Get-LambekLexicon -Language $Language
        $lists = @(@($lexicon.StopWords), @($lexicon.Interrogatives), @($lexicon.Negations))
        if ($lexicon.Dialogue) {
            foreach ($name in 'Speakers', 'Addressee', 'Asked', 'Others', 'Articles', 'Determiners') { $lists += , @($lexicon.Dialogue[$name]) }
        }
        foreach ($list in $lists) {
            foreach ($phrase in $list) {
                foreach ($word in ("$phrase" -split '\s+')) { if ($word) { [void] $words.Add([LambekDictionary]::Normalize($word)) } }
            }
        }
    }
    $script:SmallWords[$Language] = $words
    return , $words
}

function Get-LambekRouter {
    # The router, built once from its examples (Data/acts.json): each example is a vector of how it is written and of
    # its words, nothing downloaded and no dictionary needed
    [CmdletBinding()]
    param(
        [string] $Path
    )

    if (-not $Path -and $script:Router) { return $script:Router }
    $file = $Path
    if (-not $file) { $file = Join-Path $PSScriptRoot '../Data/acts.json' }
    $data = Get-Content -LiteralPath $file -Raw -Encoding utf8 | ConvertFrom-Json
    $router = [LambekRouter]::new()
    $router.Passes = [int] $data.Router.Passes
    foreach ($weight in $data.Router.Weights.PSObject.Properties) { $router.Weights[$weight.Name] = [double] $weight.Value }
    foreach ($example in $data.Examples) {
        $router.Add($example.Act, $example.Language, $example.Text, [LambekRouter]::Surface($example.Text, (Get-LambekSmallWord -Language $example.Language)))
    }
    $built = [pscustomobject]@{
        Router     = $router
        Neighbours = [int] $data.Router.Neighbours
        Margin     = [double] $data.Router.Margin
        Acts       = @($data.Acts.PSObject.Properties.Name)
    }
    if (-not $Path) { $script:Router = $built }
    return $built
}

function Get-LambekRoute {
    # What a message is, before any reader reads it: one of the acts of Data/acts.json, or nothing when the router
    # abstains. It only proposes: the readers still decide what the message says, and the act changes nothing they read
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [string] $Language
    )

    if (-not $Language) { $Language = Get-LambekLanguage -Tokens @(Get-LambekLanguageToken -Text $Text) }
    $built = Get-LambekRouter
    $route = $built.Router.Decide([LambekRouter]::Surface($Text, (Get-LambekSmallWord -Language $Language)), $built.Neighbours, $built.Margin)
    $act = $null
    if (-not $route.Abstained) { $act = $route.Act }
    # A path, a file or an extension in the message: what it asks is for the readers of the packs
    $files = @([LambekRouter]::Tokens($Text) | Where-Object { $_ -in 'zpath', 'zfile', 'zext' }).Count -gt 0
    return [pscustomobject]@{
        Act        = $act
        Proposed   = $route.Act
        Second     = $route.Second
        Margin     = $route.Margin
        Similarity = $route.Similarity
        Language   = $Language
        Files      = $files
        Neighbours = @($route.Neighbours)
    }
}

function Get-LambekRouteReply {
    # When the readers understood nothing they can act on, what the act of the message lets Lambek say instead of
    # "I did not understand": that it cannot do that yet (Open), has no hold on it (Elsewhere), thanks for being told how
    # the user feels (Feeling), or reads it only in French and English for now (Foreign). The key of the answer to say,
    # or nothing: the readers keep the last word whenever they read something
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [pscustomobject] $Route,

        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # The router abstained, or files are named: what is asked is for the packs, which ask what they miss
    if (-not $Route -or -not $Route.Act -or $Route.Files) { return $null }
    $steps = @($Plan.Steps)
    if ($steps.Count -eq 0) { return $null }
    # An action chosen (even one still missing a detail), or something told or asked whose meaning was read: the
    # readers said what it is. (A sentence they only took for a question or for "something else", with nothing read
    # in it, is not understood)
    if (@($steps | Where-Object { $_.Status -eq 'Ready' -or ($_.PSObject.Properties['Action'] -and $_.Action) }).Count -gt 0) { return $null }
    $read = @($steps | Where-Object {
            ($_.PSObject.Properties['Statement'] -and $_.Statement) -or ($_.PSObject.Properties['Asked'] -and $_.Asked) -or ($_.PSObject.Properties['ActSay'] -and $_.ActSay)
        })
    if ($read.Count -gt 0) { return $null }
    $language = $steps[0].Language
    # Small talk has its own answers
    if (Get-LambekTalk -Text $Text -Language $language) { return $null }
    $lexicon = Get-LambekLexicon -Language $language
    $key = $null
    if ($Route.Act -in 'Open', 'Elsewhere', 'Feeling') { $key = $Route.Act }
    # A fact, a question, a why, a world imagined or a problem, in a language whose sentences Lambek does not read yet
    elseif ($Route.Act -in 'Tell', 'Ask', 'World', 'Why', 'Imagine', 'Problem' -and -not $lexicon.Dialogue) { $key = 'Foreign' }
    if (-not $key -or -not $lexicon.Answer -or -not $lexicon.Answer[$key]) { return $null }
    return $key
}
