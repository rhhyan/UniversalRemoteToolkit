# ============================================================
# Universal Remote Toolkit
# Module: Utils
# Description: Utility and helper functions
# Depende de: (nenhum)
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


function ConvertTo-AdminSharePath {
    <#
    .SYNOPSIS
        Converts a local path on a remote computer to its administrative share (UNC) path.

    .DESCRIPTION
        C:\script_temp on PC-001 becomes \\PC-001\C$\script_temp.
        Accepts the computer name with or without the leading "\\".

    .PARAMETER ComputerName
        Name of the remote computer.

    .PARAMETER Path
        Absolute local path on the remote computer (e.g. C:\script_temp).

    .EXAMPLE
        ConvertTo-AdminSharePath -ComputerName "PC-001" -Path "C:\script_temp"

    .OUTPUTS
        System.String
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $HostName = $ComputerName.Trim().TrimStart('\')

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        throw "Invalid computer name: '$ComputerName'"
    }

    # Só caminho absoluto com letra de unidade (C:\pasta); UNC e relativo não têm C$
    if ($Path -notmatch '^([A-Za-z]):(?:\\(.*))?$') {
        throw "Path must be an absolute local path such as C:\folder: '$Path'"
    }

    $Drive = $Matches[1].ToUpper()
    $Rest = ([string]$Matches[2]).Trim('\')

    $UncPath = "\\$HostName\$Drive`$"

    if ($Rest) {
        $UncPath += "\$Rest"
    }

    return $UncPath
}


Export-ModuleMember -Function @(
    'Test-IsAdministrator'
    'Format-Date'
    'ConvertTo-AdminSharePath'
)