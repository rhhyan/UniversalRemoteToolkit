# ============================================================
# Universal Remote Toolkit
# Module: Software Management
# Description: Universal software installation and uninstallation
# Version: 2.0
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

$Config = Get-ToolkitConfig

$REPOSITORY_PATH = $Config.Software.RepositoryPath
$TEMP_SCRIPT_PATH = $Config.Software.RemoteTempPath
$SUPPORTED_INSTALLERS = $Config.Software.SupportedInstallers

$DEFAULT_INSTALL_TIMEOUT = $Config.Software.DefaultInstallTimeout
$DEFAULT_UNINSTALL_TIMEOUT = $Config.Software.DefaultUninstallTimeout


# ============================================================
# INTERNAL CONSTANTS
# ============================================================

$SUCCESS_EXIT_CODES = @(0, 3010, 1641)
$REBOOT_REQUIRED_EXIT_CODES = @(3010, 1641)


# ============================================================
# GET SOFTWARE REPOSITORY
# ============================================================

<#
.SYNOPSIS
    Lists available software installers in the network repository.

.DESCRIPTION
    Scans the configured software repository recursively and returns
    all supported installers.

    Supported installer types are controlled by the configuration
    value Software.SupportedInstallers.

.PARAMETER Filter
    Optional filter to search by software name.

.EXAMPLE
    Get-SoftwareRepository

    Lists all supported installers in the repository.

.EXAMPLE
    Get-SoftwareRepository -Filter "Chrome"

    Searches recursively for installers containing "Chrome".

.OUTPUTS
    PSCustomObject[]
#>

function Get-SoftwareRepository {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $false)]
        [string]$Filter = ""
    )

    process {

        try {

            Write-Log `
                -Level Info `
                -Message "Scanning software repository: $REPOSITORY_PATH"


            # ------------------------------------------------
            # Validate repository
            # ------------------------------------------------

            if (-not (Test-Path -Path $REPOSITORY_PATH)) {

                throw "Repository not accessible: $REPOSITORY_PATH"
            }


            # ------------------------------------------------
            # Find installers
            # ------------------------------------------------

            $Installers = @()

            foreach ($Extension in $SUPPORTED_INSTALLERS) {

                $NormalizedExtension = $Extension.ToLower()

                if (-not $NormalizedExtension.StartsWith(".")) {
                    $NormalizedExtension = ".$NormalizedExtension"
                }


                $Files = Get-ChildItem `
                    -Path $REPOSITORY_PATH `
                    -File `
                    -Recurse `
                    -ErrorAction Stop |
                    Where-Object {
                        $_.Extension.ToLower() -eq $NormalizedExtension
                    }


                if ($Files) {
                    $Installers += $Files
                }
            }


            # ------------------------------------------------
            # Apply filter
            # ------------------------------------------------

            if (-not [string]::IsNullOrWhiteSpace($Filter)) {

                $Installers = @(
                    $Installers |
                        Where-Object {
                            $_.Name -like "*$Filter*"
                        }
                )
            }


            # ------------------------------------------------
            # Build structured result
            # ------------------------------------------------

            $Results = @(
                $Installers |
                    Sort-Object FullName |
                    ForEach-Object {

                        $InstallerType = switch ($_.Extension.ToLower()) {

                            ".msi" {
                                "MSI"
                                break
                            }

                            ".ps1" {
                                "PowerShell"
                                break
                            }

                            ".exe" {
                                "Executable"
                                break
                            }

                            default {
                                "Unknown"
                                break
                            }
                        }


                        $RelativePath = $_.FullName

                        if ($RelativePath.StartsWith($REPOSITORY_PATH)) {

                            $RelativePath = $RelativePath.Substring(
                                $REPOSITORY_PATH.Length
                            ).TrimStart(
                                '\',
                                '/'
                            )
                        }


                        [PSCustomObject]@{

                            Name = $_.Name

                            FullPath = $_.FullName

                            RelativePath = $RelativePath

                            Extension = $_.Extension

                            InstallerType = $InstallerType

                            Size = $_.Length

                            SizeMB = [math]::Round(
                                $_.Length / 1MB,
                                2
                            )

                            LastModified = $_.LastWriteTime
                        }
                    }
            )


            Write-Log `
                -Level Info `
                -Message "Repository scan completed. Found $($Results.Count) installers."


            return $Results
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Error scanning repository: $($_.Exception.Message)"

            throw
        }
    }
}


# ============================================================
# FIND SOFTWARE INSTALLER
# ============================================================

<#
.SYNOPSIS
    Searches for software installers in the repository.

.DESCRIPTION
    Returns all installers matching the requested software name.

    Unlike the previous implementation, this function does not
    automatically select the first result.

.PARAMETER SoftwareName
    Name of the software to search for.

.EXAMPLE
    Find-SoftwareInstaller -SoftwareName "Chrome"

.OUTPUTS
    PSCustomObject[]
#>

function Find-SoftwareInstaller {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SoftwareName
    )

    process {

        try {

            Write-Log `
                -Level Info `
                -Message "Searching for installer: $SoftwareName"


            $Repository = @(
                Get-SoftwareRepository `
                    -Filter $SoftwareName
            )


            if ($Repository.Count -eq 0) {

                Write-Log `
                    -Level Warning `
                    -Message "No installer found for: $SoftwareName"

                return @()
            }


            Write-Log `
                -Level Info `
                -Message "Found $($Repository.Count) installer candidate(s) for: $SoftwareName"


            return $Repository
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Error finding installer: $($_.Exception.Message)"

            throw
        }
    }
}


# ============================================================
# COPY SOFTWARE TO REMOTE
# ============================================================

<#
.SYNOPSIS
    Copies a software installer to a remote computer.

.DESCRIPTION
    Creates C:\script_temp on the remote computer if necessary
    and copies the selected installer to that directory.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER InstallerPath
    Full path to the installer in the network repository.

.EXAMPLE
    Copy-SoftwareToRemote `
        -ComputerName "PC-001" `
        -InstallerPath "\\fsrctrppw01\aplicativos\Chrome\Chrome.exe"

.OUTPUTS
    PSCustomObject
#>

function Copy-SoftwareToRemote {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InstallerPath
    )

    process {

        try {

            # ------------------------------------------------
            # Validate installer
            # ------------------------------------------------

            if (-not (Test-Path -Path $InstallerPath -PathType Leaf)) {

                throw "Installer file not found: $InstallerPath"
            }


            Write-Log `
                -Level Info `
                -Message "Preparing installer transfer to $ComputerName"


            # ------------------------------------------------
            # Check remote computer
            # ------------------------------------------------

            if (-not (Test-ComputerReachable -ComputerName $ComputerName)) {

                throw "Computer is not reachable: $ComputerName"
            }


            # ------------------------------------------------
            # Build remote path
            # ------------------------------------------------

            $InstallerName = Split-Path `
                -Path $InstallerPath `
                -Leaf

            $RemoteDirectory = "\\$ComputerName\C$\script_temp"

            $RemoteFilePath = Join-Path `
                -Path $RemoteDirectory `
                -ChildPath $InstallerName


            # ------------------------------------------------
            # Create remote directory
            # ------------------------------------------------

            if (-not (Test-Path -Path $RemoteDirectory)) {

                Write-Log `
                    -Level Info `
                    -Message "Creating remote directory: $RemoteDirectory"


                New-Item `
                    -ItemType Directory `
                    -Path $RemoteDirectory `
                    -Force `
                    -ErrorAction Stop |
                    Out-Null
            }


            # ------------------------------------------------
            # Copy installer
            # ------------------------------------------------

            Write-Log `
                -Level Info `
                -Message "Copying $InstallerName to $ComputerName"


            Copy-Item `
                -Path $InstallerPath `
                -Destination $RemoteFilePath `
                -Force `
                -ErrorAction Stop


            # ------------------------------------------------
            # Validate copy
            # ------------------------------------------------

            if (-not (Test-Path -Path $RemoteFilePath -PathType Leaf)) {

                throw "Installer copy could not be verified: $RemoteFilePath"
            }


            Write-Log `
                -Level Info `
                -Message "Installer copied successfully to $RemoteFilePath"


            return [PSCustomObject]@{

                Success = $true

                ComputerName = $ComputerName

                LocalPath = $InstallerPath

                RemotePath = $RemoteFilePath

                LocalPathOnly = "$TEMP_SCRIPT_PATH\$InstallerName"

                FileName = $InstallerName

                Error = $null
            }
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Error copying installer to $ComputerName`: $($_.Exception.Message)"


            return [PSCustomObject]@{

                Success = $false

                ComputerName = $ComputerName

                LocalPath = $InstallerPath

                RemotePath = $null

                LocalPathOnly = $null

                FileName = if ($InstallerPath) {
                    Split-Path -Path $InstallerPath -Leaf
                }
                else {
                    $null
                }

                Error = $_.Exception.Message
            }
        }
    }
}


# ============================================================
# BUILD INSTALL COMMAND
# ============================================================

<#
.SYNOPSIS
    Builds the installation command for an installer.

.DESCRIPTION
    Internal helper used by Install-RemoteSoftware.

    Handles EXE, MSI and PowerShell installers independently.

.PARAMETER InstallerPath
    Path of the installer on the remote computer.

.PARAMETER Arguments
    Optional installer arguments.

.OUTPUTS
    System.String
#>

function New-SoftwareInstallCommand {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InstallerPath,

        [Parameter(Mandatory = $false)]
        [string]$Arguments = ""
    )

    $Extension = [System.IO.Path]::GetExtension(
        $InstallerPath
    ).ToLower()


    switch ($Extension) {

        ".msi" {

            if ([string]::IsNullOrWhiteSpace($Arguments)) {

                return "msiexec.exe /i `"$InstallerPath`" /quiet /norestart"
            }

            return "msiexec.exe /i `"$InstallerPath`" $Arguments"
        }


        ".ps1" {

            if ([string]::IsNullOrWhiteSpace($Arguments)) {

                return "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallerPath`""
            }

            return "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallerPath`" $Arguments"
        }


        ".exe" {

            if ([string]::IsNullOrWhiteSpace($Arguments)) {

                return "`"$InstallerPath`""
            }

            return "`"$InstallerPath`" $Arguments"
        }


        default {

            throw "Unsupported installer type: $Extension"
        }
    }
}


# ============================================================
# INSTALL REMOTE SOFTWARE
# ============================================================

<#
.SYNOPSIS
    Installs software on a remote computer.

.DESCRIPTION
    Executes an installer already present on the remote computer.

    This is the low-level installation function.

    Use Install-Software for the complete workflow.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER InstallerPath
    Path of the installer on the remote computer.

.PARAMETER Arguments
    Optional installer arguments.

.PARAMETER TimeoutSeconds
    Maximum execution time.

.EXAMPLE
    Install-RemoteSoftware `
        -ComputerName "PC-001" `
        -InstallerPath "C:\script_temp\Chrome.exe"

.EXAMPLE
    Install-RemoteSoftware `
        -ComputerName "PC-001" `
        -InstallerPath "C:\script_temp\Chrome.exe" `
        -Arguments "/silent"

.OUTPUTS
    PSCustomObject
#>

function Install-RemoteSoftware {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InstallerPath,

        [Parameter(Mandatory = $false)]
        [string]$Arguments = "",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = $DEFAULT_INSTALL_TIMEOUT
    )

    process {

        try {

            Write-Log `
                -Level Info `
                -Message "Installing software on $ComputerName from $InstallerPath"


            # ------------------------------------------------
            # Build command
            # ------------------------------------------------

            $InstallCommand = New-SoftwareInstallCommand `
                -InstallerPath $InstallerPath `
                -Arguments $Arguments


            Write-Log `
                -Level Info `
                -Message "Installation command prepared for $ComputerName"


            # ------------------------------------------------
            # Execute
            # ------------------------------------------------

            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable "cmd.exe" `
                -Arguments "/c $InstallCommand" `
                -TimeoutSeconds $TimeoutSeconds


            $ExitCode = $Result.ExitCode

            $Success = (
                $Result.Success -or
                $ExitCode -in $SUCCESS_EXIT_CODES
            )

            $RebootRequired = (
                $ExitCode -in $REBOOT_REQUIRED_EXIT_CODES
            )


            if ($Success) {

                Write-Log `
                    -Level Info `
                    -Message "Software installation completed on $ComputerName with exit code $ExitCode"


                return [PSCustomObject]@{

                    Success = $true

                    ComputerName = $ComputerName

                    InstallerPath = $InstallerPath

                    InstallCommand = $InstallCommand

                    ExitCode = $ExitCode

                    RebootRequired = $RebootRequired

                    TimedOut = $Result.TimedOut

                    Output = $Result.Output

                    Error = $Result.Error

                    Duration = $Result.DurationMS

                    Timestamp = Get-Date
                }
            }


            Write-Log `
                -Level Error `
                -Message "Installation failed on $ComputerName with exit code: $ExitCode"


            return [PSCustomObject]@{

                Success = $false

                ComputerName = $ComputerName

                InstallerPath = $InstallerPath

                InstallCommand = $InstallCommand

                ExitCode = $ExitCode

                RebootRequired = $false

                TimedOut = $Result.TimedOut

                Output = $Result.Output

                Error = $Result.Error

                Duration = $Result.DurationMS

                Timestamp = Get-Date
            }
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Error installing software on $ComputerName`: $($_.Exception.Message)"


            return [PSCustomObject]@{

                Success = $false

                ComputerName = $ComputerName

                InstallerPath = $InstallerPath

                InstallCommand = $null

                ExitCode = $null

                RebootRequired = $false

                TimedOut = $false

                Output = $null

                Error = $_.Exception.Message

                Duration = $null

                Timestamp = Get-Date
            }
        }
    }
}


# ============================================================
# INSTALL SOFTWARE WORKFLOW
# ============================================================

<#
.SYNOPSIS
    Executes the complete software installation workflow.

.DESCRIPTION
    Performs:

        1. Computer validation
        2. Repository search
        3. Installer selection detection
        4. File transfer
        5. Remote installation
        6. Consolidated result

    If multiple installers are found, the function does not
    automatically choose one. Instead it returns RequiresSelection
    and the available installer candidates.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER SoftwareName
    Name of the software to install.

.PARAMETER Arguments
    Optional installer arguments.

.PARAMETER TimeoutSeconds
    Maximum installation time.

.EXAMPLE
    Install-Software `
        -ComputerName "PC-001" `
        -SoftwareName "Chrome"

.EXAMPLE
    Install-Software `
        -ComputerName "PC-001" `
        -SoftwareName "FortiClient" `
        -Arguments "/quiet /norestart"

.OUTPUTS
    PSCustomObject
#>

function Install-Software {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SoftwareName,

        [Parameter(Mandatory = $false)]
        [string]$Arguments = "",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = $DEFAULT_INSTALL_TIMEOUT
    )

    process {

        $WorkflowStart = Get-Date

        try {

            Write-Log `
                -Level Info `
                -Message "Starting software installation workflow: $SoftwareName -> $ComputerName"


            # ------------------------------------------------
            # Check computer
            # ------------------------------------------------

            if (-not (Test-ComputerReachable -ComputerName $ComputerName)) {

                throw "Computer is not reachable: $ComputerName"
            }


            # ------------------------------------------------
            # Search installer
            # ------------------------------------------------

            $Installers = @(
                Find-SoftwareInstaller `
                    -SoftwareName $SoftwareName
            )


            if ($Installers.Count -eq 0) {

                return [PSCustomObject]@{

                    Success = $false

                    RequiresSelection = $false

                    ComputerName = $ComputerName

                    SoftwareName = $SoftwareName

                    Installer = $null

                    Installers = @()

                    Error = "No installer found for: $SoftwareName"

                    ExitCode = $null

                    Duration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                    Timestamp = Get-Date
                }
            }


            # ------------------------------------------------
            # Multiple installers
            # ------------------------------------------------

            if ($Installers.Count -gt 1) {

                Write-Log `
                    -Level Warning `
                    -Message "Multiple installers found for $SoftwareName. Selection required."


                return [PSCustomObject]@{

                    Success = $false

                    RequiresSelection = $true

                    ComputerName = $ComputerName

                    SoftwareName = $SoftwareName

                    Installer = $null

                    Installers = $Installers

                    Error = $null

                    ExitCode = $null

                    Duration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                    Timestamp = Get-Date
                }
            }


            # ------------------------------------------------
            # Single installer
            # ------------------------------------------------

            $Installer = $Installers[0]


            # ------------------------------------------------
            # Copy
            # ------------------------------------------------

            $CopyResult = Copy-SoftwareToRemote `
                -ComputerName $ComputerName `
                -InstallerPath $Installer.FullPath


            if (-not $CopyResult.Success) {

                return [PSCustomObject]@{

                    Success = $false

                    RequiresSelection = $false

                    ComputerName = $ComputerName

                    SoftwareName = $SoftwareName

                    Installer = $Installer

                    Installers = $Installers

                    Error = $CopyResult.Error

                    ExitCode = $null

                    Duration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                    Timestamp = Get-Date
                }
            }


            # ------------------------------------------------
            # Install
            # ------------------------------------------------

            $InstallResult = Install-RemoteSoftware `
                -ComputerName $ComputerName `
                -InstallerPath $CopyResult.LocalPathOnly `
                -Arguments $Arguments `
                -TimeoutSeconds $TimeoutSeconds


            # ------------------------------------------------
            # Consolidated result
            # ------------------------------------------------

            return [PSCustomObject]@{

                Success = $InstallResult.Success

                RequiresSelection = $false

                ComputerName = $ComputerName

                SoftwareName = $SoftwareName

                Installer = $Installer

                Installers = $Installers

                LocalPath = $Installer.FullPath

                RemotePath = $CopyResult.RemotePath

                InstallerPath = $CopyResult.LocalPathOnly

                InstallCommand = $InstallResult.InstallCommand

                ExitCode = $InstallResult.ExitCode

                RebootRequired = $InstallResult.RebootRequired

                TimedOut = $InstallResult.TimedOut

                Output = $InstallResult.Output

                Error = $InstallResult.Error

                Duration = $InstallResult.Duration

                WorkflowDuration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                Timestamp = Get-Date
            }
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Software installation workflow failed: $($_.Exception.Message)"


            return [PSCustomObject]@{

                Success = $false

                RequiresSelection = $false

                ComputerName = $ComputerName

                SoftwareName = $SoftwareName

                Installer = $null

                Installers = @()

                Error = $_.Exception.Message

                ExitCode = $null

                Duration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                Timestamp = Get-Date
            }
        }
    }
}


# ============================================================
# GET INSTALLED SOFTWARE
# ============================================================

<#
.SYNOPSIS
    Lists installed software on a remote computer.

.DESCRIPTION
    Queries both 64-bit and 32-bit uninstall registry locations.

    The function returns a structured result containing:
        Success
        ComputerName
        Software
        Count
        Error

    This prevents a failed registry query from being confused
    with a computer that simply has no applications.

.PARAMETER ComputerName
    Name of the remote computer.

.EXAMPLE
    Get-InstalledSoftware -ComputerName "PC-001"

.OUTPUTS
    PSCustomObject
#>

function Get-InstalledSoftware {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName
    )

    process {

        try {

            Write-Log `
                -Level Info `
                -Message "Querying installed software on $ComputerName"


            if (-not (Test-ComputerReachable -ComputerName $ComputerName)) {

                throw "Computer is not reachable: $ComputerName"
            }


            # ------------------------------------------------
            # Remote query script
            # ------------------------------------------------

            $QueryScript = @'
$ErrorActionPreference = "Stop"

$RegPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$InstalledApps = @()

foreach ($RegPath in $RegPaths) {

    if (Test-Path -Path $RegPath) {

        Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue |
            ForEach-Object {

                $DisplayName = $_.GetValue("DisplayName")
                $DisplayVersion = $_.GetValue("DisplayVersion")
                $Publisher = $_.GetValue("Publisher")
                $UninstallString = $_.GetValue("UninstallString")
                $QuietUninstallString = $_.GetValue("QuietUninstallString")

                if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {

                    [PSCustomObject]@{
                        Name                  = $DisplayName
                        Version               = $DisplayVersion
                        Publisher             = $Publisher
                        UninstallString       = $UninstallString
                        QuietUninstallString  = $QuietUninstallString
                        RegistryPath          = $_.PSPath
                    }
                }
            }
    }
}

$InstalledApps |
    Sort-Object Name |
    ConvertTo-Json -Depth 5 -Compress
'@


            # ------------------------------------------------
            # Execute query
            # ------------------------------------------------

            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable "powershell.exe" `
                -Arguments "-NoProfile -ExecutionPolicy Bypass -Command `"$QueryScript`"" `
                -TimeoutSeconds 120


            if (-not $Result.Success) {

                throw "Remote software query failed. ExitCode: $($Result.ExitCode). Error: $($Result.Error)"
            }


            # ------------------------------------------------
            # Empty result
            # ------------------------------------------------

            if ([string]::IsNullOrWhiteSpace($Result.Output)) {

                return [PSCustomObject]@{

                    Success = $true

                    ComputerName = $ComputerName

                    Software = @()

                    Count = 0

                    Error = $null

                    Timestamp = Get-Date
                }
            }


            # ------------------------------------------------
            # Parse JSON
            # ------------------------------------------------

            try {

                $InstalledApps = $Result.Output |
                    ConvertFrom-Json `
                    -ErrorAction Stop
            }

            catch {

                throw "Unable to parse installed software response: $($_.Exception.Message)"
            }


            $InstalledApps = @($InstalledApps)


            Write-Log `
                -Level Info `
                -Message "Found $($InstalledApps.Count) installed applications on $ComputerName"


            return [PSCustomObject]@{

                Success = $true

                ComputerName = $ComputerName

                Software = $InstalledApps

                Count = $InstalledApps.Count

                Error = $null

                Timestamp = Get-Date
            }
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Error retrieving installed software from $ComputerName`: $($_.Exception.Message)"


            return [PSCustomObject]@{

                Success = $false

                ComputerName = $ComputerName

                Software = @()

                Count = 0

                Error = $_.Exception.Message

                Timestamp = Get-Date
            }
        }
    }
}


# ============================================================
# GET SOFTWARE UNINSTALL COMMAND
# ============================================================

<#
.SYNOPSIS
    Retrieves uninstall information for installed software.

.DESCRIPTION
    Searches installed applications on the remote computer.

    All matching applications are returned. The function does not
    silently select the first match.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER SoftwareName
    Software name to search for.

.EXAMPLE
    Get-SoftwareUninstallCommand `
        -ComputerName "PC-001" `
        -SoftwareName "Chrome"

.OUTPUTS
    PSCustomObject
#>

function Get-SoftwareUninstallCommand {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SoftwareName
    )

    process {

        try {

            Write-Log `
                -Level Info `
                -Message "Searching installed software '$SoftwareName' on $ComputerName"


            $InventoryResult = Get-InstalledSoftware `
                -ComputerName $ComputerName


            if (-not $InventoryResult.Success) {

                throw $InventoryResult.Error
            }


            $Matches = @(
                $InventoryResult.Software |
                    Where-Object {
                        $_.Name -like "*$SoftwareName*"
                    }
            )


            if ($Matches.Count -eq 0) {

                Write-Log `
                    -Level Warning `
                    -Message "No installed software matched '$SoftwareName' on $ComputerName"


                return @()
            }


            Write-Log `
                -Level Info `
                -Message "Found $($Matches.Count) installed software match(es) for '$SoftwareName'"


            return $Matches
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Error retrieving uninstall information: $($_.Exception.Message)"

            throw
        }
    }
}


# ============================================================
# BUILD UNINSTALL COMMAND
# ============================================================

<#
.SYNOPSIS
    Normalizes an uninstall command.

.DESCRIPTION
    Handles MSI uninstall commands and ensures silent execution
    where possible.

    MSI commands using /I are converted to /X.

.PARAMETER UninstallCommand
    Original uninstall command.

.OUTPUTS
    System.String
#>

function New-SoftwareUninstallCommand {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UninstallCommand
    )

    $Command = $UninstallCommand.Trim()


    if ($Command -match "(?i)\bmsiexec(?:\.exe)?\b") {

        # Convert MSI install/repair switch to uninstall.
        $Command = $Command -replace "(?i)\s/I(?=\s|\{)", " /X"
        $Command = $Command -replace "(?i)\s/i(?=\s|\{)", " /X"


        # Add quiet execution if not already supplied.
        if ($Command -notmatch "(?i)(/quiet|/qn)") {

            $Command += " /quiet"
        }


        if ($Command -notmatch "(?i)(/norestart)") {

            $Command += " /norestart"
        }
    }


    return $Command
}


# ============================================================
# UNINSTALL REMOTE SOFTWARE
# ============================================================

<#
.SYNOPSIS
    Uninstalls software from a remote computer.

.DESCRIPTION
    Executes the supplied uninstall command using PsExec.

    This is the low-level uninstall function.

    Use Uninstall-Software for the complete workflow.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER UninstallCommand
    Command obtained from the software inventory.

.PARAMETER TimeoutSeconds
    Maximum execution time.

.EXAMPLE
    Uninstall-RemoteSoftware `
        -ComputerName "PC-001" `
        -UninstallCommand "MsiExec.exe /X{GUID}"

.OUTPUTS
    PSCustomObject
#>

function Uninstall-RemoteSoftware {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UninstallCommand,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = $DEFAULT_UNINSTALL_TIMEOUT
    )

    process {

        try {

            Write-Log `
                -Level Info `
                -Message "Uninstalling software on $ComputerName"


            # ------------------------------------------------
            # Normalize command
            # ------------------------------------------------

            $FinalCommand = New-SoftwareUninstallCommand `
                -UninstallCommand $UninstallCommand


            Write-Log `
                -Level Info `
                -Message "Prepared uninstall command for $ComputerName"


            # ------------------------------------------------
            # Execute
            # ------------------------------------------------

            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable "cmd.exe" `
                -Arguments "/c $FinalCommand" `
                -TimeoutSeconds $TimeoutSeconds


            $ExitCode = $Result.ExitCode


            # ------------------------------------------------
            # Success handling
            # ------------------------------------------------

            $Success = (
                $Result.Success -or
                $ExitCode -in $SUCCESS_EXIT_CODES
            )


            $RebootRequired = (
                $ExitCode -in $REBOOT_REQUIRED_EXIT_CODES
            )


            if ($Success) {

                Write-Log `
                    -Level Info `
                    -Message "Software uninstallation completed on $ComputerName with exit code $ExitCode"


                return [PSCustomObject]@{

                    Success = $true

                    ComputerName = $ComputerName

                    UninstallCmd = $FinalCommand

                    ExitCode = $ExitCode

                    RebootRequired = $RebootRequired

                    TimedOut = $Result.TimedOut

                    Output = $Result.Output

                    Error = $Result.Error

                    Duration = $Result.DurationMS

                    Timestamp = Get-Date
                }
            }


            # ------------------------------------------------
            # Failure
            # ------------------------------------------------

            Write-Log `
                -Level Error `
                -Message "Uninstallation failed on $ComputerName with exit code: $ExitCode"


            return [PSCustomObject]@{

                Success = $false

                ComputerName = $ComputerName

                UninstallCmd = $FinalCommand

                ExitCode = $ExitCode

                RebootRequired = $false

                TimedOut = $Result.TimedOut

                Output = $Result.Output

                Error = $Result.Error

                Duration = $Result.DurationMS

                Timestamp = Get-Date
            }
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Error uninstalling software on $ComputerName`: $($_.Exception.Message)"


            return [PSCustomObject]@{

                Success = $false

                ComputerName = $ComputerName

                UninstallCmd = $UninstallCommand

                ExitCode = $null

                RebootRequired = $false

                TimedOut = $false

                Output = $null

                Error = $_.Exception.Message

                Duration = $null

                Timestamp = Get-Date
            }
        }
    }
}


# ============================================================
# UNINSTALL SOFTWARE WORKFLOW
# ============================================================

<#
.SYNOPSIS
    Executes the complete software uninstallation workflow.

.DESCRIPTION
    Performs:

        1. Computer validation
        2. Software inventory
        3. Software search
        4. Selection detection
        5. Uninstall command preparation
        6. Remote execution
        7. Consolidated result

    If multiple matches are found, the workflow returns
    RequiresSelection instead of silently uninstalling the
    first result.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER SoftwareName
    Name of the software to uninstall.

.PARAMETER TimeoutSeconds
    Maximum uninstall time.

.EXAMPLE
    Uninstall-Software `
        -ComputerName "PC-001" `
        -SoftwareName "Google Chrome"

.OUTPUTS
    PSCustomObject
#>

function Uninstall-Software {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SoftwareName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = $DEFAULT_UNINSTALL_TIMEOUT
    )

    process {

        $WorkflowStart = Get-Date

        try {

            Write-Log `
                -Level Info `
                -Message "Starting software uninstallation workflow: $SoftwareName -> $ComputerName"


            # ------------------------------------------------
            # Check computer
            # ------------------------------------------------

            if (-not (Test-ComputerReachable -ComputerName $ComputerName)) {

                throw "Computer is not reachable: $ComputerName"
            }


            # ------------------------------------------------
            # Search installed software
            # ------------------------------------------------

            $Matches = @(
                Get-SoftwareUninstallCommand `
                    -ComputerName $ComputerName `
                    -SoftwareName $SoftwareName
            )


            if ($Matches.Count -eq 0) {

                return [PSCustomObject]@{

                    Success = $false

                    RequiresSelection = $false

                    ComputerName = $ComputerName

                    SoftwareName = $SoftwareName

                    Software = @()

                    UninstallCommand = $null

                    ExitCode = $null

                    Error = "No installed software found matching: $SoftwareName"

                    Duration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                    Timestamp = Get-Date
                }
            }


            # ------------------------------------------------
            # Multiple matches
            # ------------------------------------------------

            if ($Matches.Count -gt 1) {

                Write-Log `
                    -Level Warning `
                    -Message "Multiple installed software matches found for $SoftwareName. Selection required."


                return [PSCustomObject]@{

                    Success = $false

                    RequiresSelection = $true

                    ComputerName = $ComputerName

                    SoftwareName = $SoftwareName

                    Software = $Matches

                    UninstallCommand = $null

                    ExitCode = $null

                    Error = $null

                    Duration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                    Timestamp = Get-Date
                }
            }


            # ------------------------------------------------
            # Single match
            # ------------------------------------------------

            $Software = $Matches[0]


            # ------------------------------------------------
            # Validate uninstall command
            # ------------------------------------------------

            if ([string]::IsNullOrWhiteSpace(
                $Software.UninstallString
            ) -and
                [string]::IsNullOrWhiteSpace(
                    $Software.QuietUninstallString
                )) {

                return [PSCustomObject]@{

                    Success = $false

                    RequiresSelection = $false

                    ComputerName = $ComputerName

                    SoftwareName = $SoftwareName

                    Software = $Software

                    UninstallCommand = $null

                    ExitCode = $null

                    Error = "No uninstall command is registered for $($Software.Name)"

                    Duration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                    Timestamp = Get-Date
                }
            }


            # ------------------------------------------------
            # Prefer QuietUninstallString
            # ------------------------------------------------

            $RawCommand = if (
                -not [string]::IsNullOrWhiteSpace(
                    $Software.QuietUninstallString
                )
            ) {
                $Software.QuietUninstallString
            }
            else {
                $Software.UninstallString
            }


            $FinalCommand = New-SoftwareUninstallCommand `
                -UninstallCommand $RawCommand


            # ------------------------------------------------
            # Execute uninstall
            # ------------------------------------------------

            $UninstallResult = Uninstall-RemoteSoftware `
                -ComputerName $ComputerName `
                -UninstallCommand $FinalCommand `
                -TimeoutSeconds $TimeoutSeconds


            # ------------------------------------------------
            # Consolidated result
            # ------------------------------------------------

            return [PSCustomObject]@{

                Success = $UninstallResult.Success

                RequiresSelection = $false

                ComputerName = $ComputerName

                SoftwareName = $SoftwareName

                Software = $Software

                UninstallCommand = $UninstallResult.UninstallCmd

                ExitCode = $UninstallResult.ExitCode

                RebootRequired = $UninstallResult.RebootRequired

                TimedOut = $UninstallResult.TimedOut

                Output = $UninstallResult.Output

                Error = $UninstallResult.Error

                Duration = $UninstallResult.Duration

                WorkflowDuration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                Timestamp = Get-Date
            }
        }

        catch {

            Write-Log `
                -Level Error `
                -Message "Software uninstallation workflow failed: $($_.Exception.Message)"


            return [PSCustomObject]@{

                Success = $false

                RequiresSelection = $false

                ComputerName = $ComputerName

                SoftwareName = $SoftwareName

                Software = @()

                UninstallCommand = $null

                ExitCode = $null

                Error = $_.Exception.Message

                Duration = ((Get-Date) - $WorkflowStart).TotalMilliseconds

                Timestamp = Get-Date
            }
        }
    }
}


# ============================================================
# EXPORT MODULE MEMBERS
# ============================================================

Export-ModuleMember -Function @(
    'Get-SoftwareRepository'
    'Find-SoftwareInstaller'
    'Copy-SoftwareToRemote'

    'Install-RemoteSoftware'
    'Install-Software'

    'Get-InstalledSoftware'
    'Get-SoftwareUninstallCommand'

    'Uninstall-RemoteSoftware'
    'Uninstall-Software'
)