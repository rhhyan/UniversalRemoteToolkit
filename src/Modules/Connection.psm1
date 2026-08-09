<#
.SYNOPSIS
    Locates the PsExec executable used by the Universal Remote Toolkit.

.DESCRIPTION
    Resolves the path to PsExec.exe located in the toolkit's Bin directory.
    The function does not execute PsExec; it only locates the executable.

.OUTPUTS
    System.String
    Returns the full path to PsExec.exe when the executable is found.

    System.Null
    Returns $null when PsExec.exe cannot be found.

.EXAMPLE
    Get-PsExecPath

    Returns the full path to the PsExec executable.
#>
function Get-PsExecPath {
    [CmdletBinding()]
    param()

    process {
        try {
            $ToolkitRoot = Split-Path -Parent $PSScriptRoot
            $ToolkitRoot = Split-Path -Parent $ToolkitRoot

            $PsExecPath = Join-Path $ToolkitRoot "Bin/PsExec.exe"

            if (Test-Path -Path $PsExecPath -PathType Leaf) {
                return $PsExecPath
            }

            return $null
        }
        catch {
            throw "Error locating PsExec: $($_.Exception.Message)"
        }
    }
}


<#
.SYNOPSIS
    Checks whether PsExec is available to the toolkit.

.DESCRIPTION
    Uses Get-PsExecPath to determine whether the PsExec executable
    exists in the expected Bin directory.

    This function does not execute PsExec or establish a remote
    connection.

.OUTPUTS
    System.Boolean
    Returns $true when PsExec is available.
    Returns $false when PsExec cannot be found.

.EXAMPLE
    Test-PsExecInstalled

    Returns True when PsExec is available to the toolkit.
#>
function Test-PsExecInstalled {
    [CmdletBinding()]
    param()

    process {
        $PsExecPath = Get-PsExecPath

        return ($null -ne $PsExecPath)
    }
}


<#
.SYNOPSIS
    Tests whether a remote computer is reachable.

.DESCRIPTION
    Sends a single ICMP request to the specified computer using
    Test-Connection.

    This function only verifies network reachability. A successful
    response does not guarantee that PsExec, SMB, RPC, or other
    remote execution services are available.

.PARAMETER ComputerName
    Specifies the hostname or IP address of the computer to test.

.OUTPUTS
    System.Boolean
    Returns $true when the computer responds to the connectivity test.
    Returns $false when the computer does not respond or an error occurs.

.EXAMPLE
    Test-ComputerReachable -ComputerName "HOSTNAME"

    Tests whether PC-001 responds to an ICMP request.

.EXAMPLE
    Test-ComputerReachable -ComputerName "172.1.1.1"

    Tests whether the specified IP address responds to an ICMP request.
#>
function Test-ComputerReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName
    )

    process {
        try {
            if (
                Test-Connection `
                    -ComputerName $ComputerName `
                    -Count 1 `
                    -Quiet `
                    -ErrorAction Stop
            ) {
                return $true
            }

            return $false
        }
        catch {
            return $false
        }
    }
}


Export-ModuleMember -Function `
    Get-PsExecPath, `
    Test-PsExecInstalled, `
    Test-ComputerReachable