<#
    Module: Config.psm1

    Responsável por carregar e validar
    as configurações do URT.
#>


function Get-ToolkitConfig {
    # Modules\Config.psm1 -> sobe um nível pra chegar na raiz UTR\
    $ProjectRoot = Split-Path -Parent $PSScriptRoot

    $ConfigFile = Join-Path $ProjectRoot "Config\Settings.json"

    if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile -Raw | ConvertFrom-Json
    } else {
        throw "Arquivo de configuração não encontrado: $ConfigFile"
    }
}