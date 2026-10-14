function Find-LambekCategoryQuestion {
    [CmdletBinding()]
    param(
        # What was asked and cannot be concluded
        [Parameter(Mandatory)]
        [pscustomobject] $Ask,

        # What was told, each with its reading, and the same as clauses (see Category.cs)
        [Parameter(Mandatory)]
        [object[]] $Premises,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [LambekCategoryStatement[]] $Statements,

        [Parameter(Mandatory)]
        [hashtable] $Atoms,

        [Parameter(Mandatory)]
        [string] $Language
    )

    # The question that would settle what cannot be concluded: every question Lambek could ask about what it was told
    # ("Tom est-il un chat ?", "tous les mammiferes sont-ils des animaux ?") is tried both ways, its answer yes added to
    # what was told, then its answer no, and the question kept is the one after which the most answers are known: both
    # when one does, else one. A question whose answer already follows is never asked, nor the question itself.
    # Nothing when no question would help
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $forms = Get-LambekCategoryForm -Items (@($Premises | ForEach-Object { $_.Item }) + @($Ask)) -Language $Language
    $individual = ''
    if ($Ask.Individual) { $individual = $Ask.Individual.Key }
    $asked = ($Ask.Predicate.Atoms -join '+')
    $outcome = {
        param([LambekCategoryStatement] $extra)
        $with = [LambekCategoryStatement[]] (@($Statements) + @($extra))
        if ([LambekCategories]::Follows($with, (Get-LambekCategoryOpposite -Item $Ask -Atoms $Atoms -Individual $individual))) { return 'yes' }
        if ([LambekCategories]::Follows($with, (Get-LambekCategoryOpposite -Item $Ask -Atoms $Atoms -Individual $individual -No))) { return 'no' }
        return 'unknown'
    }
    $best = $null
    $bestScore = 0
    foreach ($candidate in @(Get-LambekCategoryCandidate -Ask $Ask -Forms $forms -Language $Language)) {
        # (the question itself, or a part of it, settles nothing new)
        if ((($candidate.Yes.Predicate.Atoms) -join '+') -eq $asked -and ($candidate.Kind -eq 'one' -or ($candidate.Yes.Subject.Atoms -join '+') -eq ($Ask.Subject.Atoms -join '+'))) { continue }
        $yes = ConvertTo-LambekCategoryStatement -Item $candidate.Yes -Atoms $Atoms
        $no = ConvertTo-LambekCategoryStatement -Item $candidate.No -Atoms $Atoms
        # (a question whose answer follows already, either way, is not asked)
        if (-not [LambekCategories]::Satisfiable([LambekCategoryStatement[]] (@($Statements) + @($yes)))) { continue }
        if (-not [LambekCategories]::Satisfiable([LambekCategoryStatement[]] (@($Statements) + @($no)))) { continue }
        # (nor a question about every one of a kind that a yes could only make true by there being none of them)
        if ($candidate.Kind -eq 'all') {
            $some = [pscustomobject]@{ Kind = 'some'; Subject = $candidate.Yes.Subject; Predicate = $candidate.Yes.Subject; Individual = $null }
            if (-not [LambekCategories]::Satisfiable([LambekCategoryStatement[]] (@($Statements) + @($yes) + @(ConvertTo-LambekCategoryStatement -Item $some -Atoms $Atoms)))) { continue }
        }
        $ifYes = & $outcome $yes
        $ifNo = & $outcome $no
        $score = @($ifYes, $ifNo | Where-Object { $_ -ne 'unknown' }).Count
        if ($score -gt $bestScore) {
            $best = [pscustomobject]@{ Candidate = $candidate; IfYes = $ifYes; IfNo = $ifNo }
            $bestScore = $score
            if ($score -eq 2) { break }
        }
    }
    if (-not $best) { return $null }

    # The question, and what each answer would give, said to the user; what each answer is, kept as it would be told
    $pairs = @{ askis = @('is', 'isnot'); askdoes = @('is', 'isnot'); askall = @('all', 'notall'); asksome = @('some', $null); asksomenot = @('somenot', 'notsomenot'); askno = @('no', $null) }
    $consequence = {
        param([string] $result)
        if ($result -eq 'unknown') { return $null }
        $shape = $pairs[$Ask.Kind][$(if ($result -eq 'yes') { 0 } else { 1 })]
        if (-not $shape) { return $data['NoneThereInline'] }
        return Get-LambekCategorySentence -Item $Ask -Shape $shape -Language $Language
    }
    $candidate = $best.Candidate
    $question = Get-LambekCategorySentence -Item $candidate.Yes -Shape $candidate.Shape -Language $Language -Shapes 'Asks'
    if (-not $question) { return $null }
    $plainQuestion = Get-LambekCategorySentence -Item $candidate.Yes -Shape $candidate.Shape -Language $Language -Shapes 'Asks' -Plain
    if ($plainQuestion -cmatch '^\p{Ll}') { $question = $question.Substring(0, 1).ToLowerInvariant() + $question.Substring(1) }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(($data['Decide'] -f $question))
    $said = & $consequence $best.IfYes
    if ($said) { $lines.Add(($data['IfYes'] -f $said)) }
    $said = & $consequence $best.IfNo
    if ($said) { $lines.Add(($data['IfNo'] -f $said)) }
    $yesShape = $(if ($candidate.Kind -eq 'one') { 'is' } else { 'all' })
    $noShape = $(if ($candidate.Kind -eq 'one') { 'isnot' } else { 'notall' })
    return [pscustomobject]@{
        Lines = $lines.ToArray()
        Yes   = Get-LambekCategorySentence -Item $candidate.Yes -Shape $yesShape -Language $Language -Plain
        No    = Get-LambekCategorySentence -Item $candidate.Yes -Shape $noShape -Language $Language -Plain
    }
}

function Get-LambekCategoryForm {
    param([object[]] $Items, [string] $Language)

    # Every kind of thing and everything said of them in the sentences told and asked, with the words the user wrote
    # for it: in the plural as a kind ("chats"), after "sont" ("des mammiferes"), after "est" ("un chat"), as a verb
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $forms = [ordered]@{}
    $entry = {
        param($term)
        $key = ($term.Atoms -join '+')
        if (-not $forms.Contains($key)) {
            $forms[$key] = [pscustomobject]@{ Atoms = @($term.Atoms); Verb = $false; SubjectPlural = ''; Quantifier = ''; SubjectSingular = ''; PredicatePlural = ''; PredicateSingular = ''; VerbPlural = ''; VerbSingular = ''; Object = '' }
        }
        $forms[$key]
    }
    foreach ($item in $Items) {
        if (-not $item) { continue }
        $plural = $item.Quantifier -in @($data['Plural']) -or (-not $item.Quantifier -and $item.Kind -in 'some', 'asksome')
        if ($item.Subject) {
            $form = & $entry $item.Subject
            if ($plural -and -not $form.SubjectPlural) { $form.SubjectPlural = $item.Written.Subject; $form.Quantifier = $item.Quantifier }
            elseif (-not $plural -and -not $form.SubjectSingular) { $form.SubjectSingular = $item.Written.Subject }
        }
        $form = & $entry $item.Predicate
        if ($item.Verb) {
            $form.Verb = $true
            if ($item.Written.Object) { $form.Object = $item.Written.Object }
            $speaker = $item.Individual -and $item.Individual.Key -eq 'speaker'
            if ($plural -and -not $form.VerbPlural) { $form.VerbPlural = $item.Written.Predicate }
            elseif (-not $plural -and -not $speaker -and -not $form.VerbSingular -and $item.Kind -notin 'askdoes') { $form.VerbSingular = $item.Written.Predicate }
        }
        elseif ($item.Member) { if (-not $form.SubjectPlural) { $form.SubjectPlural = $item.Written.Predicate } }
        elseif ($plural) { if (-not $form.PredicatePlural) { $form.PredicatePlural = $item.Written.Predicate } }
        elseif (-not $form.PredicateSingular) { $form.PredicateSingular = $item.Written.Predicate }
    }
    # What was not written is made from what was, when the dictionary can: "des mammiferes" is said of the kind
    # "mammiferes", and "un mammifere" of one; "chats" gives "des chats" and "un chat"; "volent" gives "vole"
    foreach ($form in $forms.Values) {
        if ($form.Verb) {
            $lemma = ($form.Atoms[0] -replace '^v:', '') -replace '>.*$', ''
            if (-not $form.VerbSingular) { $form.VerbSingular = Get-LambekCategoryVerbForm -Lemma $lemma -Language $Language -Person 'one' }
            if (-not $form.VerbPlural) { $form.VerbPlural = Get-LambekCategoryVerbForm -Lemma $lemma -Language $Language -Person 'many' }
            continue
        }
        $articles = @($data['PluralArticles'])
        if (-not $form.SubjectPlural -and $form.PredicatePlural -and $articles.Count -gt 0) {
            $tokens = @($form.PredicatePlural -split "[\s'\u2019]+" | Where-Object { $_ })
            if ($tokens.Count -gt 1 -and (ConvertTo-LambekNormalizedText -Text $tokens[0]) -in $articles) { $form.SubjectPlural = ($form.PredicatePlural -replace "^\S+?(?:\s+|['\u2019])", '') }
        }
        # (where nothing comes before a noun after "are", the dictionary says whether it names a kind: "mammals", not "black")
        if (-not $form.SubjectPlural -and $form.PredicatePlural -and $articles.Count -eq 0) {
            $one = ConvertTo-LambekCategorySingular -Text $form.PredicatePlural -Language $Language
            if ($one -and @($data['Indefinite'].Values | Where-Object { $one.StartsWith("$_ ") }).Count -gt 0) { $form.SubjectPlural = $form.PredicatePlural }
        }
        if (-not $form.PredicatePlural -and $form.SubjectPlural) {
            $form.PredicatePlural = $form.SubjectPlural
            if ($articles.Count -gt 0) { $form.PredicatePlural = "$($articles[0]) $($form.SubjectPlural)" }
        }
        if (-not $form.PredicateSingular) {
            # (said as a kind it is a noun; said after "sont" it is one only after an article, or when no adjective is spelled so)
            $sources = @(@($form.SubjectSingular, $true), @($form.SubjectPlural, $true), @($form.PredicatePlural, $null))
            foreach ($source in $sources) {
                if (-not $source[0]) { continue }
                $one = ConvertTo-LambekCategorySingular -Text $source[0] -Language $Language -Noun $source[1]
                if ($one) { $form.PredicateSingular = $one; break }
            }
        }
    }
    return $forms
}

function Get-LambekCategoryVerbForm {
    param([string] $Lemma, [string] $Language, [string] $Person)

    # The form of a verb for one, for the user, or for many ("vole", "vole", "volent"); the verb itself where the
    # language says the form is its base ("does it fly")
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $tag = "$($data['VerbForms'][$Person])"
    if (-not $tag) { return $Lemma }
    $dictionary = Get-LambekDictionary -Language $Language
    if (-not $dictionary) { return '' }
    $found = @($dictionary.Forms($Lemma, $Language, 'v', $tag))
    if ($found.Count -gt 0) { return "$($found[0])" }
    return ''
}

function ConvertTo-LambekCategorySingular {
    param(
        [string] $Text,
        [string] $Language,
        # Whether the words name a kind ("chats"), or say what something is like ("noirs"); not said, the article and
        # the dictionary tell
        [object] $Noun = $null
    )

    # One of a kind said in the plural: "chats noirs de ma soeur" is "un chat noir de ma soeur", "mammals" is
    # "a mammal", "noirs" is "noir". The noun gives its gender, the adjectives agree with it; nothing when the
    # dictionary does not know a word
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $dictionary = Get-LambekDictionary -Language $Language
    if (-not $dictionary) { return $null }
    $words = @($Text.Trim() -split ' ' | Where-Object { $_ })
    $articles = @($data['PluralArticles']) + @($data['Articles'])
    if ($words.Count -gt 1 -and (ConvertTo-LambekNormalizedText -Text $words[0]) -in $articles) { $words = @($words | Select-Object -Skip 1); $Noun = $true }
    $of = -1
    for ($i = 1; $i -lt $words.Count; $i++) { if ((ConvertTo-LambekNormalizedText -Text $words[$i]) -in @($data['Of'])) { $of = $i; break } }
    $head = @($words)
    $rest = ''
    if ($of -gt 0) { $head = @($words[0..($of - 1)]); $rest = ' ' + (@($words | Select-Object -Skip $of) -join ' ') }
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($word in $head) { $entries.Add(@($dictionary.Lemmas((ConvertTo-LambekNormalizedText -Text $word), $Language))) }
    # The noun, and its gender: the first word where the language puts the noun first (where it has genders), else the last
    $nounAt = -1
    $gender = 'm'
    $gendered = $data['Indefinite']['f'] -ne $data['Indefinite']['m']
    $place = $(if ($gendered) { 0 } else { $head.Count - 1 })
    $isNoun = @($entries[$place] | Where-Object { $_.Pos -eq 'n' }).Count -gt 0
    $isAdjective = @($entries[$place] | Where-Object { $_.Pos -eq 'a' }).Count -gt 0
    if ($null -eq $Noun) { $Noun = $isNoun -and -not $isAdjective }
    if ($Noun) {
        if (-not $isNoun) { return $null }
        $nounAt = $place
        $found = @($entries[$place] | Where-Object { $_.Pos -eq 'n' -and "$($_.Tag)" -match '^[mf]' } | Select-Object -First 1)
        if ($found.Count -gt 0) { $gender = "$($found[0].Tag)".Substring(0, 1) }
    }
    $indefinite = $data['Indefinite']
    $said = @(for ($i = 0; $i -lt $head.Count; $i++) {
            $pos = $(if ($i -eq $nounAt) { 'n' } else { 'a' })
            $lemma = @($entries[$i] | Where-Object { $_.Pos -eq $pos } | Select-Object -First 1)
            if ($lemma.Count -eq 0) { return $null }
            $form = $null
            if ($data['VerbForms']['one']) {
                # (a word that does not change with the number has its form for the gender alone: "souris")
                foreach ($tag in "$($gender)s", $gender) {
                    $forms = @($dictionary.Forms("$($lemma[0].Lemma)", $Language, $pos, $tag))
                    if ($forms.Count -gt 0) { $form = "$($forms[0])"; break }
                }
            }
            else { $form = "$($lemma[0].Lemma)" }
            if (-not $form) { return $null }
            $form
        })
    $phrase = ($said -join ' ') + $rest
    if ($nounAt -lt 0) { return $phrase }
    $article = "$($indefinite[$gender])"
    if ($indefinite.Contains('vowel') -and $phrase -match '^[aeiouAEIOU]') { $article = "$($indefinite['vowel'])" }
    return "$article $phrase"
}

function Get-LambekCategoryCandidate {
    param([pscustomobject] $Ask, [System.Collections.IDictionary] $Forms, [string] $Language)

    # The questions Lambek could ask, each as what its answer yes and its answer no would tell:
    # about the one asked about ("est-ce que Tom est un chat ?"), or about every one of a kind
    # ("est-ce que tous les mammiferes sont des animaux ?")
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    if ($Ask.Kind -in 'askis', 'askdoes') {
        $who = $Ask.Individual
        foreach ($form in $Forms.Values) {
            if (@($form.Atoms | Where-Object { -not "$_".StartsWith('of:') }).Count -eq 0) { continue }
            $written = [pscustomobject]@{ Subject = $who.Written; Predicate = ''; Object = '' }
            $member = $false
            if ($form.Verb) {
                $verb = $form.VerbSingular
                if ($who.Key -eq 'speaker') { $verb = Get-LambekCategoryVerbForm -Lemma (($form.Atoms[0] -replace '^v:', '') -replace '>.*$', '') -Language $Language -Person 'speaker' }
                if (-not $verb) { continue }
                $written.Predicate = $verb
                $written.Object = $form.Object
            }
            elseif ($form.PredicateSingular) { $written.Predicate = $form.PredicateSingular }
            elseif ($form.SubjectPlural) { $written.Predicate = $form.SubjectPlural; $member = $true }
            else { continue }
            $make = { param($kind) [pscustomobject]@{ Kind = $kind; Quantifier = ''; Subject = $null; Individual = $who; Predicate = [pscustomobject]@{ Atoms = @($form.Atoms) }; Verb = $form.Verb; Member = $member; Written = $written } }
            [pscustomobject]@{ Kind = 'one'; Shape = 'is'; Yes = (& $make 'is'); No = (& $make 'isnot') }
        }
        return
    }
    if ($Ask.Kind -notin 'askall', 'asksome', 'asksomenot', 'askno') { return }
    foreach ($kind in $Forms.Values) {
        if ($kind.Verb -or -not $kind.SubjectPlural) { continue }
        $quantifier = $(if ($kind.Quantifier -and $data['AllOf'].Contains($kind.Quantifier)) { "$($data['AllOf'][$kind.Quantifier])" } else { '' })
        if (-not $quantifier) {
            $one = ConvertTo-LambekCategorySingular -Text $kind.SubjectPlural -Language $Language
            $gender = $(if ($one -and $data['Indefinite']['f'] -ne $data['Indefinite']['m'] -and $one.StartsWith("$($data['Indefinite']['f']) ")) { 'f' } else { 'm' })
            $quantifier = "$($data['AllByGender'][$gender])"
        }
        foreach ($said in $Forms.Values) {
            if ($said -eq $kind) { continue }
            if (@($said.Atoms | Where-Object { -not "$_".StartsWith('of:') }).Count -eq 0) { continue }
            $predicate = $(if ($said.Verb) { $said.VerbPlural } else { $said.PredicatePlural })
            if (-not $predicate) { continue }
            $written = [pscustomobject]@{ Subject = $kind.SubjectPlural; Predicate = $predicate; Object = $(if ($said.Verb) { $said.Object } else { '' }) }
            $make = { param($k) [pscustomobject]@{ Kind = $k; Quantifier = $quantifier; Subject = [pscustomobject]@{ Atoms = @($kind.Atoms) }; Individual = $null; Predicate = [pscustomobject]@{ Atoms = @($said.Atoms) }; Verb = $said.Verb; Member = $false; Written = $written } }
            [pscustomobject]@{ Kind = 'all'; Shape = 'all'; Yes = (& $make 'all'); No = (& $make 'somenot') }
        }
    }
}

function Get-LambekCategoryPending {
    # The question Lambek asked in this conversation and waits the answer of (each chat has its own)
    if ($null -eq $script:CategoryPending) { return $null }
    $here = Get-LambekTold
    if ($script:CategoryPending.ContainsKey($here)) { return $script:CategoryPending[$here] }
    return $null
}

function Set-LambekCategoryPending {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Keeps a value in memory only.')]
    param([pscustomobject] $Pending)

    if ($null -eq $script:CategoryPending) { $script:CategoryPending = [System.Collections.Generic.Dictionary[object, object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance) }
    $here = Get-LambekTold
    if ($Pending) { $script:CategoryPending[$here] = $Pending } else { [void] $script:CategoryPending.Remove($here) }
}

function Test-LambekCategoryAnswer {
    param([string] $Text, [string] $Language)

    # "oui", "non, pas du tout": the answer to the question asked, yes or no; nothing for anything else
    $data = (Get-LambekCategoryVocabulary -Language $Language).Data
    $plain = ((ConvertTo-LambekNormalizedText -Text $Text) -replace '[^\p{L}\s]+', ' ' -replace '\s+', ' ').Trim()
    foreach ($pair in @(@('yes', $data['YesWords']), @('no', $data['NoWords']))) {
        foreach ($phrase in @($pair[1]) | Sort-Object { -"$_".Length }) {
            $words = ((ConvertTo-LambekNormalizedText -Text "$phrase") -replace '[^\p{L}\s]+', ' ' -replace '\s+', ' ').Trim()
            if ($plain -eq $words) { return $pair[0] }
        }
    }
    return $null
}
