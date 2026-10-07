function Get-LambekDomainSense {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Dictionary[string, string[]]])]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    # Cache
    if ($script:DomainSenseCache.ContainsKey($Language)) { return $script:DomainSenseCache[$Language] }

    $domain = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::Ordinal)
    $dictionary = $null
    foreach ($tongue in Get-LambekAvailableLanguage) { $dictionary = Get-LambekDictionary -Language $tongue }
    if (-not $dictionary) {
        $script:DomainSenseCache[$Language] = $domain
        return $domain
    }

    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            # The senses the action means: shared by two of its own verbs, in any language
            $verbs = [System.Collections.Generic.List[string]]::new()
            $tongues = [System.Collections.Generic.List[string]]::new()
            foreach ($tongue in Get-LambekAvailableLanguage) {
                foreach ($verb in $action.Verbs) {
                    if ($pack.Words.ContainsKey($tongue) -and $pack.Words[$tongue].ContainsKey($verb)) { $verbs.Add($verb); $tongues.Add($tongue) }
                }
            }
            $core = $dictionary.Core([string[]] $verbs, [string[]] $tongues, 'v')

            # Its words in this language, and the words the pack reads as them ("erase": delete), keep only those senses
            $words = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($verb in $action.Verbs) {
                if ($pack.Words.ContainsKey($Language) -and $pack.Words[$Language].ContainsKey($verb)) { [void] $words.Add($verb) }
            }
            if ($pack.BaseForms.ContainsKey($Language)) {
                foreach ($key in $pack.BaseForms[$Language].Keys) {
                    if ($pack.BaseForms[$Language][$key] -in $words) { [void] $words.Add($key) }
                }
            }
            foreach ($word in $words) {
                $senses = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
                if ($domain.ContainsKey($word)) { $senses.UnionWith($domain[$word]) }
                foreach ($lemma in @($word) + @($dictionary.Lemmas($word, $Language) | Where-Object Pos -EQ 'v' | ForEach-Object Lemma)) {
                    $senses.UnionWith([string[]] $dictionary.Within($lemma, $Language, 'v', $core))
                }
                $domain[$word] = [string[]] @($senses)
            }
        }
    }
    $script:DomainSenseCache[$Language] = $domain
    return $domain
}
