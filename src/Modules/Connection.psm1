<#
.SYNOPSIS
    Locates the PsExec executable used by the Universal Remote Toolkit.

.DESCRIPTION
    Resolves the path to PsExec.exe using Paths.PsExec from Settings.json.
    Falls back to the toolkit's Bin directory when the setting is missing.
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
            $PsExecPath = $null

            try {
                $Config = Get-ToolkitConfig

                if ($Config.Paths.PsExec) {
                    $PsExecPath = Resolve-ToolkitPath -Path $Config.Paths.PsExec
                }
            }
            catch {
                Write-Verbose "Could not read Paths.PsExec from configuration. Using default."
            }

            if (-not $PsExecPath) {
                $PsExecPath = Join-Path (Get-ToolkitRoot) "Bin/PsExec.exe"
            }

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
    Sends a single ICMP request to the specified computer, waiting at
    most Network.PingTimeout milliseconds (Settings.json, default 1000).

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
        [string]$ComputerName,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 0
    )

    process {
        # Aceita "\\PC-001" e "PC-001"
        $HostName = $ComputerName.TrimStart('\')

        if ($TimeoutMilliseconds -eq 0) {
            $TimeoutMilliseconds = 1000

            try {
                $Config = Get-ToolkitConfig

                if ($Config.Network.PingTimeout) {
                    $TimeoutMilliseconds = [int]$Config.Network.PingTimeout
                }
            }
            catch {
                Write-Verbose "Could not read Network.PingTimeout. Using $TimeoutMilliseconds ms."
            }
        }

        # System.Net.NetworkInformation.Ping permite timeout tanto no
        # Windows PowerShell 5.1 quanto no PowerShell 7.
        $Ping = [System.Net.NetworkInformation.Ping]::new()

        try {
            $Reply = $Ping.Send($HostName, $TimeoutMilliseconds)

            return ($Reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
        }
        catch {
            return $false
        }
        finally {
            $Ping.Dispose()
        }
    }
}


Export-ModuleMember -Function `
    Get-PsExecPath, `
    Test-PsExecInstalled, `
    Test-ComputerReachable