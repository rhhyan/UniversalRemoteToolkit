# ============================================================
# Universal Remote Toolkit
# Module: Software Management
# Description: Universal software installation and uninstallation
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

# Tempo máximo aguardando o programa sumir do registro após a desinstalação
$VERIFY_TIMEOUT = if ($Config.Software.UninstallVerifyTimeout) { [int]$Config.Software.UninstallVerifyTimeout } else { 60 }
$VERIFY_INTERVAL = 5

$GUID_PATTERN = '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'

# Códigos de saída do Windows Installer que indicam sucesso
#   0    = sucesso
#   3010 = sucesso, reinicialização necessária
#   1641 = sucesso, reinicialização iniciada
$SUCCESS_EXIT_CODES = @(0, 3010, 1641)
$REBOOT_EXIT_CODES = @(3010, 1641)

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

            $DriveLetter = $TEMP_SCRIPT_PATH.Substring(0, 1)
            $PathWithoutDrive = $TEMP_SCRIPT_PATH.Substring(3)
            $RemotePath = "\\$ComputerName\$DriveLetter`$\$PathWithoutDrive"

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
                LocalPathOnly = Join-Path $TEMP_SCRIPT_PATH $InstallerName
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
        [int]$TimeoutSeconds = $DEFAULT_INSTALL_TIMEOUT
    )

    process {
        try {
            Write-Log `
                -Level Info `
                -Message "Installing software on $ComputerName from $InstallerPath"

            # Determina o tipo de instalador e argumentos padrão
            $Extension = [System.IO.Path]::GetExtension($InstallerPath).ToLower()

            # Chama o executável diretamente (sem "cmd /c") e com o caminho
            # entre aspas, para suportar nomes de arquivo com espaços.
            switch ($Extension) {
                ".msi" {
                    $Executable = "msiexec.exe"

                    if ([string]::IsNullOrWhiteSpace($Arguments)) {
                        $Arguments = "/quiet /norestart"
                    }

                    $FinalArguments = "/i `"$InstallerPath`" $Arguments"
                }

                ".ps1" {
                    $Executable = "powershell.exe"
                    $FinalArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$InstallerPath`" $Arguments"
                }

                ".exe" {
                    $Executable = $InstallerPath
                    $FinalArguments = $Arguments
                }

                default {
                    throw "Unsupported installer type: $Extension"
                }
            }

            # Executa via PsExec
            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable $Executable `
                -Arguments $FinalArguments.Trim() `
                -TimeoutSeconds $TimeoutSeconds

            if (-not $Result.TimedOut -and $Result.ExitCode -in $SUCCESS_EXIT_CODES) {
                Write-Log `
                    -Level Info `
                    -Message "Software installed successfully on $ComputerName"

                return [PSCustomObject]@{
                    Success        = $true
                    RebootRequired = ($Result.ExitCode -in $REBOOT_EXIT_CODES)
                    ComputerName   = $ComputerName
                    InstallerPath  = $InstallerPath
                    ExitCode       = $Result.ExitCode
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

            # Script executado remotamente (aspas simples: nada é expandido
            # localmente). Lê HKLM (64/32 bits) e os perfis carregados em
            # HKEY_USERS, para enxergar também instalações por usuário.
            $QueryScript = @'
try {
    $Sources = @(
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Machine' },
        @{ Path = 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Machine (x86)' }
    )
    Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } |
        ForEach-Object {
            $Sid = $_.PSChildName
            $User = try { ([System.Security.Principal.SecurityIdentifier]$Sid).Translate([System.Security.Principal.NTAccount]).Value } catch { $Sid }
            $Sources += @{ Path = "Registry::HKEY_USERS\$Sid\Software\Microsoft\Windows\CurrentVersion\Uninstall"; Scope = "User ($User)" }
        }
    $Apps = @()
    foreach ($Source in $Sources) {
        if (-not (Test-Path $Source.Path)) { continue }
        Get-ChildItem $Source.Path -ErrorAction SilentlyContinue | ForEach-Object {
            $Name = $_.GetValue('DisplayName')
            if (-not $Name -or $_.GetValue('SystemComponent') -eq 1 -or $_.GetValue('ParentKeyName')) { return }
            $Apps += [PSCustomObject]@{
                Name                 = $Name
                Version              = $_.GetValue('DisplayVersion')
                Publisher            = $_.GetValue('Publisher')
                Scope                = $Source.Scope
                KeyName              = $_.PSChildName
                WindowsInstaller     = $_.GetValue('WindowsInstaller')
                InstallLocation      = $_.GetValue('InstallLocation')
                UninstallString      = $_.GetValue('UninstallString')
                QuietUninstallString = $_.GetValue('QuietUninstallString')
                RegistryPath         = $_.PSPath
            }
        }
    }
    if ($Apps.Count -gt 0) { $Apps | Sort-Object Name | ConvertTo-Json -Depth 3 } else { '[]' }
} catch {
    '[]'
}
'@

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
                    # Procura o primeiro [ ou { (um único programa vira um objeto
                    # JSON, e o nome dele pode conter colchetes)
                    $JsonStart = $OutputTrim.IndexOfAny([char[]]'[{')

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
                    if ($null -eq $InstalledApps) {
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
# RESOLVE UNINSTALL COMMAND
# ============================================================

<#
.SYNOPSIS
    Splits a registry command line into executable and arguments.

.DESCRIPTION
    Handles quoted paths ("C:\Program Files\App\unins000.exe" /x) and
    unquoted paths containing spaces (C:\Program Files\App\uninst.exe /S).
#>
function Split-UninstallCommandLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandLine
    )

    $Text = $CommandLine.Trim()

    if ($Text.StartsWith('"')) {
        $End = $Text.IndexOf('"', 1)

        if ($End -gt 0) {
            return [PSCustomObject]@{
                Executable = $Text.Substring(1, $End - 1)
                Arguments  = $Text.Substring($End + 1).Trim()
            }
        }

        $Text = $Text.Trim('"')
    }

    # Caminho sem aspas: o menor prefixo terminado em .exe seguido de espaço
    $Match = [regex]::Match(
        $Text,
        '^(.+?\.(?:exe|cmd|bat|com))(?:\s+(.*))?$',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($Match.Success) {
        return [PSCustomObject]@{
            Executable = $Match.Groups[1].Value.Trim()
            Arguments  = $Match.Groups[2].Value.Trim()
        }
    }

    $Parts = $Text -split '\s+', 2

    [PSCustomObject]@{
        Executable = $Parts[0]
        Arguments  = if ($Parts.Count -gt 1) { $Parts[1] } else { "" }
    }
}

<#
.SYNOPSIS
    Builds a silent uninstall command for an installed program.

.DESCRIPTION
    Identifies the installer technology from the registry entry
    returned by Get-InstalledSoftware and adds the matching silent
    switches:

      MSI              msiexec /x {GUID} /qn /norestart
      QuietUninstall   vendor-provided silent command, used as is
      Inno Setup       /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
      NSIS             /S
      Chromium         --force-uninstall (Chrome, Edge, ...)
      Squirrel         -s (Teams classic, Discord, Slack, ...)
      InstallShield    no silent mode without a response file
      Generic          command as registered (may show UI)

    PsExec runs without a desktop session, so an uninstaller that waits
    for user input hangs until the timeout. Silent reports whether a
    silent switch is known for this uninstaller.

.PARAMETER Software
    Entry returned by Get-InstalledSoftware (or any object with an
    UninstallString property).

.EXAMPLE
    Get-InstalledSoftware -ComputerName "PC-001" |
        Where-Object Name -like "*7-Zip*" |
        Resolve-UninstallCommand
#>
function Resolve-UninstallCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object]$Software
    )

    process {
        $UninstallString = [string]$Software.UninstallString
        $QuietString = [string]$Software.QuietUninstallString
        $KeyName = [string]$Software.KeyName

        $NewPlan = {
            param($Type, $Executable, $Arguments, $Silent)

            $Arguments = ([string]$Arguments).Trim()
            $Display = if ($Executable -match '\s') { "`"$Executable`"" } else { $Executable }

            [PSCustomObject]@{
                InstallerType = $Type
                Executable    = $Executable
                Arguments     = $Arguments
                Silent        = $Silent
                CommandLine   = "$Display $Arguments".Trim()
            }
        }

        # MSI: a chave do registro é o ProductCode; /I{GUID} abriria a tela
        # de "modificar", então sempre usa /x silencioso.
        $ProductCode = $null

        if ($KeyName -match "^$GUID_PATTERN$" -and ($Software.WindowsInstaller -eq 1 -or $UninstallString -match 'msiexec')) {
            $ProductCode = $KeyName
        }
        elseif ($UninstallString -match 'msiexec') {
            $GuidMatch = [regex]::Match($UninstallString, $GUID_PATTERN)

            if ($GuidMatch.Success) {
                $ProductCode = $GuidMatch.Value
            }
        }

        if ($ProductCode) {
            return & $NewPlan 'MSI' 'msiexec.exe' "/x $ProductCode /qn /norestart" $true
        }

        if (-not [string]::IsNullOrWhiteSpace($QuietString)) {
            $Parts = Split-UninstallCommandLine -CommandLine $QuietString
            return & $NewPlan 'QuietUninstallString' $Parts.Executable $Parts.Arguments $true
        }

        if ([string]::IsNullOrWhiteSpace($UninstallString)) {
            throw "No uninstall command registered for '$($Software.Name)'."
        }

        $Parts = Split-UninstallCommandLine -CommandLine $UninstallString
        $Executable = $Parts.Executable
        $Arguments = $Parts.Arguments

        # Path.GetFileName não separa "\" fora do Windows; divide manualmente
        $FileName = ($Executable -split '[\\/]')[-1]

        if ($KeyName -match '_is1$' -or $FileName -match '^unins\d{3}\.exe$') {
            if ($Arguments -notmatch '/VERYSILENT') {
                $Arguments += " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
            }

            return & $NewPlan 'Inno Setup' $Executable $Arguments $true
        }

        if ($FileName -match '^update\.exe$' -and $Arguments -match '--uninstall') {
            if ($Arguments -notmatch '(^|\s)-s(\s|$)') {
                $Arguments += " -s"
            }

            return & $NewPlan 'Squirrel' $Executable $Arguments $true
        }

        if ($Arguments -match '--uninstall') {
            if ($Arguments -notmatch '--force-uninstall') {
                $Arguments += " --force-uninstall"
            }

            return & $NewPlan 'Chromium' $Executable $Arguments $true
        }

        if ($Executable -match 'InstallShield Installation Information' -or $Arguments -match '-runfromtemp|-removeonly') {
            return & $NewPlan 'InstallShield' $Executable $Arguments $false
        }

        if ($FileName -match '^(uninst|uninstall)[^\\/]*\.exe$') {
            if ($Arguments -notmatch '(^|\s)/S(\s|$)') {
                $Arguments += " /S"
            }

            return & $NewPlan 'NSIS' $Executable $Arguments $true
        }

        & $NewPlan 'Generic' $Executable $Arguments $false
    }
}

# ============================================================
# TEST REMOTE SOFTWARE INSTALLED
# ============================================================

<#
.SYNOPSIS
    Checks whether a program's uninstall registry key still exists.

.OUTPUTS
    System.Boolean
    $true if present, $false if removed, $null if the check failed.
#>
function Test-RemoteSoftwareInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RegistryPath
    )

    $EscapedPath = $RegistryPath -replace "'", "''"
    $Script = "if (Test-Path -LiteralPath '$EscapedPath') { 'PRESENT' } else { 'ABSENT' }"

    $EncodedScript = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($Script)
    )

    $Result = Invoke-PsExecCommand `
        -ComputerName $ComputerName `
        -Executable "powershell.exe" `
        -Arguments "-NoProfile -NoLogo -ExecutionPolicy Bypass -EncodedCommand $EncodedScript"

    if ($Result.Output -match 'ABSENT') {
        return $false
    }

    if ($Result.Output -match 'PRESENT') {
        return $true
    }

    return $null
}

# ============================================================
# UNINSTALL SOFTWARE
# ============================================================

<#
.SYNOPSIS
    Uninstalls software from a remote computer.

.DESCRIPTION
    Resolves a silent uninstall command (see Resolve-UninstallCommand),
    executes it through PsExec and, when a registry entry is given,
    waits until the program disappears from the registry.

    Some uninstallers (NSIS, Squirrel) return immediately and keep
    working in the background, so the registry check is what decides
    success when -Software is used.

.PARAMETER ComputerName
    Name of the remote computer.

.PARAMETER Software
    Entry returned by Get-InstalledSoftware. Enables post-uninstall
    verification.

.PARAMETER UninstallCommand
    Raw uninstall command line. No verification is performed.

.PARAMETER Arguments
    Replaces the resolved arguments (for uninstallers whose silent
    switch is not detected automatically).

.PARAMETER TimeoutSeconds
    Maximum execution time in seconds (default: Software.DefaultUninstallTimeout).

.OUTPUTS
    System.Object
    Returns uninstallation result with status and details.

.EXAMPLE
    $App = Get-InstalledSoftware -ComputerName "PC-001" | Where-Object Name -like "*7-Zip*"
    Uninstall-RemoteSoftware -ComputerName "PC-001" -Software $App

.EXAMPLE
    Uninstall-RemoteSoftware -ComputerName "PC-001" -UninstallCommand "MsiExec.exe /X{GUID}"
#>
function Uninstall-RemoteSoftware {
    [CmdletBinding(DefaultParameterSetName = 'Software')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory, ParameterSetName = 'Software')]
        [ValidateNotNull()]
        [object]$Software,

        [Parameter(Mandatory, ParameterSetName = 'Command')]
        [ValidateNotNullOrEmpty()]
        [string]$UninstallCommand,

        [Parameter(Mandatory = $false)]
        [string]$Arguments = "",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = $DEFAULT_UNINSTALL_TIMEOUT
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Command') {
            $Software = [PSCustomObject]@{
                Name            = $UninstallCommand
                UninstallString = $UninstallCommand
            }
        }

        $SoftwareName = [string]$Software.Name
        $Plan = $null

        $NewResult = {
            param($Success, $Verified, $ExitCode, $ErrorMessage, $Output, $Duration, $RebootRequired)

            [PSCustomObject]@{
                Success         = $Success
                Verified        = $Verified
                RebootRequired  = [bool]$RebootRequired
                ComputerName    = $ComputerName
                SoftwareName    = $SoftwareName
                UninstallerType = $Plan.InstallerType
                UninstallCmd    = $Plan.CommandLine
                ExitCode        = $ExitCode
                Error           = $ErrorMessage
                Output          = $Output
                Duration        = $Duration
                Timestamp       = Get-Date
            }
        }

        try {
            $Plan = Resolve-UninstallCommand -Software $Software

            if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
                $Plan.Arguments = $Arguments.Trim()
                $Display = if ($Plan.Executable -match '\s') { "`"$($Plan.Executable)`"" } else { $Plan.Executable }
                $Plan.CommandLine = "$Display $($Plan.Arguments)"
            }

            Write-Log `
                -Level Info `
                -Message "Uninstalling '$SoftwareName' on $ComputerName [$($Plan.InstallerType)]: $($Plan.CommandLine)"

            if (-not $Plan.Silent -and [string]::IsNullOrWhiteSpace($Arguments)) {
                Write-Log `
                    -Level Warning `
                    -Message "No silent switch known for '$SoftwareName'; the uninstaller may wait for input until the timeout"
            }

            # Variáveis de ambiente (%ProgramFiles%...) só são expandidas pelo cmd.
            # As aspas externas extras são removidas pelo próprio cmd /c.
            if ($Plan.Executable -match '%') {
                $Executable = "cmd.exe"
                $FinalArguments = "/c `"`"$($Plan.Executable)`" $($Plan.Arguments)`""
            }
            else {
                $Executable = $Plan.Executable
                $FinalArguments = $Plan.Arguments
            }

            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable $Executable `
                -Arguments $FinalArguments `
                -TimeoutSeconds $TimeoutSeconds

            $Duration = $Result.DurationMS
            $RebootRequired = ($Result.ExitCode -in $REBOOT_EXIT_CODES)

            # 1605 = produto MSI não está instalado (já removido)
            $AcceptedCodes = $SUCCESS_EXIT_CODES
            if ($Plan.InstallerType -eq 'MSI') {
                $AcceptedCodes += 1605
            }

            $ExitOk = (-not $Result.TimedOut -and $Result.ExitCode -in $AcceptedCodes)

            if ($Result.TimedOut) {
                # O PsExec local foi encerrado, mas o desinstalador continua
                # rodando na máquina remota (provavelmente aguardando uma janela).
                if ($Plan.InstallerType -ne 'MSI') {
                    $ProcessName = ($Plan.Executable -split '[\\/]')[-1]

                    $null = Invoke-PsExecCommand `
                        -ComputerName $ComputerName `
                        -Executable "taskkill.exe" `
                        -Arguments "/f /t /im `"$ProcessName`"" `
                        -TimeoutSeconds 30
                }

                $Hint = if ($Plan.Silent) { "" } else { " The uninstaller probably opened a window; provide silent arguments and try again." }

                Write-Log `
                    -Level Error `
                    -Message "Uninstall of '$SoftwareName' timed out on $ComputerName after $TimeoutSeconds s"

                return & $NewResult $false $null $null "Uninstaller timed out after $TimeoutSeconds seconds.$Hint" $Result.Output $Duration $false
            }

            # Sem entrada de registro não há como verificar: confia no exit code
            if ([string]::IsNullOrWhiteSpace([string]$Software.RegistryPath)) {
                if ($ExitOk) {
                    Write-Log `
                        -Level Info `
                        -Message "Uninstall command completed on $ComputerName (not verified)"

                    return & $NewResult $true $null $Result.ExitCode $null $Result.Output $Duration $RebootRequired
                }

                Write-Log `
                    -Level Error `
                    -Message "Uninstall failed on $ComputerName with exit code: $($Result.ExitCode)"

                return & $NewResult $false $null $Result.ExitCode $Result.Error $Result.Output $Duration $false
            }

            # Verificação: aguarda a chave do programa sumir do registro
            Write-Log `
                -Level Info `
                -Message "Verifying removal of '$SoftwareName' on $ComputerName"

            $VerifyWatch = [System.Diagnostics.Stopwatch]::StartNew()

            do {
                $StillInstalled = Test-RemoteSoftwareInstalled `
                    -ComputerName $ComputerName `
                    -RegistryPath $Software.RegistryPath

                if ($StillInstalled -ne $true) {
                    break
                }

                # Se o desinstalador falhou, não adianta esperar
                if (-not $ExitOk) {
                    break
                }

                Start-Sleep -Seconds $VERIFY_INTERVAL
            } while ($VerifyWatch.Elapsed.TotalSeconds -lt $VERIFY_TIMEOUT)

            if ($StillInstalled -eq $false) {
                Write-Log `
                    -Level Info `
                    -Message "'$SoftwareName' uninstalled and verified on $ComputerName"

                return & $NewResult $true $true $Result.ExitCode $null $Result.Output $Duration $RebootRequired
            }

            if ($null -eq $StillInstalled) {
                $Message = "Could not verify removal (registry check failed)."

                Write-Log `
                    -Level Warning `
                    -Message "$Message Exit code: $($Result.ExitCode)"

                return & $NewResult $ExitOk $null $Result.ExitCode $(if (-not $ExitOk) { $Result.Error } else { $Message }) $Result.Output $Duration $RebootRequired
            }

            $Message = if ($ExitOk) {
                "Uninstaller reported success, but the program is still registered after $VERIFY_TIMEOUT seconds."
            }
            else {
                "Uninstaller failed with exit code $($Result.ExitCode). $($Result.Error)".Trim()
            }

            if ([string]$Software.Scope -like 'User*') {
                $Message += " This is a per-user installation; it may need to be removed while logged in as that user."
            }

            Write-Log `
                -Level Error `
                -Message "Uninstall of '$SoftwareName' failed on $ComputerName`: $Message"

            return & $NewResult $false $false $Result.ExitCode $Message $Result.Output $Duration $false
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Error uninstalling software on $ComputerName`: $($_.Exception.Message)"

            return & $NewResult $false $null $null $_.Exception.Message $null $null $false
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
    'Resolve-UninstallCommand'
    'Uninstall-RemoteSoftware'
)