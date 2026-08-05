Test-IsAdministrator

Pause-Toolkit

Clear-Toolkit

Format-Date

Get-ApplicationRoot

//function
Get-

Set-

Start-

Stop-

Test-

Invoke-

Show-

Write-

Read-

function Format-Duration {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Stopwatch]$Stopwatch

    )

    if ($Stopwatch.Elapsed.TotalSeconds -lt 1) {
        return "$($Stopwatch.ElapsedMilliseconds) ms"

    }


    if ($Stopwatch.Elapsed.TotalMinutes -lt 1) {
        return ("{0:N2} s" -f $Stopwatch.Elapsed.TotalSeconds)
    }

    return ("{0:mm}m {0:ss}s" -f $Stopwatch.Elapsed)
}
