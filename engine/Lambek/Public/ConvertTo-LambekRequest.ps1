function ConvertTo-LambekRequest {
    <#
    .SYNOPSIS
        Converts a plain-language request into a structured Lambek request.
    .EXAMPLE
        ConvertTo-LambekRequest 'Delete the files older than 30 days in C:\Temp'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateLength(1, 2000)]
        [string] $Text,

        [ValidatePattern('^(auto|[a-z]{2})$')]
        [string] $Language = 'auto'
    )

    process {
        if ($Language -ne 'auto' -and $Language -notin (Get-LambekAvailableLanguage)) {
            throw "Language '$Language' is not available."
        }

        # The reading the grammar explains best (read once per message: the readers ask for the same sentence again)
        $key = "request`n$Language`n$Text"
        $kept = Get-LambekReadCopy -Key $key
        if ($kept) { return $kept }
        $request = Repair-LambekRequest -Text $Text.Normalize([System.Text.NormalizationForm]::FormC) -Original $Text -Language $Language
        $script:ReadCache[$key] = $request
        $request.PSObject.Copy()
    }
}
