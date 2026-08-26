# ============================================================
# Universal Remote Toolkit
# Main Application Entry Point
# ============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'

# ============================================================
# APPLICATION PATH
# ============================================================

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "[*] UTR Root: $ProjectRoot`n" -ForegroundColor Cyan

# ============================================================
# LOAD MODULES
# ============================================================

$ModulePath = Join-Path $PSScriptRoot "Modules"

if (-not (Test-Path -Path $ModulePath)) {
    Write-Host "[!] Modules directory not found: $ModulePath" -ForegroundColor Red
    exit 1
}

$ModulesToLoad = @(
    'Config.psm1'
    'Logger.psm1'
    'Connection.psm1'
    'Execution.psm1'
    'ConsoleUI.psm1'
    'Utils.psm1'
    'Software.psm1'
)

foreach ($Module in $ModulesToLoad) {

    $ModuleFile = Join-Path -Path $ModulePath -ChildPath $Module

    if (-not (Test-Path -Path $ModuleFile)) {
        Write-Host "[!] Module not found: $ModuleFile" -ForegroundColor Red
        exit 1
    }

    try {
        Import-Module `
            -Name $ModuleFile `
            -Force `
            -ErrorAction Stop

        Write-Host "[✓] $Module loaded" -ForegroundColor Green
    }
    catch {
        Write-Host `
            "[✗] Failed to load $Module : $($_.Exception.Message)" `
            -ForegroundColor Red

        exit 1
    }
}

Write-Host ""

# ============================================================
# INITIALIZE LOGGING
# ============================================================

try {

    Start-Log

    Write-Log `
        -Level Info `
        -Message "=== Universal Remote Toolkit started ==="

}
catch {

    Write-Host `
        "[!] Failed to initialize logging: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}

# ============================================================
# LOAD CONFIGURATION
# ============================================================

try {

    $Config = Get-ToolkitConfig

    Write-Log `
        -Level Info `
        -Message "Configuration loaded successfully"

}
catch {

    Write-Log `
        -Level Error `
        -Message "Failed to load configuration: $($_.Exception.Message)"

    Show-ExecutionResult `
        -Status Error `
        -Message "Failed to load configuration" `
        -Details $_.Exception.Message `
        -Pause $true

    Stop-Log

    exit 1
}

# ============================================================
# MENU DEFINITIONS
# ============================================================

$MainMenu = [ordered]@{
    1 = "Remote Execution"
    2 = "Software Management"
    3 = "Settings"
    0 = "Exit"
}

$ExecutionMenu = [ordered]@{
    1 = "Execute command"
    2 = "Execute script"
    3 = "Execution history"
    0 = "Back to main menu"
}

$SoftwareMenu = [ordered]@{
    1 = "Install software"
    2 = "Uninstall software"
    3 = "List installed software"
    0 = "Back to main menu"
}

$SettingsMenu = [ordered]@{
    1 = "Connections"
    2 = "Preferences"
    3 = "About"
    0 = "Back to main menu"
}

# ============================================================
# EXECUTION MENU
# ============================================================

function Invoke-ExecutionMenu {

    [CmdletBinding()]
    param()

    while ($true) {

        Clear-Host

        Show-Banner `
            -Title "Universal Remote Toolkit" `
            -Subtitle "Remote Execution"

        Show-MainMenu `
            -MenuItems $ExecutionMenu `
            -Description "Select an execution option:"

        $Choice = Read-MenuSelection `
            -ValidOptions @(0, 1, 2, 3)

        Write-Log `
            -Level Info `
            -Message "ExecutionMenu: option $Choice selected"

        switch ($Choice) {

            # ------------------------------------------------
            # Execute command
            # ------------------------------------------------

            1 {

                Write-Host ""
                Write-Host "[>] Computer name: " `
                    -ForegroundColor Yellow `
                    -NoNewline

                $Computer = Read-Host

                if ([string]::IsNullOrWhiteSpace($Computer)) {

                    Write-Log `
                        -Level Info `
                        -Message "Command execution cancelled by user"

                    continue
                }

                Write-Host "[>] Executable: " `
                    -ForegroundColor Yellow `
                    -NoNewline

                $Executable = Read-Host

                if ([string]::IsNullOrWhiteSpace($Executable)) {

                    Write-Log `
                        -Level Warning `
                        -Message "Executable was empty"

                    Show-ExecutionResult `
                        -Status Warning `
                        -Message "Executable cannot be empty"

                    continue
                }

                Write-Host "[>] Arguments (optional): " `
                    -ForegroundColor Yellow `
                    -NoNewline

                $Arguments = Read-Host

                try {

                    Write-Log `
                        -Level Info `
                        -Message "Starting remote execution on $Computer"

                    $Result = Invoke-PsExecCommand `
                        -ComputerName $Computer `
                        -Executable $Executable `
                        -Arguments $Arguments `
                        -TimeoutSeconds 60

                    if ($Result.Success) {

                        Write-Log `
                            -Level Info `
                            -Message "Execution completed successfully on $Computer"

                        Show-ExecutionResult `
                            -Status Success `
                            -Message "Command executed successfully" `
                            -Details @"
                            Computer : $($Result.Computer)
                            Command  : $($Result.Command)
                            ExitCode : $($Result.ExitCode)
                            Duration : $($Result.DurationMS) ms

                            Output:
                            $($Result.Output)
                            "@
                    }
                    else {

                        Write-Log `
                            -Level Error `
                            -Message "Execution failed on $Computer"

                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Command execution failed" `
                            -Details @"
Computer : $($Result.Computer)
ExitCode : $($Result.ExitCode)

Error:
$($Result.Error)
"@
                    }
                }
                catch {

                    Write-Log `
                        -Level Error `
                        -Message "Unexpected error during execution on $Computer : $($_.Exception.Message)"

                    Show-ExecutionResult `
                        -Status Error `
                        -Message "Unexpected execution error" `
                        -Details $_.Exception.Message
                }
            }

            # ------------------------------------------------
            # Execute script
            # ------------------------------------------------

            2 {

                Write-Log `
                    -Level Info `
                    -Message "ExecutionMenu: Execute script selected"

                Show-ExecutionResult `
                    -Status Info `
                    -Message "Script execution is under development."
            }

            # ------------------------------------------------
            # Execution history
            # ------------------------------------------------

            3 {

                Write-Log `
                    -Level Info `
                    -Message "ExecutionMenu: History selected"

                Show-ExecutionResult `
                    -Status Info `
                    -Message "Execution history is under development."
            }

            # ------------------------------------------------
            # Back
            # ------------------------------------------------

            0 {

                Write-Log `
                    -Level Info `
                    -Message "ExecutionMenu: returning to main menu"

                return
            }
        }
    }
}

# ============================================================
# SOFTWARE MENU
# ============================================================

function Invoke-SoftwareMenu {

    [CmdletBinding()]
    param()

    while ($true) {

        Clear-Host

        Show-Banner `
            -Title "Universal Remote Toolkit" `
            -Subtitle "Software Management"

        Show-MainMenu `
            -MenuItems $SoftwareMenu `
            -Description "Select a software management option:"

        $Choice = Read-MenuSelection `
            -ValidOptions @(0, 1, 2, 3)

        Write-Log `
            -Level Info `
            -Message "SoftwareMenu: option $Choice selected"

        switch ($Choice) {

            1 {
                # ------------------------------------------------
                # Install software
                # ------------------------------------------------

                Write-Host ""
                Write-Host "[>] Computer name: " `
                    -ForegroundColor Yellow `
                    -NoNewline

                $Computer = Read-Host

                if ([string]::IsNullOrWhiteSpace($Computer)) {
                    Write-Log `
                        -Level Info `
                        -Message "Software installation cancelled by user"
                    continue
                }

                Write-Host "[>] Software name (to search): " `
                    -ForegroundColor Yellow `
                    -NoNewline

                $SoftwareName = Read-Host

                if ([string]::IsNullOrWhiteSpace($SoftwareName)) {
                    Write-Log `
                        -Level Warning `
                        -Message "Software name was empty"

                    Show-ExecutionResult `
                        -Status Warning `
                        -Message "Software name cannot be empty"

                    continue
                }

                try {
                    Write-Log `
                        -Level Info `
                        -Message "Starting software installation workflow"

                    # Step 1: Search for installer
                    Write-Host "`n[*] Searching for installer..." -ForegroundColor Cyan
                    $Installer = Find-SoftwareInstaller -SoftwareName $SoftwareName

                    if (-not $Installer) {
                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Installer not found" `
                            -Details "No matching installer found in repository for: $SoftwareName"
                        continue
                    }

                    Write-Host "[✓] Installer found: $($Installer.Name)" -ForegroundColor Green

                    # Step 2: Copy to remote
                    Write-Host "`n[*] Copying installer to remote computer..." -ForegroundColor Cyan
                    $CopyResult = Copy-SoftwareToRemote `
                        -ComputerName $Computer `
                        -InstallerPath $Installer.FullPath

                    if (-not $CopyResult.Success) {
                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Failed to copy installer" `
                            -Details $CopyResult.Error
                        continue
                    }

                    Write-Host "[✓] Installer copied successfully" -ForegroundColor Green

                    # Step 3: Optional arguments
                    Write-Host "`n[>] Installation arguments (optional): " `
                        -ForegroundColor Yellow `
                        -NoNewline

                    $Arguments = Read-Host

                    # Step 4: Execute installation
                    Write-Host "`n[*] Installing software on $Computer..." -ForegroundColor Cyan
                    $InstallResult = Install-RemoteSoftware `
                        -ComputerName $Computer `
                        -InstallerPath $CopyResult.LocalPathOnly `
                        -Arguments $Arguments

                    if ($InstallResult.Success) {
                        Write-Log `
                            -Level Info `
                            -Message "Installation completed successfully on $Computer"

                        Show-ExecutionResult `
                            -Status Success `
                            -Message "Software installed successfully" `
                            -Details @"
Computer       : $($InstallResult.ComputerName)
Software       : $SoftwareName
Installer      : $($Installer.Name)
Exit Code      : $($InstallResult.ExitCode)
Duration       : $($InstallResult.Duration) ms

Output:
$($InstallResult.Output)
"@
                    }
                    else {
                        Write-Log `
                            -Level Error `
                            -Message "Installation failed on $Computer"

                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Installation failed" `
                            -Details @"
Computer  : $($InstallResult.ComputerName)
Software  : $SoftwareName
Exit Code : $($InstallResult.ExitCode)

Error:
$($InstallResult.Error)
"@
                    }
                }
                catch {
                    Write-Log `
                        -Level Error `
                        -Message "Unexpected error during installation: $($_.Exception.Message)"

                    Show-ExecutionResult `
                        -Status Error `
                        -Message "Unexpected installation error" `
                        -Details $_.Exception.Message
                }
            }

            2 {
                # ------------------------------------------------
                # Uninstall software
                # ------------------------------------------------

                Write-Host ""
                Write-Host "[>] Computer name: " `
                    -ForegroundColor Yellow `
                    -NoNewline

                $Computer = Read-Host

                if ([string]::IsNullOrWhiteSpace($Computer)) {
                    Write-Log `
                        -Level Info `
                        -Message "Software uninstall cancelled by user"
                    continue
                }

                Write-Host "[>] Software name (to search): " `
                    -ForegroundColor Yellow `
                    -NoNewline

                $SoftwareName = Read-Host

                if ([string]::IsNullOrWhiteSpace($SoftwareName)) {
                    Write-Log `
                        -Level Warning `
                        -Message "Software name was empty"

                    Show-ExecutionResult `
                        -Status Warning `
                        -Message "Software name cannot be empty"

                    continue
                }

                try {
                    Write-Log `
                        -Level Info `
                        -Message "Starting software uninstall workflow"

                    # Step 1: Get uninstall command
                    Write-Host "`n[*] Searching for software..." -ForegroundColor Cyan
                    $Software = Get-SoftwareUninstallCommand `
                        -ComputerName $Computer `
                        -SoftwareName $SoftwareName

                    if (-not $Software) {
                        Show-ExecutionResult `
                            -Status Warning `
                            -Message "Software not found" `
                            -Details "No software matching '$SoftwareName' found on $Computer"
                        continue
                    }

                    Write-Host "[✓] Software found: $($Software.Name)" -ForegroundColor Green
                    Write-Host "   Version: $($Software.Version)" -ForegroundColor Gray

                    # Step 2: Confirm uninstall
                    Write-Host "`n[!] Are you sure you want to uninstall this software? (yes/no): " `
                        -ForegroundColor Yellow `
                        -NoNewline

                    $Confirm = Read-Host

                    if ($Confirm -ne "yes") {
                        Write-Log `
                            -Level Info `
                            -Message "Uninstall cancelled by user"

                        Show-ExecutionResult `
                            -Status Info `
                            -Message "Uninstall cancelled"
                        continue
                    }

                    # Step 3: Execute uninstall
                    Write-Host "`n[*] Uninstalling software on $Computer..." -ForegroundColor Cyan
                    $UninstallResult = Uninstall-RemoteSoftware `
                        -ComputerName $Computer `
                        -UninstallCommand $Software.UninstallString

                    if ($UninstallResult.Success) {
                        Write-Log `
                            -Level Info `
                            -Message "Uninstall completed successfully on $Computer"

                        Show-ExecutionResult `
                            -Status Success `
                            -Message "Software uninstalled successfully" `
                            -Details @"
Computer   : $($UninstallResult.ComputerName)
Software   : $($Software.Name)
Version    : $($Software.Version)
Exit Code  : $($UninstallResult.ExitCode)
Duration   : $($UninstallResult.Duration) ms

Output:
$($UninstallResult.Output)
"@
                    }
                    else {
                        Write-Log `
                            -Level Error `
                            -Message "Uninstall failed on $Computer"

                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Uninstall failed" `
                            -Details @"
Computer  : $($UninstallResult.ComputerName)
Software  : $($Software.Name)
Exit Code : $($UninstallResult.ExitCode)

Error:
$($UninstallResult.Error)
"@
                    }
                }
                catch {
                    Write-Log `
                        -Level Error `
                        -Message "Unexpected error during uninstall: $($_.Exception.Message)"

                    Show-ExecutionResult `
                        -Status Error `
                        -Message "Unexpected uninstall error" `
                        -Details $_.Exception.Message
                }
            }

            3 {
                # ------------------------------------------------
                # List installed software
                # ------------------------------------------------

                Write-Host ""
                Write-Host "[>] Computer name: " `
                    -ForegroundColor Yellow `
                    -NoNewline

                $Computer = Read-Host

                if ([string]::IsNullOrWhiteSpace($Computer)) {
                    Write-Log `
                        -Level Info `
                        -Message "Software list cancelled by user"
                    continue
                }

                try {
                    Write-Log `
                        -Level Info `
                        -Message "Fetching installed software from $Computer"

                    Write-Host "`n[*] Querying installed software on $Computer..." -ForegroundColor Cyan
                    $InstalledSoftware = Get-InstalledSoftware -ComputerName $Computer

                    if ($InstalledSoftware.Count -eq 0) {
                        Show-ExecutionResult `
                            -Status Warning `
                            -Message "No software found" `
                            -Details "Could not retrieve software list from $Computer"
                        continue
                    }

                    Write-Log `
                        -Level Info `
                        -Message "Retrieved $(@($InstalledSoftware).Count) software entries from $Computer"

                    # Format and display software list
                    $SoftwareList = $InstalledSoftware | ForEach-Object {
                        $Version = if ($_.Version) { $_.Version } else { "N/A" }
                        "  • $($_.Name) (v$Version)"
                    }

                    Show-ExecutionResult `
                        -Status Success `
                        -Message "Installed software on $Computer" `
                        -Details @"
Total software installed: $(@($InstalledSoftware).Count)

$($SoftwareList -join "`n")
"@
                }
                catch {
                    Write-Log `
                        -Level Error `
                        -Message "Unexpected error listing software: $($_.Exception.Message)"

                    Show-ExecutionResult `
                        -Status Error `
                        -Message "Error listing software" `
                        -Details $_.Exception.Message
                }
            }

            0 {
                Write-Log `
                    -Level Info `
                    -Message "SoftwareMenu: returning to main menu"

                return
            }
        }
    }
}

# ============================================================
# SETTINGS MENU
# ============================================================

function Invoke-SettingsMenu {

    [CmdletBinding()]
    param()

    while ($true) {

        Clear-Host

        Show-Banner `
            -Title "Universal Remote Toolkit" `
            -Subtitle "Settings"

        Show-MainMenu `
            -MenuItems $SettingsMenu `
            -Description "Select a settings option:"

        $Choice = Read-MenuSelection `
            -ValidOptions @(0, 1, 2, 3)

        Write-Log `
            -Level Info `
            -Message "SettingsMenu: option $Choice selected"

        switch ($Choice) {

            1 {
                Show-ExecutionResult `
                    -Status Info `
                    -Message "Connection settings are under development."
            }

            2 {
                Show-ExecutionResult `
                    -Status Info `
                    -Message "Preferences are under development."
            }

            3 {
                Show-ExecutionResult `
                    -Status Info `
                    -Message "Universal Remote Toolkit v1.0 - Remote Administration Console"
            }

            0 {
                Write-Log `
                    -Level Info `
                    -Message "SettingsMenu: returning to main menu"

                return
            }
        }
    }
}

# ============================================================
# MAIN MENU
# ============================================================

function Start-UniversalRemoteToolkit {

    [CmdletBinding()]
    param()

    while ($true) {

        Clear-Host

        Show-Banner `
            -Title "Universal Remote Toolkit" `
            -Subtitle "Remote Administration Console"

        Show-MainMenu `
            -MenuItems $MainMenu `
            -Description "Select an option:"

        $Choice = Read-MenuSelection `
            -ValidOptions @(0, 1, 2, 3)

        Write-Log `
            -Level Info `
            -Message "MainMenu: option $Choice selected"

        switch ($Choice) {

            1 {
                Clear-Host
                Invoke-ExecutionMenu
            }

            2 {
                Clear-Host
                Invoke-SoftwareMenu
            }

            3 {
                Clear-Host
                Invoke-SettingsMenu
            }

            0 {

                Write-Log `
                    -Level Info `
                    -Message "User selected exit"

                Show-ExecutionResult `
                    -Status Info `
                    -Message "Universal Remote Toolkit shutting down..." `
                    -Pause $false

                return
            }
        }
    }
}

# ============================================================
# APPLICATION START
# ============================================================

try {

    Write-Log `
        -Level Info `
        -Message "Starting main application"

    Start-UniversalRemoteToolkit

}
catch {

    Write-Log `
        -Level Error `
        -Message "Unhandled application error: $($_.Exception.Message)"

    Show-ExecutionResult `
        -Status Error `
        -Message "Unexpected application error" `
        -Details $_.Exception.Message `
        -Pause $true
}
finally {

    try {

        Write-Log `
            -Level Info `
            -Message "=== Universal Remote Toolkit stopped ==="

        Stop-Log

    }
    catch {

        Write-Host `
            "[!] Failed to close logging session: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}