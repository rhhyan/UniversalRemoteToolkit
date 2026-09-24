# ====================================================
# ConsoleUI.psm1 - Sistema de Menu e Interface
# ====================================================

# Os símbolos são montados a partir de code points porque o Windows
# PowerShell 5.1 lê arquivos UTF-8 sem BOM como ANSI e corromperia
# caracteres literais como ✓ ou ═.
$script:Glyph = @{
    TopLeft     = [string][char]0x2554   # ╔
    TopRight    = [string][char]0x2557   # ╗
    BottomLeft  = [string][char]0x255A   # ╚
    BottomRight = [string][char]0x255D   # ╝
    Horizontal  = [string][char]0x2550   # ═
    Vertical    = [string][char]0x2551   # ║
    Rule        = [string][char]0x2500   # ─
    Bullet      = [string][char]0x2022   # •
    Prompt      = [string][char]0x203A   # ›
    Success     = [string][char]0x2713   # ✓
    Error       = [string][char]0x2717   # ✗
    Warning     = '!'
    Info        = 'i'
    Running     = '*'
}

$script:StatusStyle = @{
    'Success' = @{ Icon = $script:Glyph.Success; Color = 'Green' }
    'Error'   = @{ Icon = $script:Glyph.Error;   Color = 'Red' }
    'Warning' = @{ Icon = $script:Glyph.Warning; Color = 'Yellow' }
    'Info'    = @{ Icon = $script:Glyph.Info;    Color = 'Cyan' }
    'Running' = @{ Icon = $script:Glyph.Running; Color = 'Cyan' }
}

$script:DefaultWidth = 64

function Initialize-ConsoleUI {
    <#
    .SYNOPSIS
        Prepara o console para a interface (encoding e título da janela)

    .PARAMETER Title
        Título da janela do console

    .DESCRIPTION
        Força UTF-8 na saída para que bordas e ícones sejam exibidos
        corretamente no conhost do Windows. Falhas são ignoradas, pois
        consoles redirecionados não permitem alterar essas propriedades.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Title = "Universal Remote Toolkit"
    )

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
    catch { }

    try {
        $Host.UI.RawUI.WindowTitle = $Title
    }
    catch { }
}

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
        [AllowEmptyString()]
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

function Write-BoxLine {
    # Escreve uma linha "║ texto ║" com o texto centralizado
    param(
        [string]$Text,
        [int]$Width,
        [string]$Color
    )

    $Inner = $Width - 2

    if ($Text.Length -gt $Inner) {
        $Text = $Text.Substring(0, $Inner)
    }

    $Content = (Format-CenteredText -Text $Text -Width $Inner).PadRight($Inner)

    Write-Host "  $($script:Glyph.Vertical)" -ForegroundColor DarkCyan -NoNewline
    Write-Host $Content -ForegroundColor $Color -NoNewline
    Write-Host $script:Glyph.Vertical -ForegroundColor DarkCyan
}

function Show-Banner {
    <#
    .SYNOPSIS
        Exibe um banner formatado no início da aplicação

    .PARAMETER Title
        Título principal do banner

    .PARAMETER Subtitle
        Subtítulo opcional (normalmente o nome da tela atual)

    .PARAMETER Width
        Largura do banner em caracteres (padrão: 64, válido: 20-200)

    .PARAMETER HideStatus
        Oculta a linha de status (usuário, máquina e horário)

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
        [int]$Width = $script:DefaultWidth,

        [Parameter(Mandatory = $false)]
        [switch]$HideStatus
    )

    $Line = $script:Glyph.Horizontal * ($Width - 2)

    Write-Host ""
    Write-Host "  $($script:Glyph.TopLeft)$Line$($script:Glyph.TopRight)" -ForegroundColor DarkCyan
    Write-BoxLine -Text $Title.ToUpper() -Width $Width -Color White

    if ($Subtitle) {
        Write-BoxLine -Text $Subtitle -Width $Width -Color Cyan
    }

    Write-Host "  $($script:Glyph.BottomLeft)$Line$($script:Glyph.BottomRight)" -ForegroundColor DarkCyan

    if (-not $HideStatus) {
        $Status = "{0}@{1}  $($script:Glyph.Bullet)  {2:dd/MM/yyyy HH:mm}" -f `
            [Environment]::UserName,
            [Environment]::MachineName,
            (Get-Date)

        Write-Host (Format-CenteredText -Text $Status -Width ($Width + 4)) -ForegroundColor DarkGray
    }

    Write-Host ""
}

function Show-Section {
    <#
    .SYNOPSIS
        Exibe um cabeçalho de seção com uma linha divisória

    .EXAMPLE
        Show-Section -Title "Install software"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 200)]
        [int]$Width = $script:DefaultWidth
    )

    $Label = " $Title "
    $Remaining = [math]::Max(0, $Width - $Label.Length - 2)

    Write-Host ""
    Write-Host "  $($script:Glyph.Rule * 2)" -ForegroundColor DarkGray -NoNewline
    Write-Host $Label -ForegroundColor White -NoNewline
    Write-Host ($script:Glyph.Rule * $Remaining) -ForegroundColor DarkGray
    Write-Host ""
}

function Show-MainMenu {
    <#
    .SYNOPSIS
        Exibe o menu principal com opções formatadas

    .PARAMETER MenuItems
        Hashtable com [número] = "descrição"

    .PARAMETER Description
        Descrição do menu (opcional)

    .DESCRIPTION
        A opção 0 (sair/voltar) é sempre exibida por último, separada
        das demais por uma linha em branco.

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

    Write-Host "  $Description" -ForegroundColor Gray
    Write-Host ""

    # Menus [ordered] mantêm a ordem definida; hashtables comuns
    # não têm ordem garantida, então são ordenadas.
    $Entries = @($MenuItems.GetEnumerator())

    if ($MenuItems -isnot [System.Collections.Specialized.OrderedDictionary]) {
        $Entries = @($Entries | Sort-Object -Property Name)
    }

    $Options = @($Entries | Where-Object { "$($_.Name)" -ne '0' })
    $ExitEntry = $Entries | Where-Object { "$($_.Name)" -eq '0' } | Select-Object -First 1

    foreach ($Entry in $Options) {
        Write-MenuOption -Key $Entry.Name -Label $Entry.Value
    }

    if ($ExitEntry) {
        Write-Host ""
        Write-MenuOption -Key $ExitEntry.Name -Label $ExitEntry.Value -Dim
    }

    Write-Host ""
}

function Write-MenuOption {
    # Escreve uma opção de menu no formato "  [1]  Descrição"
    param(
        $Key,
        [string]$Label,
        [switch]$Dim
    )

    $KeyColor = if ($Dim) { 'DarkGray' } else { 'Cyan' }
    $LabelColor = if ($Dim) { 'Gray' } else { 'White' }

    Write-Host "    [" -ForegroundColor DarkGray -NoNewline
    Write-Host $Key -ForegroundColor $KeyColor -NoNewline
    Write-Host "]  " -ForegroundColor DarkGray -NoNewline
    Write-Host $Label -ForegroundColor $LabelColor
}

function Write-PromptLabel {
    # Escreve o rótulo de um prompt sem quebrar a linha
    param([string]$Text)

    Write-Host "  $($script:Glyph.Prompt) " -ForegroundColor Cyan -NoNewline
    Write-Host "$Text" -ForegroundColor Yellow -NoNewline
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
        Write-PromptLabel -Text "$Prompt : "
        $Selection = Read-Host

        # Validar conversão para inteiro usando variável temporária
        $SelectionInt = 0
        if (-not [int]::TryParse($Selection, [ref]$SelectionInt)) {
            Write-Status -Status Error -Message "Entrada inválida. Digite um número."
            continue
        }

        # Validar se está nas opções permitidas
        if ($SelectionInt -in $ValidOptions) {
            return $SelectionInt
        } else {
            Write-Status -Status Error -Message "Opção inválida. Tente novamente."
        }

    } while ($true)
}

function Read-UserInput {
    <#
    .SYNOPSIS
        Lê um valor de texto digitado pelo usuário

    .PARAMETER Prompt
        Rótulo exibido antes do cursor

    .PARAMETER Default
        Valor retornado quando o usuário apenas pressiona Enter

    .DESCRIPTION
        Remove espaços nas extremidades. Retorna string vazia quando nada
        foi digitado e não há valor padrão, o que os menus tratam como
        cancelamento.

    .EXAMPLE
        $Computer = Read-UserInput -Prompt "Computer name"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory = $false)]
        [string]$Default = ""
    )

    $Label = if ($Default) { "$Prompt [$Default]: " } else { "${Prompt}: " }

    Write-PromptLabel -Text $Label
    $Value = "$(Read-Host)".Trim()

    if (-not $Value) {
        return $Default
    }

    return $Value
}

function Read-Confirmation {
    <#
    .SYNOPSIS
        Pede uma confirmação sim/não ao usuário

    .PARAMETER Prompt
        Pergunta exibida

    .DESCRIPTION
        Aceita y/yes/s/sim como confirmação. Qualquer outra resposta,
        inclusive Enter vazio, é tratada como "não".

    .EXAMPLE
        if (Read-Confirmation -Prompt "Uninstall this software?") { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    Write-Host ""
    Write-Host "  $($script:Glyph.Warning) " -ForegroundColor Yellow -NoNewline
    Write-Host "$Prompt " -ForegroundColor Yellow -NoNewline
    Write-Host "(y/N): " -ForegroundColor DarkGray -NoNewline

    $Answer = "$(Read-Host)".Trim().ToLower()

    return ($Answer -in @('y', 'yes', 's', 'sim'))
}

function Write-Status {
    <#
    .SYNOPSIS
        Escreve uma linha de status/progresso com ícone e cor

    .PARAMETER Status
        Running, Success, Warning, Error ou Info

    .PARAMETER Message
        Texto da linha

    .EXAMPLE
        Write-Status -Status Running -Message "Copying installer..."
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Running', 'Success', 'Warning', 'Error', 'Info')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $Style = $script:StatusStyle[$Status]

    Write-Host "  [" -ForegroundColor DarkGray -NoNewline
    Write-Host $Style.Icon -ForegroundColor $Style.Color -NoNewline
    Write-Host "] " -ForegroundColor DarkGray -NoNewline
    Write-Host $Message -ForegroundColor $(if ($Status -eq 'Running') { 'Gray' } else { $Style.Color })
}

function Show-Properties {
    <#
    .SYNOPSIS
        Exibe pares chave/valor com as chaves alinhadas

    .PARAMETER Properties
        Dicionário (de preferência [ordered]) com os valores a exibir

    .PARAMETER Indent
        Recuo à esquerda em espaços

    .EXAMPLE
        Show-Properties -Properties ([ordered]@{ Computer = "PC01"; ExitCode = 0 })
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Properties,

        [Parameter(Mandatory = $false)]
        [int]$Indent = 4
    )

    if ($Properties.Count -eq 0) {
        return
    }

    $KeyWidth = ($Properties.Keys | ForEach-Object { "$_".Length } | Measure-Object -Maximum).Maximum
    $Padding = " " * $Indent

    foreach ($Entry in $Properties.GetEnumerator()) {
        $Value = if ($null -eq $Entry.Value -or "$($Entry.Value)" -eq '') { '-' } else { "$($Entry.Value)" }

        Write-Host "$Padding$("$($Entry.Name)".PadRight($KeyWidth))  " -ForegroundColor DarkGray -NoNewline
        Write-Host $Value -ForegroundColor White
    }
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
    Write-Host "  $Title" -ForegroundColor Gray
    Write-Host ""

    # Alinha os números quando a lista passa de 9 itens
    $KeyWidth = "$($Items.Count)".Length

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $Label = $Items[$i] | ForEach-Object $DisplayProperty
        Write-MenuOption -Key "$($i + 1)".PadLeft($KeyWidth) -Label $Label
    }

    Write-Host ""
    Write-MenuOption -Key "0".PadLeft($KeyWidth) -Label "Cancelar" -Dim
    Write-Host ""

    $Choice = Read-MenuSelection -ValidOptions (0..$Items.Count)

    if ($Choice -eq 0) {
        return $null
    }

    return $Items[$Choice - 1]
}

function Wait-UserAcknowledge {
    <#
    .SYNOPSIS
        Aguarda o usuário pressionar Enter
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Message = "Pressione Enter para continuar"
    )

    Write-Host ""
    Write-Host "  $Message" -ForegroundColor DarkGray -NoNewline
    # Out-Null evita que o texto digitado vaze para o pipeline
    Read-Host | Out-Null
}

function Show-ExecutionResult {
    <#
    .SYNOPSIS
        Exibe o resultado de uma execução com formatação

    .PARAMETER Status
        Status da execução: 'Success', 'Error', 'Warning', 'Info'

    .PARAMETER Message
        Mensagem a ser exibida

    .PARAMETER Properties
        Pares chave/valor exibidos alinhados abaixo da mensagem (opcional)

    .PARAMETER Details
        Texto livre adicional, exibido após as propriedades (opcional)

    .PARAMETER DetailsTitle
        Rótulo exibido acima de Details (ex: "Output")

    .PARAMETER Pause
        Se $true, aguarda Enter antes de continuar (padrão: $true)

    .DESCRIPTION
        Exibe resultado com ícone e cor apropriados.

    .EXAMPLE
        Show-ExecutionResult -Status Success -Message "Comando executado" -Properties ([ordered]@{ Computer = "PC01" })

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
        [System.Collections.IDictionary]$Properties,

        [Parameter(Mandatory = $false)]
        [string]$Details = "",

        [Parameter(Mandatory = $false)]
        [string]$DetailsTitle = "",

        [Parameter(Mandatory = $false)]
        [bool]$Pause = $true
    )

    $Style = $script:StatusStyle[$Status]
    $Rule = $script:Glyph.Rule * $script:DefaultWidth

    Write-Host ""
    Write-Host "  $Rule" -ForegroundColor $Style.Color
    Write-Host "  $($Style.Icon)  " -ForegroundColor $Style.Color -NoNewline
    Write-Host $Message -ForegroundColor $Style.Color
    Write-Host "  $Rule" -ForegroundColor $Style.Color

    if ($Properties -and $Properties.Count -gt 0) {
        Write-Host ""
        Show-Properties -Properties $Properties
    }

    if (-not [string]::IsNullOrWhiteSpace($Details)) {
        Write-Host ""

        if ($DetailsTitle) {
            Write-Host "    $DetailsTitle" -ForegroundColor DarkGray
        }

        # Indenta todas as linhas, não apenas a primeira
        $Details.TrimEnd() -split "\r?\n" | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Gray
        }
    }

    if ($Pause) {
        Wait-UserAcknowledge
    }

    Write-Host ""
}
