function Send-LambekProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Stage,

        [int] $Step = 0,

        # Share of the work already done, from 0 to 100
        [ValidateRange(0, 100)]
        [int] $Percent = 0,

        # The pregroup types of the step, once they are known
        [string] $Types = ''
    )

    # The host sets a handler that streams the stage to the app; otherwise nothing happens
    if ($script:ProgressHandler) {
        & $script:ProgressHandler $Stage $Step $Percent $Types
    }
}
