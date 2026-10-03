<#
    Module: Config.psm1

    Responsável por carregar e validar
    as configurações do URT.
#>

# Depende de: (nenhum)

# Configuração lida do disco na primeira chamada (Get-ToolkitConfig -Force relê)
$script:ConfigCache = $null


function Get-ToolkitConfig {
    <#
    .SYNOPSIS
        Retorna o conteúdo do Settings.json.

    .DESCRIPTION
        O arquivo é lido uma vez e mantido em cache. Use -Force para
        reler depois de alterar o Settings.json.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )

    if ($script:ConfigCache -and -not $Force) {
        return $script:ConfigCache
    }

    # O Settings.json fica em src\Config: Modules\Config.psm1 -> sobe um
    # nível até src\. Não confundir com Get-ToolkitRoot (raiz do projeto,
    # base dos caminhos relativos dentro do Settings.json).
    $SourceRoot = Split-Path -Parent $PSScriptRoot

    $ConfigFile = Join-Path $SourceRoot "Config\Settings.json"

    if (-not (Test-Path $ConfigFile)) {
        throw "Arquivo de configuração não encontrado: $ConfigFile"
    }

    $script:ConfigCache = Get-Content $ConfigFile -Raw | ConvertFrom-Json

    return $script:ConfigCache
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


# Funções não listadas aqui são internas do módulo
Export-ModuleMember -Function @(
    'Get-ToolkitConfig'
    'Get-ToolkitRoot'
    'Resolve-ToolkitPath'
)
