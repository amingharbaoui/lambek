function Confirm-LambekProof {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Reply,

        [string] $Language = 'en'
    )

    # Before an answer is said, its proof is worked out again by the checker that shares no code with the engine
    # (Checker/Test-LambekProof.ps1): what it refuses is not said. Lambek says it cannot prove it, and keeps no proof
    # for "pourquoi ?". What the checker does not know how to check ("some", a fact in a shape it does not read) is
    # said as before
    $proof = Get-LambekLastProof
    if (-not $proof -or -not $Reply) { return $Reply }
    $refused = $false
    if ($proof.Calculation -and (Test-LambekCalculation -Text $proof.Calculation) -eq $false) { $refused = $true }
    $conclusions = @($proof.Conclusion | Where-Object { $_ })
    if (-not $refused -and $conclusions.Count -gt 0) {
        $facts = @($proof.Facts)
        $premises = @($facts | ForEach-Object { Get-LambekFactCore -Fact $_ })
        # (the facts as the reasoning read them, when it read them in another shape than the one they are held in)
        if (@($proof.Forms).Count -gt 0) { $premises = @(if (@($proof.Forms).Count -eq $facts.Count) { @($proof.Forms) } else { '' }) }
        # (what is only imagined counts as a premise of this answer, never as a thing told)
        if ($proof.PSObject.Properties['Assumed']) { $premises = @($premises) + @($proof.Assumed | Where-Object { $_ }) }
        if ($premises.Count -gt 0 -and @($premises | Where-Object { -not $_ }).Count -eq 0) {
            $refused = (Test-LambekProof -Premises ([string[]] $premises) -Conclusions ([string[]] $conclusions)).Holds -eq $false
        }
    }
    if (-not $refused) { return $Reply }

    Write-Verbose "The checker refused the proof of: $Reply ($(@($proof.Facts | ForEach-Object { if ($_.PSObject.Properties['Core']) { $_.Core } }) -join ' ; ') / $(@($proof.Forms) -join ' ; ') => $($conclusions -join ' ; ') $($proof.Calculation))"
    Set-LambekLastProof
    $unproved = (Get-LambekLexicon -Language $Language).Dialogue.Say['Unproved']
    if (-not $unproved) { $unproved = (Get-LambekLexicon -Language 'en').Dialogue.Say['Unproved'] }
    return $unproved
}
