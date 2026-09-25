# Testes gerais do projeto: sintaxe, encoding e execução do menu principal

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent $PSScriptRoot

    $script:SourceFiles = Get-ChildItem (Join-Path $RepoRoot 'src') -Recurse -Include *.ps1, *.psm1 |
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
