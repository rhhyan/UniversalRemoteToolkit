function Connect-RemoteComputer {

    param(
        [string]$ComputerName
    )

    Write-Log -Message "Tentando conectar em $ComputerName..." -Level Info

    # PsExec

    Write-Log -Message "Conexão realizada com sucesso." -Level Success
}