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
                        -Message "Starting execution on $Computer : $Executable $Arguments"

                    # ------------------------------------------------
                    # TEMPORARY MOCK
                    #
                    # Replace this with:
                    #
                    # Invoke-PsExecCommand
                    # ------------------------------------------------

                    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                    Start-Sleep -Milliseconds 150

                    $Stopwatch.Stop()

                    $Result = [PSCustomObject]@{

                        Computer   = $Computer
                        Command    = $Executable
                        Success    = $true
                        ExitCode   = 0
                        TimedOut   = $false
                        Output     = "Command executed successfully."
                        Error      = ""
                        DurationMS = $Stopwatch.ElapsedMilliseconds
                        Timestamp  = Get-Date
                    }

                    Write-Log `
                        -Level Success `
                        -Message "Execution completed on $Computer"

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
                catch {

                    Write-Log `
                        -Level Error `
                        -Message "Execution failed: $($_.Exception.Message)"

                    Show-ExecutionResult `
                        -Status Error `
                        -Message "Failed to execute command" `
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
                Show-ExecutionResult `
                    -Status Info `
                    -Message "Software installation is under development."
            }

            2 {
                Show-ExecutionResult `
                    -Status Info `
                    -Message "Software removal is under development."
            }

            3 {
                Show-ExecutionResult `
                    -Status Info `
                    -Message "Installed software listing is under development."
            }

            0 {
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
                    -Message "Universal Remote Toolkit"
            }

            0 {
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
                Invoke-ExecutionMenu
            }

            2 {
                Invoke-SoftwareMenu
            }

            3 {
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