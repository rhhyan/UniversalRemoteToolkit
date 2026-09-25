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
    'Scripts.psm1'
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
            -DisableNameChecking `
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
    4 = "Scripts"
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

$ScriptsMenu = [ordered]@{
    1 = "Otimizacao do Windows"
    2 = "Ativar Windows/Office"
    0 = "Voltar ao menu principal"
}

$OptimizationMenu = [ordered]@{
    1 = "Remover perfis BC, XTR, XTC, TEMP e TH (+ chaves de registro) + SFC"
    2 = "Remover apps pre-instalados (debloat)"
    3 = "Reparo do Windows com DISM (quando o SFC nao resolve)"
    4 = "Ajustar efeitos visuais (melhor desempenho)"
    5 = "Desativar Spooler, SysMain, WSearch (avalie a necessidade)"
    0 = "Voltar"
}

$ActivationMenu = [ordered]@{
    1 = "Ativar Microsoft Office (32/64 bits detectado automaticamente)"
    2 = "Ativar Windows"
    3 = "Verificar status de ativacao"
    0 = "Voltar"
}

# ============================================================
# SCREEN HELPERS
# ============================================================

function Show-Screen {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subtitle
    )

    Clear-Host

    Show-Banner `
        -Title $Config.Application.Name `
        -Subtitle $Subtitle
}

function Read-MenuChoice {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Menu,

        [Parameter(Mandatory)]
        [string]$Description
    )

    Show-MainMenu `
        -MenuItems $Menu `
        -Description $Description

    return Read-MenuSelection `
        -ValidOptions @($Menu.Keys)
}

# ============================================================
# EXECUTION MENU
# ============================================================

function Invoke-ExecutionMenu {

    [CmdletBinding()]
    param()

    while ($true) {

        Show-Screen -Subtitle "Remote Execution"

        $Choice = Read-MenuChoice `
            -Menu $ExecutionMenu `
            -Description "Select an execution option:"

        Write-Log `
            -Level Info `
            -Message "ExecutionMenu: option $Choice selected"

        switch ($Choice) {

            # ------------------------------------------------
            # Execute command
            # ------------------------------------------------

            1 {

                Show-Section -Title "Execute command"

                $Computer = Read-UserInput -Prompt "Computer name"

                if ([string]::IsNullOrWhiteSpace($Computer)) {

                    Write-Log `
                        -Level Info `
                        -Message "Command execution cancelled by user"

                    continue
                }

                $Executable = Read-UserInput -Prompt "Executable"

                if ([string]::IsNullOrWhiteSpace($Executable)) {

                    Write-Log `
                        -Level Warning `
                        -Message "Executable was empty"

                    Show-ExecutionResult `
                        -Status Warning `
                        -Message "Executable cannot be empty"

                    continue
                }

                $Arguments = Read-UserInput -Prompt "Arguments (optional)"

                try {

                    Write-Log `
                        -Level Info `
                        -Message "Starting remote execution on $Computer"

                    Write-Host ""
                    Write-Status -Status Running -Message "Executing on $Computer..."

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
                            -Properties ([ordered]@{
                                Computer = $Result.Computer
                                Command  = $Result.Command
                                ExitCode = $Result.ExitCode
                                Duration = "$($Result.DurationMS) ms"
                            }) `
                            -DetailsTitle "Output:" `
                            -Details $Result.Output
                    }
                    else {

                        Write-Log `
                            -Level Error `
                            -Message "Execution failed on $Computer"

                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Command execution failed" `
                            -Properties ([ordered]@{
                                Computer = $Result.Computer
                                ExitCode = $Result.ExitCode
                            }) `
                            -DetailsTitle "Error:" `
                            -Details $Result.Error
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

        Show-Screen -Subtitle "Software Management"

        $Choice = Read-MenuChoice `
            -Menu $SoftwareMenu `
            -Description "Select a software management option:"

        Write-Log `
            -Level Info `
            -Message "SoftwareMenu: option $Choice selected"

        switch ($Choice) {

            1 {
                # ------------------------------------------------
                # Install software
                # ------------------------------------------------

                Show-Section -Title "Install software"

                $Computer = Read-UserInput -Prompt "Computer name"

                if ([string]::IsNullOrWhiteSpace($Computer)) {
                    Write-Log `
                        -Level Info `
                        -Message "Software installation cancelled by user"
                    continue
                }

                $SoftwareName = Read-UserInput -Prompt "Software name (to search)"

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
                    Write-Host ""
                    Write-Status -Status Running -Message "Searching for installer..."
                    $Installers = @(Get-SoftwareRepository -Filter $SoftwareName)

                    if ($Installers.Count -eq 0) {
                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Installer not found" `
                            -Details "No matching installer found in repository for: $SoftwareName"
                        continue
                    }

                    $Installer = Read-ItemSelection `
                        -Items $Installers `
                        -Title "Multiple installers found:" `
                        -DisplayProperty { "$($_.Name)  [$($_.FullPath)]" }

                    if (-not $Installer) {
                        Write-Log `
                            -Level Info `
                            -Message "Software installation cancelled by user"
                        continue
                    }

                    Write-Status -Status Success -Message "Installer found: $($Installer.Name)"

                    # Step 2: Copy to remote
                    Write-Status -Status Running -Message "Copying installer to $Computer..."
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

                    Write-Status -Status Success -Message "Installer copied successfully"

                    # Step 3: Optional arguments
                    Write-Host ""
                    $Arguments = Read-UserInput -Prompt "Installation arguments (optional)"

                    # Step 4: Execute installation
                    Write-Host ""
                    Write-Status -Status Running -Message "Installing software on $Computer..."
                    $InstallResult = Install-RemoteSoftware `
                        -ComputerName $Computer `
                        -InstallerPath $CopyResult.LocalPathOnly `
                        -Arguments $Arguments

                    # Step 5: Remove the copied installer from the remote temp folder
                    try {
                        Remove-Item -Path $CopyResult.RemotePath -Force -ErrorAction Stop

                        Write-Log `
                            -Level Info `
                            -Message "Removed remote installer: $($CopyResult.RemotePath)"
                    }
                    catch {
                        Write-Log `
                            -Level Warning `
                            -Message "Could not remove remote installer $($CopyResult.RemotePath): $($_.Exception.Message)"
                    }

                    if ($InstallResult.Success) {
                        Write-Log `
                            -Level Info `
                            -Message "Installation completed successfully on $Computer"

                        Show-ExecutionResult `
                            -Status Success `
                            -Message "Software installed successfully" `
                            -Properties ([ordered]@{
                                'Computer'      = $InstallResult.ComputerName
                                'Software'      = $SoftwareName
                                'Installer'     = $Installer.Name
                                'Exit Code'     = $InstallResult.ExitCode
                                'Reboot needed' = $(if ($InstallResult.RebootRequired) { "Yes" } else { "No" })
                                'Duration'      = "$($InstallResult.Duration) ms"
                            }) `
                            -DetailsTitle "Output:" `
                            -Details $InstallResult.Output
                    }
                    else {
                        Write-Log `
                            -Level Error `
                            -Message "Installation failed on $Computer"

                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Installation failed" `
                            -Properties ([ordered]@{
                                'Computer'  = $InstallResult.ComputerName
                                'Software'  = $SoftwareName
                                'Exit Code' = $InstallResult.ExitCode
                            }) `
                            -DetailsTitle "Error:" `
                            -Details $InstallResult.Error
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

                Show-Section -Title "Uninstall software"

                $Computer = Read-UserInput -Prompt "Computer name"

                if ([string]::IsNullOrWhiteSpace($Computer)) {
                    Write-Log `
                        -Level Info `
                        -Message "Software uninstall cancelled by user"
                    continue
                }

                $SoftwareName = Read-UserInput -Prompt "Software name (to search)"

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
                    Write-Host ""
                    Write-Status -Status Running -Message "Searching for software on $Computer..."
                    $FoundSoftware = @(
                        Get-InstalledSoftware -ComputerName $Computer |
                            Where-Object { $_.Name -like "*$SoftwareName*" }
                    )

                    if ($FoundSoftware.Count -eq 0) {
                        Show-ExecutionResult `
                            -Status Warning `
                            -Message "Software not found" `
                            -Details "No software matching '$SoftwareName' found on $Computer"
                        continue
                    }

                    $Software = Read-ItemSelection `
                        -Items $FoundSoftware `
                        -Title "Multiple programs found. Select which one to uninstall:" `
                        -DisplayProperty { "$($_.Name) (v$($_.Version))  [$($_.Scope)]" }

                    if (-not $Software) {
                        Write-Log `
                            -Level Info `
                            -Message "Uninstall cancelled by user"
                        continue
                    }

                    # Step 2: Resolve silent uninstall command
                    try {
                        $Plan = Resolve-UninstallCommand -Software $Software
                    }
                    catch {
                        Show-ExecutionResult `
                            -Status Error `
                            -Message "No uninstall command registered" `
                            -Details $_.Exception.Message
                        continue
                    }

                    Write-Status -Status Success -Message "Software found: $($Software.Name)"
                    Write-Host ""
                    Show-Properties -Properties ([ordered]@{
                        'Version'   = $Software.Version
                        'Publisher' = $Software.Publisher
                        'Scope'     = $Software.Scope
                        'Installer' = $Plan.InstallerType
                        'Command'   = $Plan.CommandLine
                    })

                    $CustomArguments = ""

                    if (-not $Plan.Silent) {
                        Write-Host ""
                        Write-Status -Status Warning -Message "No silent switch is known for this uninstaller."
                        Write-Host "      Without one it may wait for a window nobody can see until the timeout." -ForegroundColor Yellow

                        $CustomArguments = Read-UserInput -Prompt "Silent arguments (optional, replaces current arguments)"
                    }

                    # Step 3: Confirm uninstall
                    if (-not (Read-Confirmation -Prompt "Uninstall $($Software.Name) from ${Computer}?")) {
                        Write-Log `
                            -Level Info `
                            -Message "Uninstall cancelled by user"

                        Show-ExecutionResult `
                            -Status Info `
                            -Message "Uninstall cancelled"
                        continue
                    }

                    # Step 4: Execute uninstall and verify removal
                    Write-Host ""
                    Write-Status -Status Running -Message "Uninstalling software on $Computer..."
                    $UninstallResult = Uninstall-RemoteSoftware `
                        -ComputerName $Computer `
                        -Software $Software `
                        -Arguments $CustomArguments

                    if ($UninstallResult.Success) {
                        Write-Log `
                            -Level Info `
                            -Message "Uninstall completed successfully on $Computer"

                        Show-ExecutionResult `
                            -Status Success `
                            -Message "Software uninstalled successfully" `
                            -Properties ([ordered]@{
                                'Computer'  = $UninstallResult.ComputerName
                                'Software'  = $Software.Name
                                'Version'   = $Software.Version
                                'Installer' = $UninstallResult.UninstallerType
                                'Command'   = $UninstallResult.UninstallCmd
                                'Exit Code' = $UninstallResult.ExitCode
                                'Verified'  = $(if ($UninstallResult.Verified) { "Yes (removed from registry)" } else { "No" })
                                'Reboot'    = $(if ($UninstallResult.RebootRequired) { "Required" } else { "Not required" })
                                'Duration'  = "$($UninstallResult.Duration) ms"
                            }) `
                            -DetailsTitle "Output:" `
                            -Details $UninstallResult.Output
                    }
                    else {
                        Write-Log `
                            -Level Error `
                            -Message "Uninstall failed on $Computer"

                        Show-ExecutionResult `
                            -Status Error `
                            -Message "Uninstall failed" `
                            -Properties ([ordered]@{
                                'Computer'  = $UninstallResult.ComputerName
                                'Software'  = $Software.Name
                                'Installer' = $UninstallResult.UninstallerType
                                'Command'   = $UninstallResult.UninstallCmd
                                'Exit Code' = $UninstallResult.ExitCode
                            }) `
                            -DetailsTitle "Error:" `
                            -Details $UninstallResult.Error
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

                Show-Section -Title "List installed software"

                $Computer = Read-UserInput -Prompt "Computer name"

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

                    Write-Host ""
                    Write-Status -Status Running -Message "Querying installed software on $Computer..."
                    $InstalledSoftware = @(Get-InstalledSoftware -ComputerName $Computer)

                    if ($InstalledSoftware.Count -eq 0) {
                        Show-ExecutionResult `
                            -Status Warning `
                            -Message "No software found" `
                            -Details "Could not retrieve software list from $Computer"
                        continue
                    }

                    Write-Log `
                        -Level Info `
                        -Message "Retrieved $($InstalledSoftware.Count) software entries from $Computer"

                    # Tabela em duas colunas: nome (truncado) e versão
                    $NameWidth = [math]::Min(
                        48,
                        ($InstalledSoftware | ForEach-Object { "$($_.Name)".Length } | Measure-Object -Maximum).Maximum
                    )

                    $SoftwareList = $InstalledSoftware | Sort-Object -Property Name | ForEach-Object {
                        $Name = "$($_.Name)"

                        if ($Name.Length -gt $NameWidth) {
                            $Name = $Name.Substring(0, $NameWidth - 3) + "..."
                        }

                        $Version = if ($_.Version) { $_.Version } else { "N/A" }
                        "$($Name.PadRight($NameWidth))  $Version"
                    }

                    $Header = "$("NAME".PadRight($NameWidth))  VERSION"

                    Show-ExecutionResult `
                        -Status Success `
                        -Message "Installed software on $Computer" `
                        -Properties ([ordered]@{ 'Total' = $InstalledSoftware.Count }) `
                        -Details (@($Header) + @($SoftwareList) -join "`n")
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

        Show-Screen -Subtitle "Settings"

        $Choice = Read-MenuChoice `
            -Menu $SettingsMenu `
            -Description "Select a settings option:"

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
                    -Message "$($Config.Application.Name) - Remote Administration Console" `
                    -Properties ([ordered]@{
                        'Version'    = $Config.Application.Version
                        'Company'    = $Config.Company.Name
                        'PowerShell' = $PSVersionTable.PSVersion
                        'Root'       = $ProjectRoot
                        'Repository' = $Config.Software.RepositoryPath
                        'Admin'      = $(if (Test-IsAdministrator) { "Yes" } else { "No" })
                    })
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
# SCRIPTS MENU
# ============================================================

function Read-TargetComputers {

    [CmdletBinding()]
    param()

    $InputText = Read-UserInput -Prompt "Computador(es) (separe por virgula ou espaco)"

    return @(
        $InputText -split '[,; ]+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim().TrimStart('\') } |
            Select-Object -Unique
    )
}

function Invoke-ScriptOnComputers {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Computers,

        [Parameter(Mandatory)]
        [string]$Label,

        # Recebe o nome do computador e retorna o resultado do Scripts.psm1
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    Write-Host ""

    $Results = foreach ($Computer in $Computers) {

        Write-Status -Status Running -Message "$Computer - $Label..."

        $Result = & $ScriptBlock $Computer

        $Status = switch ($Result.Status) {
            'Success' { 'Success' }
            'Partial' { 'Warning' }
            default   { 'Error' }
        }

        Write-Status -Status $Status -Message "$Computer - $($Result.Status)"

        $Result
    }

    Show-ScriptResults -Results @($Results)
}

function Show-ScriptResults {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results
    )

    foreach ($Result in $Results) {

        Show-Section -Title "$($Result.Computer) - $($Result.Status)"

        if ($Result.Output) {
            $Result.Output.TrimEnd() -split "\r?\n" | ForEach-Object {
                Write-Host "    $_" -ForegroundColor Gray
            }
        }

        if ($Result.Error -and -not $Result.Success) {
            Write-Status -Status Error -Message $Result.Error
        }
    }

    $Ok = @($Results | Where-Object Success).Count

    $Summary = $Results | ForEach-Object {
        "{0,-20} {1,-9} {2,-6} {3}" -f $_.Computer, $_.Status, "$($_.ExitCode)", ('{0:mm\:ss}' -f [timespan]::FromMilliseconds([double]$_.DurationMS))
    }

    Show-ExecutionResult `
        -Status $(if ($Ok -eq $Results.Count) { 'Success' } elseif ($Ok -gt 0) { 'Warning' } else { 'Error' }) `
        -Message "$Ok de $($Results.Count) computador(es) concluidos" `
        -Details (@("{0,-20} {1,-9} {2,-6} {3}" -f 'COMPUTADOR', 'STATUS', 'EXIT', 'DURACAO') + @($Summary) -join "`n")
}

function Invoke-OptimizationMenu {

    [CmdletBinding()]
    param()

    while ($true) {

        Show-Screen -Subtitle "Scripts > Otimizacao do Windows"

        $Choice = Read-MenuChoice `
            -Menu $OptimizationMenu `
            -Description "Selecione a otimizacao:"

        Write-Log `
            -Level Info `
            -Message "OptimizationMenu: option $Choice selected"

        if ($Choice -eq 0) {
            return
        }

        $Action = switch ($Choice) {
            1 { 'CleanProfiles' }
            2 { 'Debloat' }
            3 { 'RepairImage' }
            4 { 'VisualEffects' }
            5 { 'DisableServices' }
        }

        # [object] força a busca pela chave; com int, [ordered][n] usa a posição
        Show-Section -Title $OptimizationMenu[[object]$Choice]

        $Computers = Read-TargetComputers

        if ($Computers.Count -eq 0) {
            Write-Log `
                -Level Info `
                -Message "Optimization cancelled: no computer informed"
            continue
        }

        $Params = @{ Action = $Action }

        if ($Action -eq 'CleanProfiles') {

            $Keep = @((Read-UserInput -Prompt "Matriculas TH a MANTER (Enter = nenhuma)") -split '[,; ]+' | Where-Object { $_ })

            Write-Host ""
            Show-Properties -Properties ([ordered]@{
                'Remover'   = "Perfis BC*, XTR*, XTC*, TEMP* e TH*"
                'Excecoes'  = $(if ($Keep) { $Keep -join ', ' } else { '(nenhuma)' })
                'Em uso'    = "Perfis de usuarios logados sao ignorados"
            })

            if (-not (Read-Confirmation -Prompt "Confirma a exclusao em $($Computers -join ', ')?")) {
                Write-Log `
                    -Level Info `
                    -Message "CleanProfiles cancelled by user"
                continue
            }

            $Params.KeepProfiles = $Keep

            if (-not (Read-Confirmation -Prompt "Executar SFC /SCANNOW ao final? (~15 min)")) {
                $Params.SkipSfc = $true
            }
        }

        if ($Action -eq 'DisableServices') {

            Write-Host ""
            Write-Status -Status Warning -Message "O Spooler desativado impede IMPRESSAO na maquina."
            Write-Status -Status Info -Message "Tambem desativa WSearch (indexacao) e SysMain."

            if (-not (Read-Confirmation -Prompt "Deseja continuar?")) {
                Write-Log `
                    -Level Info `
                    -Message "DisableServices cancelled by user"
                continue
            }
        }

        Invoke-ScriptOnComputers `
            -Computers $Computers `
            -Label $Action `
            -ScriptBlock { param($Computer) Invoke-WindowsOptimization -ComputerName $Computer @Params }.GetNewClosure()
    }
}

function Invoke-ActivationMenu {

    [CmdletBinding()]
    param()

    while ($true) {

        Show-Screen -Subtitle "Scripts > Ativar Windows/Office"

        $Choice = Read-MenuChoice `
            -Menu $ActivationMenu `
            -Description "Selecione a ativacao:"

        Write-Log `
            -Level Info `
            -Message "ActivationMenu: option $Choice selected"

        if ($Choice -eq 0) {
            return
        }

        $Target = switch ($Choice) {
            1 { 'Office' }
            2 { 'Windows' }
            3 { 'Status' }
        }

        # [object] força a busca pela chave; com int, [ordered][n] usa a posição
        Show-Section -Title $ActivationMenu[[object]$Choice]

        $Computers = Read-TargetComputers

        if ($Computers.Count -eq 0) {
            Write-Log `
                -Level Info `
                -Message "Activation cancelled: no computer informed"
            continue
        }

        Invoke-ScriptOnComputers `
            -Computers $Computers `
            -Label $Target `
            -ScriptBlock { param($Computer) Invoke-LicenseActivation -ComputerName $Computer -Target $Target }.GetNewClosure()
    }
}

function Invoke-ScriptsMenu {

    [CmdletBinding()]
    param()

    while ($true) {

        Show-Screen -Subtitle "Scripts"

        $Choice = Read-MenuChoice `
            -Menu $ScriptsMenu `
            -Description "Selecione um script:"

        Write-Log `
            -Level Info `
            -Message "ScriptsMenu: option $Choice selected"

        switch ($Choice) {

            1 {
                Invoke-OptimizationMenu
            }

            2 {
                Invoke-ActivationMenu
            }

            0 {
                Write-Log `
                    -Level Info `
                    -Message "ScriptsMenu: returning to main menu"

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

        Show-Screen -Subtitle "Remote Administration Console  v$($Config.Application.Version)"

        $Choice = Read-MenuChoice `
            -Menu $MainMenu `
            -Description "Select an option:"

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

            4 {
                Invoke-ScriptsMenu
            }

            0 {

                Write-Log `
                    -Level Info `
                    -Message "User selected exit"

                Show-ExecutionResult `
                    -Status Info `
                    -Message "$($Config.Application.Name) shutting down..." `
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

    Initialize-ConsoleUI -Title "$($Config.Application.Name) v$($Config.Application.Version)"

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