# ============================================================
# Universal Remote Toolkit
# Module: Software Management
# Description: Universal software installation and uninstallation
# ============================================================

# ============================================================
# CONSTANTS
# ============================================================

$REPOSITORY_PATH = "\\fsrctrppw01\aplicativos"
$TEMP_SCRIPT_PATH = "C:\script_temp"
$SUPPORTED_INSTALLERS = @(".exe", ".msi", ".ps1")

# ============================================================
# GET SOFTWARE REPOSITORY
# ============================================================

<#
.SYNOPSIS
    Lists available software installers in the network repository.

.DESCRIPTION
    Scans the network repository path and returns available software
    installers with their full paths.

.PARAMETER Filter
    Optional filter to search by software name.

.OUTPUTS
    System.Object[]
    Returns an array of PSCustomObjects with installer information.

.EXAMPLE
    Get-SoftwareRepository

    Lists all available installers in the repository.

.EXAMPLE
    Get-SoftwareRepository -Filter "Chrome"

    Lists installers containing "Chrome" in the name.
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

            if (-not (Test-Path -Path $REPOSITORY_PATH)) {
                throw "Repository not accessible: $REPOSITORY_PATH"
            }

            $Installers = @()

            # Procura por arquivos de instalação (até 5 níveis de profundidade)
            foreach ($Extension in $SUPPORTED_INSTALLERS) {
                $Files = Get-ChildItem `
                    -Path $REPOSITORY_PATH `
                    -Filter "*$Extension" `
                    -File `
                    -Recurse `
                    -Depth 5 `
                    -ErrorAction SilentlyContinue

                if ($Files) {
                    $Installers += $Files
                }
            }

            # Aplica filtro se fornecido
            if (-not [string]::IsNullOrWhiteSpace($Filter)) {
                $Installers = $Installers | Where-Object {
                    $_.Name -like "*$Filter*"
                }
            }

            # Retorna resultado estruturado
            $Installers | ForEach-Object {
                [PSCustomObject]@{
                    Name          = $_.Name
                    FullPath      = $_.FullName
                    Extension     = $_.Extension
                    Size          = $_.Length
                    LastModified  = $_.LastWriteTime
                    InstallerType = if ($_.Extension -eq ".msi") { "MSI" } elseif ($_.Extension -eq ".ps1") { "PowerShell" } else { "Executable" }
                }
            }

            Write-Log `
                -Level Info `
                -Message "Repository scan completed. Found $(@($Installers).Count) installers."
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error scanning repository: $($_.Exception.Message)"

            throw $_
        }
    }
}

# ============================================================
# FIND SOFTWARE INSTALLER
# ============================================================

<#
.SYNOPSIS
    Searches for a specific software installer in the repository.

.PARAMETER SoftwareName
    Name of the software to search for.

.OUTPUTS
    System.Object
    Returns a PSCustomObject with installer details, or $null if not found.

.EXAMPLE
    Find-SoftwareInstaller -SoftwareName "Chrome"
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

            $Repository = Get-SoftwareRepository -Filter $SoftwareName

            if ($Repository) {
                $Installer = $Repository | Select-Object -First 1

                Write-Log `
                    -Level Info `
                    -Message "Installer found: $($Installer.Name)"

                return $Installer
            }
            else {
                Write-Log `
                    -Level Warning `
                    -Message "No installer found for: $SoftwareName"

                return $null
            }
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error finding installer: $($_.Exception.Message)"

            throw $_
        }
    }
}

# ============================================================
# COPY SOFTWARE TO REMOTE
# ============================================================

<#
.SYNOPSIS
    Copies a software installer to the remote computer's temp directory.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER InstallerPath
    Full path to the installer file.

.OUTPUTS
    System.Object
    Returns PSCustomObject with copy status and remote path.

.EXAMPLE
    Copy-SoftwareToRemote -ComputerName "PC-001" -InstallerPath "\\server\path\installer.exe"
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
            if (-not (Test-Path -Path $InstallerPath)) {
                throw "Installer file not found: $InstallerPath"
            }

            Write-Log `
                -Level Info `
                -Message "Copying installer to $ComputerName"

            $InstallerName = Split-Path -Leaf $InstallerPath
            $RemotePath = "\\$ComputerName\C$\script_temp"

            # Cria diretório se não existir
            if (-not (Test-Path -Path $RemotePath)) {
                New-Item -ItemType Directory -Path $RemotePath -Force -ErrorAction Stop | Out-Null
                Write-Log `
                    -Level Info `
                    -Message "Created remote directory: $RemotePath"
            }

            # Copia o arquivo
            $RemoteFilePath = Join-Path $RemotePath $InstallerName
            Copy-Item -Path $InstallerPath -Destination $RemoteFilePath -Force -ErrorAction Stop

            Write-Log `
                -Level Info `
                -Message "Installer copied successfully to $RemoteFilePath"

            [PSCustomObject]@{
                Success       = $true
                ComputerName  = $ComputerName
                LocalPath     = $InstallerPath
                RemotePath    = $RemoteFilePath
                FileName      = $InstallerName
                LocalPathOnly = "C:\script_temp\$InstallerName"
            }
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error copying installer to $ComputerName`: $($_.Exception.Message)"

            [PSCustomObject]@{
                Success       = $false
                ComputerName  = $ComputerName
                LocalPath     = $InstallerPath
                RemotePath    = $null
                FileName      = Split-Path -Leaf $InstallerPath
                Error         = $_.Exception.Message
            }
        }
    }
}

# ============================================================
# INSTALL SOFTWARE
# ============================================================

<#
.SYNOPSIS
    Installs software on a remote computer.

.DESCRIPTION
    Executes an installer on a remote computer using PsExec.
    Supports .exe, .msi, and .ps1 installers.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER InstallerPath
    Local path to the installer on the remote computer (e.g., C:\script_temp\installer.exe).

.PARAMETER Arguments
    Optional arguments to pass to the installer.

.PARAMETER TimeoutSeconds
    Maximum execution time in seconds (default: 300).

.OUTPUTS
    System.Object
    Returns installation result with status and details.

.EXAMPLE
    Install-RemoteSoftware -ComputerName "PC-001" -InstallerPath "C:\script_temp\installer.exe"

.EXAMPLE
    Install-RemoteSoftware -ComputerName "PC-001" -InstallerPath "C:\script_temp\setup.msi" -Arguments "/quiet /norestart"
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
        [int]$TimeoutSeconds = 300
    )

    process {
        try {
            Write-Log `
                -Level Info `
                -Message "Installing software on $ComputerName from $InstallerPath"

            # Determina o tipo de instalador e argumentos padrão
            $Extension = [System.IO.Path]::GetExtension($InstallerPath).ToLower()

            $InstallCommand = switch ($Extension) {
                ".msi" {
                    if ([string]::IsNullOrWhiteSpace($Arguments)) {
                        "$InstallerPath /quiet /norestart"
                    }
                    else {
                        "$InstallerPath $Arguments"
                    }
                }

                ".ps1" {
                    if ([string]::IsNullOrWhiteSpace($Arguments)) {
                        "powershell.exe -ExecutionPolicy Bypass -File `"$InstallerPath`""
                    }
                    else {
                        "powershell.exe -ExecutionPolicy Bypass -File `"$InstallerPath`" $Arguments"
                    }
                }

                ".exe" {
                    if ([string]::IsNullOrWhiteSpace($Arguments)) {
                        $InstallerPath
                    }
                    else {
                        "$InstallerPath $Arguments"
                    }
                }

                default {
                    throw "Unsupported installer type: $Extension"
                }
            }

            # Executa via PsExec
            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable "cmd.exe" `
                -Arguments "/c $InstallCommand" `
                -TimeoutSeconds $TimeoutSeconds

            if ($Result.Success -or $Result.ExitCode -eq 0) {
                Write-Log `
                    -Level Info `
                    -Message "Software installed successfully on $ComputerName"

                return [PSCustomObject]@{
                    Success       = $true
                    ComputerName  = $ComputerName
                    InstallerPath = $InstallerPath
                    ExitCode      = $Result.ExitCode
                    Output        = $Result.Output
                    Duration      = $Result.DurationMS
                    Timestamp     = Get-Date
                }
            }
            else {
                Write-Log `
                    -Level Error `
                    -Message "Installation failed on $ComputerName with exit code: $($Result.ExitCode)"

                return [PSCustomObject]@{
                    Success       = $false
                    ComputerName  = $ComputerName
                    InstallerPath = $InstallerPath
                    ExitCode      = $Result.ExitCode
                    Error         = $Result.Error
                    Output        = $Result.Output
                    Duration      = $Result.DurationMS
                    Timestamp     = Get-Date
                }
            }
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error installing software on $ComputerName`: $($_.Exception.Message)"

            return [PSCustomObject]@{
                Success       = $false
                ComputerName  = $ComputerName
                InstallerPath = $InstallerPath
                Error         = $_.Exception.Message
                Timestamp     = Get-Date
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
    Queries the remote computer's registry to retrieve a list of
    installed applications.

.PARAMETER ComputerName
    Name of the remote computer.

.OUTPUTS
    System.Object[]
    Returns array of installed software with names and versions.

.EXAMPLE
    Get-InstalledSoftware -ComputerName "PC-001"

    Lists all installed software on PC-001.
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

            # PowerShell script para executar remotamente
            # Usar aspas simples e escapar corretamente para remoto
            $QueryScript = @"
try {
    `$RegPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    `$InstalledApps = @()

    foreach (`$RegPath in `$RegPaths) {
        if (Test-Path `$RegPath) {
            Get-ChildItem `$RegPath -ErrorAction SilentlyContinue | ForEach-Object {
                `$DisplayName = `$_.GetValue('DisplayName')
                `$DisplayVersion = `$_.GetValue('DisplayVersion')
                `$UninstallString = `$_.GetValue('UninstallString')

                if (`$DisplayName) {
                    `$InstalledApps += [PSCustomObject]@{
                        Name             = `$DisplayName
                        Version          = `$DisplayVersion
                        UninstallString  = `$UninstallString
                        RegistryPath     = `$_.PSPath
                    }
                }
            }
        }
    }

    if (`$InstalledApps.Count -gt 0) {
        `$InstalledApps | Sort-Object Name | ConvertTo-Json -Depth 3
    } else {
        Write-Output '[]'
    }
} catch {
    Write-Output '[]'
}
"@

            # Executa o script remotamente
            # Escapar o script para ser transmitido via PsExec
            $EncodedScript = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($QueryScript)
            )
            
            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable "powershell.exe" `
                -Arguments "-NoProfile -NoLogo -ExecutionPolicy Bypass -EncodedCommand $EncodedScript"

            if ($Result.Success) {
                try {
                    $OutputTrim = $Result.Output.Trim()
                    
                    # Validar se há saída
                    if ([string]::IsNullOrWhiteSpace($OutputTrim)) {
                        Write-Log `
                            -Level Info `
                            -Message "No software found on $ComputerName (empty response)"
                        return @()
                    }

                    # Tentar extrair JSON válido do output (pode ter mensagens antes/depois)
                    # Procura por [ ou { que começa o JSON
                    $JsonStart = $OutputTrim.IndexOf('[')
                    if ($JsonStart -eq -1) {
                        $JsonStart = $OutputTrim.IndexOf('{')
                    }
                    
                    if ($JsonStart -gt 0) {
                        # Remove tudo antes do JSON
                        $OutputTrim = $OutputTrim.Substring($JsonStart)
                    }
                    
                    # Procura pelo último ] ou } que fecha o JSON
                    $JsonEnd = $OutputTrim.LastIndexOf(']')
                    $JsonEnd2 = $OutputTrim.LastIndexOf('}')
                    $JsonEnd = [Math]::Max($JsonEnd, $JsonEnd2)
                    
                    if ($JsonEnd -gt 0) {
                        # Remove tudo depois do JSON
                        $OutputTrim = $OutputTrim.Substring(0, $JsonEnd + 1)
                    }

                    # Tentar parsear JSON
                    $InstalledApps = $OutputTrim | ConvertFrom-Json -ErrorAction Stop

                    # Garantir que é sempre um array
                    if ($InstalledApps -eq $null) {
                        $InstalledApps = @()
                    } elseif (-not ($InstalledApps -is [array])) {
                        $InstalledApps = @($InstalledApps)
                    }

                    Write-Log `
                        -Level Info `
                        -Message "Found $($InstalledApps.Count) installed applications on $ComputerName"

                    return $InstalledApps
                }
                catch {
                    Write-Log `
                        -Level Warning `
                        -Message "Could not parse installed software list from $ComputerName : $($_.Exception.Message). Raw output: $($Result.Output.Substring(0, [Math]::Min(100, $Result.Output.Length)))"

                    return @()
                }
            }
            else {
                Write-Log `
                    -Level Warning `
                    -Message "Failed to query installed software on $ComputerName. Exit code: $($Result.ExitCode). Error: $($Result.Error)"

                return @()
            }
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error retrieving installed software from $ComputerName`: $($_.Exception.Message)"

            return @()
        }
    }
}

# ============================================================
# GET SOFTWARE UNINSTALL COMMAND
# ============================================================

<#
.SYNOPSIS
    Retrieves the uninstall command for a specific software.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER SoftwareName
    Name of the software to uninstall.

.OUTPUTS
    System.Object
    Returns the uninstall command and related information.

.EXAMPLE
    Get-SoftwareUninstallCommand -ComputerName "PC-001" -SoftwareName "Google Chrome"
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
                -Message "Retrieving uninstall command for $SoftwareName on $ComputerName"

            $InstalledApps = Get-InstalledSoftware -ComputerName $ComputerName

            $Software = $InstalledApps | Where-Object {
                $_.Name -like "*$SoftwareName*"
            } | Select-Object -First 1

            if ($Software) {
                Write-Log `
                    -Level Info `
                    -Message "Found uninstall command for $($Software.Name)"

                return $Software
            }
            else {
                Write-Log `
                    -Level Warning `
                    -Message "No software found matching: $SoftwareName"

                return $null
            }
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error retrieving uninstall command: $($_.Exception.Message)"

            throw $_
        }
    }
}

# ============================================================
# UNINSTALL SOFTWARE
# ============================================================

<#
.SYNOPSIS
    Uninstalls software from a remote computer.

.DESCRIPTION
    Executes the uninstall command for a specified software on a
    remote computer using PsExec.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER UninstallCommand
    The uninstall command to execute.

.PARAMETER TimeoutSeconds
    Maximum execution time in seconds (default: 300).

.OUTPUTS
    System.Object
    Returns uninstallation result with status and details.

.EXAMPLE
    Uninstall-RemoteSoftware -ComputerName "PC-001" -UninstallCommand "MsiExec.exe /X{GUID} /quiet /norestart"
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
        [int]$TimeoutSeconds = 300
    )

    process {
        try {
            Write-Log `
                -Level Info `
                -Message "Uninstalling software on $ComputerName"

            # Se o comando for MsiExec, garantir que use /quiet e /norestart
            $FinalCommand = $UninstallCommand

            if ($UninstallCommand -like "*MsiExec*" -and $UninstallCommand -notlike "*quiet*") {
                $FinalCommand = $UninstallCommand -replace "(/X.*?)(\s|$)", "`$1 /quiet /norestart `$2"
            }

            # Executa o comando de desinstalação
            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable "cmd.exe" `
                -Arguments "/c $FinalCommand" `
                -TimeoutSeconds $TimeoutSeconds

            if ($Result.Success -or $Result.ExitCode -eq 0 -or $Result.ExitCode -eq 1605) {
                Write-Log `
                    -Level Info `
                    -Message "Software uninstalled successfully on $ComputerName"

                return [PSCustomObject]@{
                    Success        = $true
                    ComputerName   = $ComputerName
                    UninstallCmd   = $FinalCommand
                    ExitCode       = $Result.ExitCode
                    Output         = $Result.Output
                    Duration       = $Result.DurationMS
                    Timestamp      = Get-Date
                }
            }
            else {
                Write-Log `
                    -Level Error `
                    -Message "Uninstallation failed on $ComputerName with exit code: $($Result.ExitCode)"

                return [PSCustomObject]@{
                    Success        = $false
                    ComputerName   = $ComputerName
                    UninstallCmd   = $FinalCommand
                    ExitCode       = $Result.ExitCode
                    Error          = $Result.Error
                    Output         = $Result.Output
                    Duration       = $Result.DurationMS
                    Timestamp      = Get-Date
                }
            }
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error uninstalling software on $ComputerName`: $($_.Exception.Message)"

            return [PSCustomObject]@{
                Success        = $false
                ComputerName   = $ComputerName
                UninstallCmd   = $UninstallCommand
                Error          = $_.Exception.Message
                Timestamp      = Get-Date
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
    'Get-InstalledSoftware'
    'Get-SoftwareUninstallCommand'
    'Uninstall-RemoteSoftware'
)