<#
    Module: Logger.psm1

    start logs URT
#>

function Remove-OldLogFiles {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogsPath,

        [Parameter(Mandatory)]
        [int]$RetentionDays
    )

    process {
        try {
            $CutoffDate = (Get-Date).AddDays(-$RetentionDays)

            $OldLogFiles = Get-ChildItem `
                -Path $LogsPath `
                -Filter "*.log" `
                -File `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $CutoffDate }

            foreach ($LogFile in $OldLogFiles) {
                Remove-Item -Path $LogFile.FullName -Force -ErrorAction SilentlyContinue
            }

            return @($OldLogFiles).Count
        }
        catch {
            Write-Verbose "Falha ao rotacionar logs antigos: $($_.Exception.Message)"
            return 0
        }
    }
}

function Start-Log {

    [CmdletBinding()]
    param()

    try {

        # Caminho da pasta Logs
        $LogsPath = Join-Path (
            Split-Path -Parent (
                Split-Path -Parent $PSScriptRoot
            )
        ) "Logs"

        # Cria a pasta caso não exista
        if (-not (Test-Path $LogsPath)) {
            New-Item -ItemType Directory -Path $LogsPath -Force | Out-Null
        }

        # Remove logs além do período de retenção configurado
        $RetentionDays = 30

        try {
            $Config = Get-ToolkitConfig

            if ($Config.Logs.RetentionDays) {
                $RetentionDays = $Config.Logs.RetentionDays
            }
        }
        catch {
            Write-Verbose "Não foi possível ler RetentionDays da configuração. Usando padrão: $RetentionDays dias."
        }

        $RemovedCount = Remove-OldLogFiles `
            -LogsPath $LogsPath `
            -RetentionDays $RetentionDays

        # Nome do arquivo
        $Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $LogFileName = "URT_$Timestamp.log"

        # Caminho completo
        $LogFilePath = Join-Path $LogsPath $LogFileName

        # Cria o arquivo
        New-Item -ItemType File -Path $LogFilePath -Force | Out-Null

        # Guarda informações da sessão
        $script:LogSession = @{
            StartedAt = Get-Date
            LogFile   = $LogFilePath
        }

        if ($RemovedCount -gt 0) {
            Write-Log `
                -Level Info `
                -Message "Rotação de logs: $RemovedCount arquivo(s) com mais de $RetentionDays dia(s) removido(s)."
        }

        Write-Verbose "Sessão de log iniciada."

    }
    catch {

        throw "Não foi possível iniciar o Logger.`n$_"

    }

}

function Format-LogMessage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Mensagem,

        [Parameter(Mandatory = $true)]
        [string]$Nivel
    )

    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    # Retorna a string formatada (o PowerShell retorna o output automaticamente)
    "[$Timestamp] [$($Nivel.ToUpper())] $Mensagem"
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Debug','Info','Success','Warning','Error')]
        [string]$Level = 'Info'
    )

    process {

        # Verifica se o logger foi iniciado
        if (-not $script:LogSession) {
            throw "Sessão de log não iniciada. Execute Start-Log antes."
        }

        # Monta a mensagem formatada
        $FormattedMessage = Format-LogMessage `
            -Mensagem $Message `
            -Nivel $Level

        # Escreve no arquivo
        Add-Content `
            -Path $script:LogSession.LogFile `
            -Value $FormattedMessage `
            -Encoding UTF8

        # Exibe no console
        switch ($Level) {

            'Debug' {
                Write-Host $FormattedMessage -ForegroundColor DarkGray
            }

            'Info' {
                Write-Host $FormattedMessage -ForegroundColor Cyan
            }

            'Success' {
                Write-Host $FormattedMessage -ForegroundColor Green
            }

            'Warning' {
                Write-Host $FormattedMessage -ForegroundColor Yellow
            }

            'Error' {
                Write-Host $FormattedMessage -ForegroundColor Red
            }

            default {
                Write-Host $FormattedMessage
            }
        }
    }
}


function Stop-Log {

    [CmdletBinding()]
    param()

    process {

        if (-not $script:LogSession) {
            return
        }

        $Duration = (Get-Date) - $script:LogSession.StartedAt

        $FormattedDuration = "{0:00}:{1:00}:{2:00}" -f `
            $Duration.Hours,
            $Duration.Minutes,
            $Duration.Seconds

        Write-Log `
            -Level Info `
            -Message "Sessão encerrada. Tempo total: $Duration"

        $script:LogSession = $null
    }

}

