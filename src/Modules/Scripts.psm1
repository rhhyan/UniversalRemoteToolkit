# ============================================================
# Universal Remote Toolkit
# Module: Scripts
# Description: Catalogo e execucao remota de scripts de manutencao
#              (Otimizacao do Windows, Ativacao Windows/Office)
# ============================================================

# ============================================================
# CONSTANTS
# ============================================================

# Os .ps1 ficam em Modules\Scripts, ao lado deste modulo
$SCRIPTS_LOCAL_PATH = Join-Path $PSScriptRoot 'Scripts'

$Config = Get-ToolkitConfig

$REMOTE_TEMP_PATH = if ($Config.Software.RemoteTempPath) { $Config.Software.RemoteTempPath } else { 'C:\script_temp' }
$DEFAULT_KMS_HOST = if ($Config.Scripts.KmsHost) { $Config.Scripts.KmsHost } else { 'kmspw01.oi.corp.net' }

# Catalogo: adicionar novos scripts aqui
$SCRIPT_CATALOG = [ordered]@{
    'Otimizacao' = @{
        File           = 'Otimizacao.ps1'
        Description    = 'Otimizacao do Windows'
        TimeoutSeconds = 3600
    }
    'Ativacao' = @{
        File           = 'Ativacao.ps1'
        Description    = 'Ativar Windows/Office (KMS)'
        TimeoutSeconds = 300
    }
}

# ============================================================
# GET SCRIPT CATALOG
# ============================================================

<#
.SYNOPSIS
    Lists the scripts available in the toolkit Scripts folder.

.OUTPUTS
    System.Object[]
#>
function Get-ToolkitScript {
    [CmdletBinding()]
    param()

    process {
        foreach ($Key in $SCRIPT_CATALOG.Keys) {
            $Entry = $SCRIPT_CATALOG[$Key]
            $Path  = Join-Path $SCRIPTS_LOCAL_PATH $Entry.File

            [PSCustomObject]@{
                Name           = $Key
                Description    = $Entry.Description
                FileName       = $Entry.File
                LocalPath      = $Path
                Available      = (Test-Path -Path $Path -PathType Leaf)
                TimeoutSeconds = $Entry.TimeoutSeconds
            }
        }
    }
}

# ============================================================
# COPY SCRIPT TO REMOTE
# ============================================================

<#
.SYNOPSIS
    Copies a toolkit script to the remote temp folder (Software.RemoteTempPath).

.EXAMPLE
    Copy-ScriptToRemote -ComputerName "PC-001" -ScriptPath ".\Scripts\Otimizacao.ps1"
#>
function Copy-ScriptToRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    process {
        try {
            if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
                throw "Script not found: $ScriptPath"
            }

            # C:\script_temp -> \\PC\C$\script_temp
            $HostName   = $ComputerName.TrimStart('\')
            $FileName   = Split-Path -Leaf $ScriptPath
            $RemoteDir  = "\\$HostName\$($REMOTE_TEMP_PATH.Substring(0, 1))`$\$($REMOTE_TEMP_PATH.Substring(3))"
            $RemoteFile = Join-Path $RemoteDir $FileName

            if (-not (Test-Path -Path $RemoteDir)) {
                New-Item -ItemType Directory -Path $RemoteDir -Force -ErrorAction Stop | Out-Null
                Write-Log -Level Info -Message "Created remote directory: $RemoteDir"
            }

            Copy-Item -Path $ScriptPath -Destination $RemoteFile -Force -ErrorAction Stop

            Write-Log -Level Info -Message "Script copied to $RemoteFile"

            [PSCustomObject]@{
                Success    = $true
                RemoteUnc  = $RemoteFile
                RemotePath = Join-Path $REMOTE_TEMP_PATH $FileName
                Error      = $null
            }
        }
        catch {
            Write-Log -Level Error -Message "Error copying script to $ComputerName`: $($_.Exception.Message)"

            [PSCustomObject]@{
                Success    = $false
                RemoteUnc  = $null
                RemotePath = $null
                Error      = $_.Exception.Message
            }
        }
    }
}

# ============================================================
# INVOKE REMOTE SCRIPT (copy -> execute -> cleanup)
# ============================================================

<#
.SYNOPSIS
    Copies a catalog script to the remote computer, runs it via PsExec
    and removes the copy afterwards.

.PARAMETER ScriptName
    Catalog key (Otimizacao, Ativacao).

.PARAMETER Arguments
    Arguments passed to the remote .ps1 (e.g. "-Action Debloat").

.EXAMPLE
    Invoke-RemoteToolkitScript -ComputerName "PC-001" -ScriptName Ativacao -Arguments "-Target Status"
#>
function Invoke-RemoteToolkitScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName,

        [Parameter()]
        [string]$Arguments = '',

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds
    )

    process {
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $Copy = $null

        try {
            if (-not $SCRIPT_CATALOG.Contains($ScriptName)) {
                throw "Script '$ScriptName' is not in the catalog."
            }

            $Entry = $SCRIPT_CATALOG[$ScriptName]
            if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) {
                $TimeoutSeconds = $Entry.TimeoutSeconds
            }

            Write-Log -Level Info -Message "Running script '$ScriptName' ($Arguments) on $ComputerName"

            if (-not (Test-ComputerReachable -ComputerName $ComputerName)) {
                throw "Computer '$ComputerName' is not reachable."
            }

            $Copy = Copy-ScriptToRemote `
                -ComputerName $ComputerName `
                -ScriptPath (Join-Path $SCRIPTS_LOCAL_PATH $Entry.File)

            if (-not $Copy.Success) {
                throw "Copy failed: $($Copy.Error)"
            }

            $Result = Invoke-PsExecCommand `
                -ComputerName $ComputerName `
                -Executable 'powershell.exe' `
                -Arguments "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$($Copy.RemotePath)`" $Arguments" `
                -TimeoutSeconds $TimeoutSeconds

            # Exit 2 = sucesso parcial (alguns itens falharam)
            $Status = switch ($Result.ExitCode) {
                0       { 'Success' }
                2       { 'Partial' }
                default { if ($Result.TimedOut) { 'Timeout' } else { 'Failed' } }
            }

            Write-Log `
                -Level $(if ($Status -eq 'Success') { 'Success' } elseif ($Status -eq 'Partial') { 'Warning' } else { 'Error' }) `
                -Message "Script '$ScriptName' on $ComputerName finished: $Status (exit $($Result.ExitCode))"

            [PSCustomObject]@{
                Success    = ($Status -in 'Success', 'Partial')
                Status     = $Status
                Computer   = $ComputerName
                Script     = $ScriptName
                Arguments  = $Arguments
                ExitCode   = $Result.ExitCode
                Output     = $Result.Output
                Error      = $Result.Error
                DurationMS = $Stopwatch.ElapsedMilliseconds
                Timestamp  = Get-Date
            }
        }
        catch {
            Write-Log -Level Error -Message "Script '$ScriptName' error on $ComputerName`: $($_.Exception.Message)"

            [PSCustomObject]@{
                Success    = $false
                Status     = 'Failed'
                Computer   = $ComputerName
                Script     = $ScriptName
                Arguments  = $Arguments
                ExitCode   = $null
                Output     = $null
                Error      = $_.Exception.Message
                DurationMS = $Stopwatch.ElapsedMilliseconds
                Timestamp  = Get-Date
            }
        }
        finally {
            $Stopwatch.Stop()

            if ($Copy -and $Copy.Success -and $Copy.RemoteUnc) {
                Remove-Item -Path $Copy.RemoteUnc -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ============================================================
# WRAPPERS
# ============================================================

<#
.SYNOPSIS
    Runs one Windows optimization action on a remote computer.

.EXAMPLE
    Invoke-WindowsOptimization -ComputerName "PC-001" -Action CleanProfiles -KeepProfiles "TH123456","TH654321"
#>
function Invoke-WindowsOptimization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateSet('CleanProfiles', 'Debloat', 'RepairImage', 'VisualEffects', 'DisableServices')]
        [string]$Action,

        [Parameter()]
        [string[]]$KeepProfiles = @(),

        [Parameter()]
        [switch]$SkipSfc
    )

    process {
        $Arguments = "-Action $Action"

        if ($Action -eq 'CleanProfiles') {
            $Clean = @($KeepProfiles | ForEach-Object { $_ -split '[,; ]+' } |
                Where-Object { $_ -match '^[A-Za-z0-9._-]+$' })

            if ($Clean.Count -gt 0) {
                $Arguments += " -KeepProfiles `"$($Clean -join ',')`""
            }
            if ($SkipSfc) {
                $Arguments += ' -SkipSfc'
            }
        }

        Invoke-RemoteToolkitScript `
            -ComputerName $ComputerName `
            -ScriptName 'Otimizacao' `
            -Arguments $Arguments
    }
}

<#
.SYNOPSIS
    Activates Windows or Office against the corporate KMS, or shows status.

.EXAMPLE
    Invoke-LicenseActivation -ComputerName "PC-001" -Target Office
#>
function Invoke-LicenseActivation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateSet('Office', 'Windows', 'Status')]
        [string]$Target,

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9.-]+(:\d+)?$')]
        [string]$KmsHost = $DEFAULT_KMS_HOST
    )

    process {
        Invoke-RemoteToolkitScript `
            -ComputerName $ComputerName `
            -ScriptName 'Ativacao' `
            -Arguments "-Target $Target -KmsHost $KmsHost"
    }
}

# ============================================================
# EXPORT MODULE MEMBERS
# ============================================================

Export-ModuleMember -Function @(
    'Get-ToolkitScript'
    'Copy-ScriptToRemote'
    'Invoke-RemoteToolkitScript'
    'Invoke-WindowsOptimization'
    'Invoke-LicenseActivation'
)
