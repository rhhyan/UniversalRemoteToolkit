<#
.SYNOPSIS
Builds the argument string used to execute PsExec.

.DESCRIPTION
Build-PsExecArguments prepares the command-line arguments required by
PsExec for remote execution.

The function normalizes the remote computer name, applies optional
PsExec switches, and appends the target executable and its arguments.

This function only builds the argument string. It does not execute
PsExec or establish a remote connection.

.PARAMETER ComputerName
Specifies the name or address of the remote computer.

.PARAMETER Executable
Specifies the executable that will be launched on the remote computer.

.PARAMETER Arguments
Specifies the arguments passed to the target executable.

.PARAMETER System
Runs the remote process under the Local System account.

.PARAMETER Interactive
Allows the remote process to interact with the specified session.

.OUTPUTS
System.String

Returns a formatted PsExec argument string.

.EXAMPLE
Build-PsExecArguments `
    -ComputerName "PC-001" `
    -Executable "cmd.exe" `
    -Arguments "/c hostname"

Builds the arguments required to execute cmd.exe remotely.

.EXAMPLE
Build-PsExecArguments `
    -ComputerName "PC-001" `
    -Executable "installer.exe" `
    -Arguments "/silent" `
    -System

Builds a PsExec command that runs the installer under the Local System account.

.NOTES
This function does not execute the generated command.
It is responsible only for argument construction.
#>
function Build-PsExecArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Executable,

        [Parameter()]
        [string]$Arguments,

        [Parameter()]
        [switch]$System,

        [Parameter()]
        [switch]$Interactive
    )

    process {
        try {
            # Normalize the remote computer name.
            if ($ComputerName.StartsWith("\\")) {
                $RemoteComputer = $ComputerName
            }
            else {
                $RemoteComputer = "\\$ComputerName"
            }

            # Build PsExec switches.
            $PsExecOptions = @($RemoteComputer)

            if ($System) {
                $PsExecOptions += "-s"
            }

            if ($Interactive) {
                $PsExecOptions += "-i"
            }

            # Add executable.
            $PsExecOptions += $Executable

            # Add executable arguments when provided.
            if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
                $PsExecOptions += $Arguments
            }

            return ($PsExecOptions -join " ")
        }
        catch {
            throw "Failed to build PsExec arguments: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Executes PsExec as a native process and captures its result.

.DESCRIPTION
Invoke-PsExecProcess starts the PsExec executable using
System.Diagnostics.Process.

The function redirects standard output and standard error,
waits for the process to complete, enforces a configurable timeout,
and captures the process exit code.

If the timeout is exceeded, the process is terminated and the result
is marked as timed out.

This function does not validate the remote computer and does not
construct PsExec arguments. Those responsibilities belong to other
modules and functions.

.PARAMETER PsExecPath
Specifies the full path to the PsExec executable.

.PARAMETER ArgumentList
Specifies the complete argument string passed to PsExec.

.PARAMETER TimeoutSeconds
Specifies the maximum amount of time, in seconds, that PsExec is
allowed to run.

The default value is 60 seconds.

.OUTPUTS
System.Management.Automation.PSCustomObject

Returns an object containing the execution status, exit code,
timeout state, standard output, and standard error.

.EXAMPLE
Invoke-PsExecProcess `
    -PsExecPath "C:\Tools\PsExec.exe" `
    -ArgumentList "\\PC-001 cmd.exe /c hostname"

Executes PsExec against PC-001.

.EXAMPLE
Invoke-PsExecProcess `
    -PsExecPath "C:\Tools\PsExec.exe" `
    -ArgumentList "\\PC-001 cmd.exe /c hostname" `
    -TimeoutSeconds 30

Executes PsExec with a 30-second timeout.

.NOTES
This function is responsible only for controlling the native
PsExec process lifecycle.

Remote connectivity validation and command construction are
handled separately.
#>
function Invoke-PsExecProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PsExecPath,

        [Parameter(Mandatory)]
        [string]$ArgumentList,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 60
    )

    process {
        $Process = $null

        try {
            if (-not (Test-Path -Path $PsExecPath -PathType Leaf)) {
                throw "PsExec executable not found: $PsExecPath"
            }

            $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()

            $StartInfo.FileName = $PsExecPath
            $StartInfo.Arguments = $ArgumentList
            $StartInfo.UseShellExecute = $false
            $StartInfo.CreateNoWindow = $true
            $StartInfo.RedirectStandardOutput = $true
            $StartInfo.RedirectStandardError = $true

            $Process = [System.Diagnostics.Process]::new()
            $Process.StartInfo = $StartInfo

            $null = $Process.Start()

            $OutputTask = $Process.StandardOutput.ReadToEndAsync()
            $ErrorTask  = $Process.StandardError.ReadToEndAsync()

            $Completed = $Process.WaitForExit(
                $TimeoutSeconds * 1000
            )

            $TimedOut = -not $Completed

            if ($TimedOut) {
                try {
                    $Process.Kill()
                    $Process.WaitForExit()
                }
                catch {
                    # The process may have already exited.
                }
            }

            $Output = $OutputTask.Result
            $ErrorOutput = $ErrorTask.Result

            $ExitCode = if ($TimedOut) {
                $null
            }
            else {
                $Process.ExitCode
            }

            [PSCustomObject]@{
                Success  = (-not $TimedOut -and $ExitCode -eq 0)
                ExitCode = $ExitCode
                TimedOut = $TimedOut
                Output   = $Output.Trim()
                Error    = $ErrorOutput.Trim()
            }
        }
        catch {
            throw "Failed to execute PsExec process: $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $Process) {
                $Process.Dispose()
            }
        }
    }
}

<#
.SYNOPSIS
Executes a command on a remote computer using PsExec.

.DESCRIPTION
Invoke-PsExecCommand orchestrates the remote command execution workflow.

The function validates PsExec availability, verifies remote computer
reachability, resolves the PsExec executable path, builds the required
PsExec arguments, executes the native process, and returns a structured
execution result.

Execution duration and status are recorded through the UTR logging system.

.PARAMETER ComputerName
Specifies the name or address of the remote computer.

.PARAMETER Executable
Specifies the executable to run on the remote computer.

.PARAMETER Arguments
Specifies the arguments passed to the target executable.

.PARAMETER TimeoutSeconds
Specifies the maximum execution time in seconds.

The default value is 60 seconds.

.OUTPUTS
System.Management.Automation.PSCustomObject

Returns a structured object containing:

- Computer
- Command
- Success
- ExitCode
- TimedOut
- Output
- Error
- DurationMS
- Timestamp

.EXAMPLE
Invoke-PsExecCommand `
    -ComputerName "PC-001" `
    -Executable "cmd.exe" `
    -Arguments "/c hostname"

Executes hostname remotely on PC-001.

.EXAMPLE
Invoke-PsExecCommand `
    -ComputerName "PC-001" `
    -Executable "installer.exe" `
    -Arguments "/silent" `
    -TimeoutSeconds 120

Executes an installer remotely with a 120-second timeout.

.NOTES
This function acts as the main orchestration layer of the Execution
module.

It delegates individual responsibilities to the Connection,
Logger, and process execution components.

The function does not directly implement remote connectivity,
argument construction, or native process management.
#>
function Invoke-PsExecCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Executable,

        [Parameter()]
        [string]$Arguments,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 60
    )

    process {
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            Write-Log `
                -Level Info `
                -Message "Starting remote execution on $ComputerName."

            # Validate PsExec.
            if (-not (Test-PsExecInstalled)) {
                throw "PsExec executable was not found."
            }

            # Validate remote computer.
            if (-not (Test-ComputerReachable -ComputerName $ComputerName)) {
                throw "Computer '$ComputerName' is not reachable."
            }

            # Get PsExec path.
            $PsExecPath = Get-PsExecPath

            # Build PsExec arguments.
            $FinalArguments = Build-PsExecArguments `
                -ComputerName $ComputerName `
                -Executable $Executable `
                -Arguments $Arguments

            Write-Log `
                -Level Info `
                -Message "Executing '$Executable' on $ComputerName."

            # Execute PsExec.
            $ProcessResult = Invoke-PsExecProcess `
                -PsExecPath $PsExecPath `
                -ArgumentList $FinalArguments `
                -TimeoutSeconds $TimeoutSeconds

            if ($ProcessResult.Success) {
                Write-Log `
                    -Level Success `
                    -Message "Execution completed successfully on $ComputerName."
            }
            elseif ($ProcessResult.TimedOut) {
                Write-Log `
                    -Level Error `
                    -Message "Execution timed out on $ComputerName."
            }
            else {
                Write-Log `
                    -Level Error `
                    -Message "Execution failed on $ComputerName with exit code $($ProcessResult.ExitCode)."
            }

            [PSCustomObject]@{
                Computer   = $ComputerName
                Command    = $Executable
                Success    = $ProcessResult.Success
                ExitCode   = $ProcessResult.ExitCode
                TimedOut   = $ProcessResult.TimedOut
                Output     = $ProcessResult.Output
                Error      = $ProcessResult.Error
                DurationMS = $Stopwatch.ElapsedMilliseconds
                Timestamp  = Get-Date
            }
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Execution error on $ComputerName`: $($_.Exception.Message)"

            [PSCustomObject]@{
                Computer   = $ComputerName
                Command    = $Executable
                Success    = $false
                ExitCode   = $null
                TimedOut   = $false
                Output     = $null
                Error      = $_.Exception.Message
                DurationMS = $Stopwatch.ElapsedMilliseconds
                Timestamp  = Get-Date
            }
        }
        finally {
            $Stopwatch.Stop()
        }
    }
}