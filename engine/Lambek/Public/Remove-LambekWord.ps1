function Remove-LambekWord {
    <#
    .SYNOPSIS
        Makes Lambek forget a word it learned.
    .EXAMPLE
        Remove-LambekWord -Word purge -Language fr
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Word,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z]{2}$')]
        [string] $Language
    )

    Clear-LambekReadCache
    $word = ConvertTo-LambekNormalizedText -Text $Word
    $learned = Get-LambekLearnedWord
    if (-not $learned.ContainsKey($Language) -or -not $learned[$Language].ContainsKey($word)) {
        throw "Lambek did not learn '$Word' in '$Language'."
    }

    if ($PSCmdlet.ShouldProcess("$Language '$word'", 'Forget the word')) {
        $learned[$Language].Remove($word)
        if (-not $script:Incognito) { Save-LambekLearnedWord }
        $script:LexiconCache.Clear()
        $script:ActionIndexCache.Clear()
    }
}
