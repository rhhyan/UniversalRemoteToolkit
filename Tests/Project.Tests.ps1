# Testes gerais do projeto: sintaxe, encoding e execução do menu principal

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent $PSScriptRoot

    $script:SourceFiles = Get-ChildItem (Join-Path $RepoRoot 'src') -Recurse -Include *.ps1, *.psm1 |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }

    # Módulos e script principal (os scripts remotos em Modules\Scripts são autônomos)
    $script:ToolkitFiles = @(Get-ChildItem (Join-Path $RepoRoot 'src/Modules') -Filter *.psm1) +
        @(Get-Item (Join-Path $RepoRoot 'src/UniversalRemoteToolkit.ps1')) |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Arquivos fonte' {

    It '<Name> não tem erros de sintaxe' -ForEach $SourceFiles {
        $Tokens = $null
        $Errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors) | Out-Null

        $Errors | Should -BeNullOrEmpty
    }

    # O Windows PowerShell 5.1 lê UTF-8 sem BOM como ANSI: acentos viram "Ã§"
    It '<Name> tem BOM se contém caracteres não ASCII' -ForEach $SourceFiles {
        $Bytes = [System.IO.File]::ReadAllBytes($Path)
        $HasBom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
        $NonAscii = @($Bytes | Where-Object { $_ -gt 127 }).Count -gt 0

        if ($NonAscii) {
            $HasBom | Should -BeTrue
        }
    }
}

Describe 'Dependências entre módulos' {

    BeforeAll {
        Import-ToolkitModules

        $script:FunctionOwner = @{}   # função -> módulo que a define
        $script:Exported = @{}        # módulo -> funções exportadas

        foreach ($File in Get-ChildItem $ModulesPath -Filter *.psm1) {
            $Module = $File.BaseName
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)

            $Ast.EndBlock.Statements |
                Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] } |
                ForEach-Object { $script:FunctionOwner[$_.Name] = $Module }

            $script:Exported[$Module] = @((Get-Module $Module).ExportedFunctions.Keys)
        }

        # Chamadas a funções de outros módulos, agrupadas pelo módulo chamado
        function Get-ModuleCalls {
            param([string]$Path)

            $Self = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)

            $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } |
                Where-Object { $_ -and $script:FunctionOwner.ContainsKey($_) -and $script:FunctionOwner[$_] -ne $Self } |
                Sort-Object -Unique |
                ForEach-Object { [PSCustomObject]@{ Function = $_; Module = $script:FunctionOwner[$_] } }
        }

        # Lê "# Depende de: A, B" (ou "(nenhum)") do cabeçalho do arquivo
        function Get-DeclaredDependencies {
            param([string]$Path)

            $Match = [regex]::Match((Get-Content $Path -Raw), '(?m)^#\s*Depende de:\s*(.+?)\s*$')

            if (-not $Match.Success) {
                throw "Cabeçalho '# Depende de:' não encontrado em $Path"
            }

            if ($Match.Groups[1].Value -eq '(nenhum)') {
                return @()
            }

            @($Match.Groups[1].Value -split '\s*,\s*' | Sort-Object)
        }
    }

    It '<Name> declara no cabeçalho exatamente os módulos que usa' -ForEach $ToolkitFiles {
        $Used = @(Get-ModuleCalls -Path $Path | Select-Object -ExpandProperty Module | Sort-Object -Unique)
        $Declared = Get-DeclaredDependencies -Path $Path

        ($Used -join ', ') | Should -Be ($Declared -join ', ') -Because 'o cabeçalho "# Depende de:" deve refletir as chamadas reais'
    }

    It '<Name> só chama funções exportadas dos outros módulos' -ForEach $ToolkitFiles {
        $Internal = @(Get-ModuleCalls -Path $Path |
            Where-Object { $_.Function -notin $script:Exported[$_.Module] } |
            ForEach-Object { "$($_.Module)\$($_.Function)" })

        $Internal | Should -BeNullOrEmpty
    }
}

Describe 'UniversalRemoteToolkit.ps1' {

    BeforeAll {
        # Digita as opções como um usuário e captura toda a saída
        function Invoke-Toolkit {
            param([string[]]$Keys)

            $Pwsh = (Get-Process -Id $PID).Path
            $Script = Join-Path $RepoRoot 'src/UniversalRemoteToolkit.ps1'

            $Output = ($Keys -join "`n") + "`n" | & $Pwsh -NoProfile -File $Script 2>&1 | Out-String

            [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output   = $Output -replace '\x1b\[[0-9;?]*[A-Za-z]', ''
            }
        }
    }

    It 'navega por todos os menus e encerra sem erros' {
        $Result = Invoke-Toolkit @(
            '3', '3', '', '0'          # Settings > About
            '4', '1', '0', '2', '0', '0' # Scripts > Otimizacao / Ativacao
            '1', '1', '', '0'          # Remote Execution > cancelar
            '2', '3', '', '0'          # Software > listar > cancelar
            'x', '9', '0'              # entradas inválidas e sair
        )

        $Result.ExitCode | Should -Be 0
        $Result.Output | Should -Match 'Entrada inválida'
        $Result.Output | Should -Match 'Opção inválida'
        $Result.Output | Should -Match 'shutting down'
        $Result.Output | Should -Not -Match '\[ERROR\]|Unexpected|WARNING:'
    }

    It 'exibe o título da opção escolhida (chave, não posição)' {
        $Result = Invoke-Toolkit @(
            '4', '1', '1', ''          # Otimizacao > 1 > cancelar
            '0', '2', '3', ''          # Ativacao > 3 > cancelar
            '0', '0', '0'
        )

        $Result.Output | Should -Match '── Remover perfis BC'
        $Result.Output | Should -Match '── Verificar status de ativacao'
        $Result.Output | Should -Not -Match '── (Remover apps|Voltar)'
    }
}
