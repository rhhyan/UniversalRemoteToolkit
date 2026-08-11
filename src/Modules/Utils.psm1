# ============================================================
# Universal Remote Toolkit
# Module: Utils
# Description: Utility and helper functions
# ============================================================

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Checks whether the current PowerShell session has administrator privileges.

    .DESCRIPTION
        Determines whether the current process is running with elevated
        administrator privileges.

    .OUTPUTS
        System.Boolean
    #>

    [CmdletBinding()]
    param()

    process {
        try {
            $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()

            $Principal = New-Object Security.Principal.WindowsPrincipal(
                $CurrentIdentity
            )

            return $Principal.IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator
            )
        }
        catch {
            return $false
        }
    }
}


function Pause-Toolkit {
    <#
    .SYNOPSIS
        Pauses the toolkit and waits for user input.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Message = "Pressione Enter para continuar"
    )

    Read-Host $Message | Out-Null
}


function Clear-Toolkit {
    <#
    .SYNOPSIS
        Clears the console screen.
    #>

    [CmdletBinding()]
    param()

    Clear-Host
}


function Format-Date {
    <#
    .SYNOPSIS
        Formats a DateTime value using the toolkit standard format.

    .PARAMETER Date
        DateTime value to format.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$Date
    )

    return $Date.ToString("yyyy-MM-dd HH:mm:ss")
}


function Get-ApplicationRoot {
    <#
    .SYNOPSIS
        Returns the root directory of the Universal Remote Toolkit.
    #>

    [CmdletBinding()]
    param()

    return Split-Path -Parent $PSScriptRoot
}


function Format-Duration {
    <#
    .SYNOPSIS
        Formats the elapsed time of a Stopwatch into a human-readable string.

    .PARAMETER Stopwatch
        Stopwatch containing the elapsed execution time.

    .EXAMPLE
        Format-Duration -Stopwatch $Stopwatch

    .OUTPUTS
        System.String
    #>

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


Export-ModuleMember -Function @(
    'Test-IsAdministrator'
    'Pause-Toolkit'
    'Clear-Toolkit'
    'Format-Date'
    'Get-ApplicationRoot'
    'Format-Duration'
)