# Depende de: Logger, Connection, Utils

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
            # -accepteula evita que o PsExec fique aguardando o aceite da
            # EULA (processo sem janela = travaria até o timeout).
            # -nobanner remove o cabeçalho de copyright do stderr.
            $PsExecOptions = @($RemoteComputer, "-accepteula", "-nobanner")

            if ($System) {
                $PsExecOptions += "-s"
            }

            if ($Interactive) {
                $PsExecOptions += "-i"
            }

            # Add executable (quoted when the path contains spaces).
            if ($Executable -match '\s' -and -not $Executable.StartsWith('"')) {
                $PsExecOptions += "`"$Executable`""
            }
            else {
                $PsExecOptions += $Executable
            }

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
            $ErrorTask = $Process.StandardError.ReadToEndAsync()

            $Completed = $Process.WaitForExit(
                $TimeoutSeconds * 1000
            )

            $TimedOut = -not $Completed

            if ($TimedOut) {
                try {
                    # Kill(bool) (.NET Core / PS 7) also ends child processes.
                    if ($Process.GetType().GetMethod('Kill', [type[]]@([bool]))) {
                        $Process.Kill($true)
                    }
                    else {
                        $Process.Kill()
                    }

                    $null = $Process.WaitForExit(5000)
                }
                catch {
                    # The process may have already exited.
                }
            }

            # A child process that inherited the pipes can keep them open
            # after PsExec exits; do not let that block past the timeout.
            $null = [System.Threading.Tasks.Task]::WaitAll(
                [System.Threading.Tasks.Task[]]@($OutputTask, $ErrorTask),
                5000
            )

            $Output = if ($OutputTask.IsCompleted) { $OutputTask.Result } else { "" }
            $ErrorOutput = if ($ErrorTask.IsCompleted) { $ErrorTask.Result } else { "" }

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

.PARAMETER System
Runs the remote process under the Local System account (PsExec -s).
By default the process runs with the operator's account.

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
        [int]$TimeoutSeconds = 60,

        [Parameter()]
        [switch]$System
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
                -Arguments $Arguments `
                -System:$System

            $Account = if ($System) { " as SYSTEM" } else { "" }

            Write-Log `
                -Level Info `
                -Message "Executing '$Executable' on $ComputerName$Account."

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

<#
.SYNOPSIS
Copies a local file to a folder on a remote computer.

.DESCRIPTION
Copy-FileToRemote checks that the computer answers a ping (an offline
computer would otherwise hold the SMB copy until its timeout), creates
the destination folder through the administrative share (C$) and
copies the file.

.PARAMETER ComputerName
Specifies the name of the remote computer ("PC-001" or "\\PC-001").

.PARAMETER SourcePath
Specifies the local file to copy.

.PARAMETER DestinationDirectory
Specifies the destination folder as seen on the remote computer
(e.g. C:\script_temp).

.OUTPUTS
System.Management.Automation.PSCustomObject

Returns an object containing:

- Success
- Reachable    ($false when the computer did not answer the ping)
- ComputerName
- SourcePath
- FileName
- UncPath      (\\PC-001\C$\script_temp\file.exe, used from this computer)
- RemotePath   (C:\script_temp\file.exe, used on the remote computer)
- Error

.EXAMPLE
Copy-FileToRemote `
    -ComputerName "PC-001" `
    -SourcePath "\\server\apps\setup.msi" `
    -DestinationDirectory "C:\script_temp"
#>
function Copy-FileToRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationDirectory
    )

    process {
        $FileName = ($SourcePath -split '[\\/]')[-1]
        $Reachable = $null

        try {
            if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
                throw "File not found: $SourcePath"
            }

            Write-Log `
                -Level Info `
                -Message "Copying '$FileName' to $ComputerName"

            $Reachable = Test-ComputerReachable -ComputerName $ComputerName

            if (-not $Reachable) {
                throw "Computer '$ComputerName' is not reachable."
            }

            # Caminhos do Windows montados como texto: Join-Path com C:\ ou
            # \\PC\C$ depende do sistema em que o toolkit está rodando.
            $Destination = $DestinationDirectory.TrimEnd('\')
            $UncDirectory = ConvertTo-AdminSharePath -ComputerName $ComputerName -Path $Destination
            $UncPath = "$UncDirectory\$FileName"

            if (-not (Test-Path -LiteralPath $UncDirectory)) {
                New-Item -ItemType Directory -Path $UncDirectory -Force -ErrorAction Stop | Out-Null

                Write-Log `
                    -Level Info `
                    -Message "Created remote directory: $UncDirectory"
            }

            Copy-Item -LiteralPath $SourcePath -Destination $UncPath -Force -ErrorAction Stop

            Write-Log `
                -Level Info `
                -Message "Copied to $UncPath"

            [PSCustomObject]@{
                Success      = $true
                Reachable    = $true
                ComputerName = $ComputerName
                SourcePath   = $SourcePath
                FileName     = $FileName
                UncPath      = $UncPath
                RemotePath   = "$Destination\$FileName"
                Error        = $null
            }
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error copying '$FileName' to $ComputerName`: $($_.Exception.Message)"

            [PSCustomObject]@{
                Success      = $false
                Reachable    = $Reachable
                ComputerName = $ComputerName
                SourcePath   = $SourcePath
                FileName     = $FileName
                UncPath      = $null
                RemotePath   = $null
                Error        = $_.Exception.Message
            }
        }
    }
}


# Funções não listadas aqui são internas do módulo
Export-ModuleMember -Function @(
    'Invoke-PsExecCommand'
    'Copy-FileToRemote'
)
