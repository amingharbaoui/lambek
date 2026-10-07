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

        # The reading the grammar explains best
        Repair-LambekRequest -Text $Text.Normalize([System.Text.NormalizationForm]::FormC) -Original $Text -Language $Language
    }
}
