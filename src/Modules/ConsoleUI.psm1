# ====================================================
# ConsoleUI.psm1 - Sistema de Menu e Interface
# ====================================================

function Format-CenteredText {
    <#
    .SYNOPSIS
        Centraliza um texto dentro de uma largura especificada
    
    .PARAMETER Text
        Texto a ser centralizado
    
    .PARAMETER Width
        Largura total para centralização
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$Width
    )

    if ($Text.Length -ge $Width) {
        return $Text
    }

    $LeftPadding = [math]::Floor(($Width - $Text.Length) / 2)

    return (" " * $LeftPadding) + $Text
}

function Show-Banner {
    <#
    .SYNOPSIS
        Exibe um banner formatado no início da aplicação
    
    .PARAMETER Title
        Título principal do banner
    
    .PARAMETER Subtitle
        Subtítulo opcional
    
    .PARAMETER Width
        Largura do banner em caracteres (padrão: 60, válido: 20-200)
    
    .EXAMPLE
        Show-Banner -Title "Universal Remote Toolkit" -Subtitle "v1.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        
        [Parameter(Mandatory = $false)]
        [string]$Subtitle = "",
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 200)]
        [int]$Width = 60
    )
    
    $border = "=" * $Width
    
    Write-Host "`n$border" -ForegroundColor Cyan
    Write-Host (Format-CenteredText -Text $Title -Width $Width) -ForegroundColor Yellow
    
    if ($Subtitle) {
        Write-Host (Format-CenteredText -Text $Subtitle -Width $Width) -ForegroundColor Gray
    }
    
    Write-Host "$border`n" -ForegroundColor Cyan
}

function Show-MainMenu {
    <#
    .SYNOPSIS
        Exibe o menu principal com opções formatadas
    
    .PARAMETER MenuItems
        Hashtable com [número] = "descrição"
    
    .PARAMETER Description
        Descrição do menu (opcional)
    
    .EXAMPLE
        $menu = @{ 1 = "Executar comando"; 2 = "Listar máquinas"; 0 = "Sair" }
        Show-MainMenu -MenuItems $menu
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$MenuItems,
        
        [Parameter(Mandatory = $false)]
        [string]$Description = "Selecione uma opção:"
    )
    
    Write-Host $Description -ForegroundColor Magenta
    Write-Host ""
    
    # Menus [ordered] mantêm a ordem definida (ex: "0 - Sair" por último);
    # hashtables comuns não têm ordem garantida, então são ordenadas.
    $Entries = $MenuItems.GetEnumerator()

    if ($MenuItems -isnot [System.Collections.Specialized.OrderedDictionary]) {
        $Entries = $Entries | Sort-Object -Property Name
    }

    $Entries | ForEach-Object {
        Write-Host "  [$($_.Name)] - $($_.Value)" -ForegroundColor Green
    }
    
    Write-Host ""
}

function Read-MenuSelection {
    <#
    .SYNOPSIS
        Lê e valida a seleção do usuário no menu
    
    .PARAMETER ValidOptions
        Array com opções válidas (ex: @(0, 1, 2, 3))
    
    .PARAMETER Prompt
        Mensagem de prompt customizada
    
    .DESCRIPTION
        Realiza validação rigorosa da entrada do usuário.
        Verifica se é um número inteiro válido e se está na lista de opções permitidas.
    
    .EXAMPLE
        $choice = Read-MenuSelection -ValidOptions @(0, 1, 2, 3)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ValidOptions,
        
        [Parameter(Mandatory = $false)]
        [string]$Prompt = "Digite sua escolha"
    )
    
    do {
        Write-Host "$Prompt : " -ForegroundColor Yellow -NoNewline
        $Selection = Read-Host
        
        # Validar conversão para inteiro usando variável temporária
        $SelectionInt = 0
        if (-not [int]::TryParse($Selection, [ref]$SelectionInt)) {
            Write-Host "❌ Entrada inválida. Digite um número." -ForegroundColor Red
            continue
        }
        
        # Validar se está nas opções permitidas
        if ($SelectionInt -in $ValidOptions) {
            return $SelectionInt
        } else {
            Write-Host "❌ Opção inválida. Tente novamente." -ForegroundColor Red
        }
        
    } while ($true)
}

function Read-ItemSelection {
    <#
    .SYNOPSIS
        Permite ao usuário escolher um item de uma lista numerada

    .PARAMETER Items
        Itens disponíveis para seleção

    .PARAMETER DisplayProperty
        Scriptblock que gera o texto exibido para cada item

    .PARAMETER Title
        Texto exibido acima da lista

    .DESCRIPTION
        Com um único item, retorna-o diretamente sem perguntar.
        Retorna $null se a lista estiver vazia ou se o usuário escolher 0 (cancelar).

    .EXAMPLE
        $App = Read-ItemSelection -Items $Apps -DisplayProperty { "$($_.Name) ($($_.Version))" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [Parameter(Mandatory = $false)]
        [scriptblock]$DisplayProperty = { "$_" },

        [Parameter(Mandatory = $false)]
        [string]$Title = "Mais de um resultado encontrado:"
    )

    if ($Items.Count -eq 0) {
        return $null
    }

    if ($Items.Count -eq 1) {
        return $Items[0]
    }

    Write-Host ""
    Write-Host $Title -ForegroundColor Magenta
    Write-Host ""

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $Label = $Items[$i] | ForEach-Object $DisplayProperty
        Write-Host "  [$($i + 1)] - $Label" -ForegroundColor Green
    }

    Write-Host "  [0] - Cancelar" -ForegroundColor Green
    Write-Host ""

    $Choice = Read-MenuSelection -ValidOptions (0..$Items.Count)

    if ($Choice -eq 0) {
        return $null
    }

    return $Items[$Choice - 1]
}

function Show-ExecutionResult {
    <#
    .SYNOPSIS
        Exibe o resultado de uma execução com formatação
    
    .PARAMETER Status
        Status da execução: 'Success', 'Error', 'Warning', 'Info'
    
    .PARAMETER Message
        Mensagem a ser exibida
    
    .PARAMETER Details
        Detalhes adicionais (opcional)
    
    .PARAMETER Pause
        Se $true, aguarda Enter antes de continuar (padrão: $true)
    
    .DESCRIPTION
        Exibe resultado com ícone e cor apropriados.
        
        Nota: Futuramente, esta função pode ser expandida para aceitar
        objetos PSCustomObject do módulo Execution.psm1, permitindo
        uma integração automática entre camadas.
    
    .EXAMPLE
        Show-ExecutionResult -Status Success -Message "Comando executado" -Details "3 máquinas atualizadas"
    
    .EXAMPLE
        Show-ExecutionResult -Status Error -Message "Falha na conexão" -Pause $false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Error', 'Warning', 'Info')]
        [string]$Status,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Details = "",
        
        [Parameter(Mandatory = $false)]
        [bool]$Pause = $true
    )
    
    $IconMap = @{
        'Success' = '✓'
        'Error'   = '✗'
        'Warning' = '⚠'
        'Info'    = 'ℹ'
    }
    
    $ColorMap = @{
        'Success' = 'Green'
        'Error'   = 'Red'
        'Warning' = 'Yellow'
        'Info'    = 'Cyan'
    }
    
    Write-Host "`n$($IconMap[$Status]) $Message" -ForegroundColor $ColorMap[$Status]
    
    if ($Details) {
        # Indenta todas as linhas, não apenas a primeira
        $Details -split "\r?\n" | ForEach-Object {
            Write-Host "   $_" -ForegroundColor Gray
        }
    }

    if ($Pause) {
        Write-Host ""
        # Out-Null evita que o texto digitado vaze para o pipeline
        Read-Host "Pressione Enter para continuar" | Out-Null
    }
    
    Write-Host ""
}