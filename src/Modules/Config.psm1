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
    }
    else {
        throw "Arquivo de configuração não encontrado: $ConfigFile"
    }
}


function Get-ToolkitRoot {
    <#
    .SYNOPSIS
        Retorna a raiz do projeto (pasta que contém src, Bin, Logs).
    #>

    # Modules -> src -> raiz
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}


function Resolve-ToolkitPath {
    <#
    .SYNOPSIS
        Converte um caminho do Settings.json em caminho absoluto.

    .DESCRIPTION
        Caminhos relativos (ex: ".\Bin\PsExec.exe") são resolvidos a partir
        da raiz do projeto. Caminhos absolutos e UNC são mantidos.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    [System.IO.Path]::GetFullPath((Join-Path (Get-ToolkitRoot) $Path))
}
