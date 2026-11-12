function Get-LambekCoreTerm {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Terms,

        # (empty when no pack of actions is loaded: then no term says anything about which action it is)
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $Known
    )

    # A term no example of any action holds says nothing about which action it is (zero mutual information):
    # it would only lower every score alike. "sauf", "images", C:\Temp in a long request stay out of the comparison
    $core = @($Terms | Where-Object { $Known.Contains($_) })
    if ($core.Count -eq 0) { return , [string[]] @($Terms) }
    return , [string[]] $core
}
