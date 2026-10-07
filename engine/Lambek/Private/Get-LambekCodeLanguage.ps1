function Get-LambekCodeLanguage {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    # The six languages a plan can be exported to: how they are called, and the file each program goes in
    return @(
        [pscustomobject]@{ Name = 'PowerShell'; Shown = 'PowerShell'; Fence = 'powershell'; FileName = 'lambek-task.ps1'; Aliases = @('powershell', 'pwsh', 'ps1', 'ps') }
        [pscustomobject]@{ Name = 'Python'; Shown = 'Python'; Fence = 'python'; FileName = 'lambek_task.py'; Aliases = @('python', 'python3', 'py') }
        [pscustomobject]@{ Name = 'JavaScript'; Shown = 'JavaScript'; Fence = 'javascript'; FileName = 'lambek-task.js'; Aliases = @('javascript', 'js', 'node', 'nodejs') }
        [pscustomobject]@{ Name = 'CSharp'; Shown = 'C#'; Fence = 'csharp'; FileName = 'Program.cs'; Aliases = @('csharp', 'c#', 'cs', 'dotnet') }
        [pscustomobject]@{ Name = 'Rust'; Shown = 'Rust'; Fence = 'rust'; FileName = 'main.rs'; Aliases = @('rust', 'rs') }
        [pscustomobject]@{ Name = 'Bash'; Shown = 'Bash'; Fence = 'bash'; FileName = 'lambek-task.sh'; Aliases = @('bash', 'shell', 'sh') }
    )
}

function Resolve-LambekCodeLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    # "js", "Node", "C#" or "c sharp": the language it names, or nothing
    $wanted = $Name.Trim().ToLowerInvariant() -replace '^c[\s-]*sharp$', 'csharp'
    foreach ($language in Get-LambekCodeLanguage) {
        if ($wanted -eq $language.Name.ToLowerInvariant() -or $wanted -in $language.Aliases) {
            return $language
        }
    }
    return $null
}
