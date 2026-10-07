function Get-LambekActionIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Language
    )

    # Cache
    if ($script:ActionIndexCache.ContainsKey($Language)) {
        return $script:ActionIndexCache[$Language]
    }

    # Example phrases of every action
    $entries = [System.Collections.Generic.List[object]]::new()
    $documents = [System.Collections.Generic.List[object]]::new()

    foreach ($pack in $script:Packs.Values) {
        foreach ($action in $pack.Actions) {
            $examples = @()
            if ($action.Examples.ContainsKey($Language)) {
                $examples = @($action.Examples[$Language])
            }
            # The verbs of an action are one class: each example also stands with every other verb of the action
            # ("remettre les fichiers vers un dossier" is a move as much as "deplacer les fichiers vers un dossier")
            $verbs = @()
            if ($pack.Words.ContainsKey($Language)) { $verbs = @($action.Verbs | Where-Object { $pack.Words[$Language].ContainsKey($_) }) }

            foreach ($example in $examples) {
                # Examples are written right: read them as they are, without the repair a request goes through
                $request = Read-LambekRequest -Text (Repair-LambekPhrase -Text $example) -Original $example -Language $Language
                $forms = [System.Collections.Generic.List[object]]::new()
                $forms.Add([pscustomobject]@{ Terms = $request.Terms; NGrams = $request.CharNGrams })
                $said = @($request.Terms | Where-Object { $_ -in $verbs }) | Select-Object -First 1
                if ($said) {
                    foreach ($verb in $verbs) {
                        if ($verb -eq $said) { continue }
                        $terms = [string[]] @($request.Terms | ForEach-Object { if ($_ -eq $said) { $verb } else { $_ } })
                        $forms.Add([pscustomobject]@{ Terms = $terms; NGrams = @(Get-LambekCharNGram -Terms $terms) })
                    }
                }

                foreach ($form in $forms) {
                    $entries.Add([pscustomobject]@{
                            Pack    = $pack
                            Action  = $action
                            Example = $example
                            Terms   = $form.Terms
                            NGrams  = $form.NGrams
                        })
                    $documents.Add($form.Terms)
                }
            }
        }
    }

    # Every term an example holds
    $known = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($terms in $documents) { $known.UnionWith([string[]] @($terms)) }

    # One TF-IDF model for all examples
    $index = [pscustomobject]@{
        Entries   = $entries.ToArray()
        Known     = $known
        Model     = ConvertTo-LambekTfIdfModel -Documents $documents.ToArray()
    }

    $script:ActionIndexCache[$Language] = $index
    return $index
}
