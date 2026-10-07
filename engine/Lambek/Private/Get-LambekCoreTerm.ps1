function Get-LambekCoreTerm {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Terms,

        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]] $Known
    )

    # A term no example of any action holds says nothing about which action it is (zero mutual information):
    # it would only lower every score alike. "sauf", "images", C:\Temp in a long request stay out of the comparison
    $core = @($Terms | Where-Object { $Known.Contains($_) })
    if ($core.Count -eq 0) { return , [string[]] @($Terms) }
    return , [string[]] $core
}
