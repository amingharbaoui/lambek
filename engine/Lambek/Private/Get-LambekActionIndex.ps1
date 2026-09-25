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
                $examples = $action.Examples[$Language]
            }

            foreach ($example in $examples) {
                $request = ConvertTo-LambekRequest -Text $example -Language $Language
                $entries.Add([pscustomobject]@{
                        Pack    = $pack
                        Action  = $action
                        Example = $example
                        Terms   = $request.Terms
                        NGrams  = $request.CharNGrams
                    })
                $documents.Add($request.Terms)
            }
        }
    }

    # One TF-IDF model for all examples
    $index = [pscustomobject]@{
        Entries = $entries.ToArray()
        Model   = ConvertTo-LambekTfIdfModel -Documents $documents.ToArray()
    }

    $script:ActionIndexCache[$Language] = $index
    return $index
}
