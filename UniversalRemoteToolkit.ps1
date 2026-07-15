$Config = Get-ToolkitConfig

if ($null -eq $Config) {
    Write-Host "Não foi possível carregar as configurações. Encerrando." -ForegroundColor Red
    exit 1
}

# segue o fluxo normal usando $Config...