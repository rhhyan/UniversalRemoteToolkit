# Testes de Config, Utils, Logger e Connection

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToolkitModules
}

Describe 'Config' {

    It 'carrega o Settings.json' {
        $Config = Get-ToolkitConfig

        $Config.Application.Name | Should -Be 'Universal Remote Toolkit'
        $Config.Software.SupportedInstallers | Should -Contain '.msi'
        $Config.Software.RemoteTempPath | Should -Match '^[A-Za-z]:\\'
    }

    It 'Get-ToolkitRoot aponta para a raiz do repositório' {
        (Get-ToolkitRoot) | Should -Be $RepoRoot
    }

    It 'resolve caminho relativo a partir da raiz' {
        $Resolved = Resolve-ToolkitPath -Path (Join-Path '.' 'Bin' 'PsExec.exe')

        $Resolved | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $RepoRoot 'Bin/PsExec.exe')))
    }

    It 'mantém caminho absoluto' {
        $Absolute = Join-Path $TestDrive 'x.log'

        Resolve-ToolkitPath -Path $Absolute | Should -Be $Absolute
    }
}

Describe 'Utils' {

    It 'Format-Date usa o padrão yyyy-MM-dd HH:mm:ss' {
        Format-Date -Date ([datetime]'2026-01-02 03:04:05') | Should -Be '2026-01-02 03:04:05'
    }

    It 'Get-ApplicationRoot aponta para a raiz do repositório' {
        Get-ApplicationRoot | Should -Be $RepoRoot
    }

    It 'Format-Duration formata <Case>' -ForEach @(
        @{ Case = 'milissegundos'; Ticks = [timespan]::FromMilliseconds(250).Ticks; Pattern = '^250 ms$' }
        @{ Case = 'segundos'; Ticks = [timespan]::FromSeconds(12.5).Ticks; Pattern = '^12[.,]50 s$' }
        @{ Case = 'minutos'; Ticks = [timespan]::FromSeconds(125).Ticks; Pattern = '^02m 05s$' }
    ) {
        # Stopwatch não permite definir o tempo; usa um objeto com a mesma interface
        $Stopwatch = [System.Diagnostics.Stopwatch]::new()
        $Elapsed = [timespan]::new($Ticks)

        $Fake = $Stopwatch | Add-Member -MemberType ScriptProperty -Name Elapsed -Value { $Elapsed }.GetNewClosure() -Force -PassThru
        $Fake | Add-Member -MemberType ScriptProperty -Name ElapsedMilliseconds -Value { [long]$Elapsed.TotalMilliseconds }.GetNewClosure() -Force

        Format-Duration -Stopwatch $Fake | Should -Match $Pattern
    }

    It 'Test-IsAdministrator retorna booleano' {
        Test-IsAdministrator | Should -BeOfType [bool]
    }
}

Describe 'Logger' {

    BeforeEach {
        $LogsPath = Join-Path $TestDrive "logs_$([guid]::NewGuid())"

        Mock -ModuleName Logger Get-ToolkitConfig {
            [PSCustomObject]@{
                Paths = [PSCustomObject]@{ Logs = $LogsPath }
                Logs  = [PSCustomObject]@{ RetentionDays = 30; EnableConsole = $false }
            }
        }
    }

    AfterEach {
        Stop-Log
    }

    It 'Write-Log falha sem sessão iniciada' {
        Stop-Log
        { Write-Log -Message 'x' } | Should -Throw '*Start-Log*'
    }

    It 'cria a pasta e o arquivo de log e grava as mensagens' {
        Start-Log
        Write-Log -Level Success -Message 'teste de gravação'

        $File = Get-ChildItem $LogsPath -Filter 'URT_*.log'
        $File | Should -HaveCount 1

        $Content = Get-Content $File.FullName -Raw -Encoding UTF8
        $Content | Should -Match '\[SUCCESS\] teste de gravação'
    }

    It 'rejeita nível inválido' {
        Start-Log
        { Write-Log -Level Fatal -Message 'x' } | Should -Throw
    }

    It 'remove logs mais antigos que RetentionDays' {
        New-Item -ItemType Directory -Path $LogsPath -Force | Out-Null

        $Old = New-Item -ItemType File -Path (Join-Path $LogsPath 'URT_old.log')
        $Old.LastWriteTime = (Get-Date).AddDays(-40)
        $Recent = New-Item -ItemType File -Path (Join-Path $LogsPath 'URT_recent.log')

        Start-Log

        Test-Path $Old.FullName | Should -BeFalse
        Test-Path $Recent.FullName | Should -BeTrue
    }

    It 'Stop-Log registra a duração e encerra a sessão' {
        Start-Log
        $LogFile = (Get-ChildItem $LogsPath -Filter 'URT_*.log').FullName

        Stop-Log

        Get-Content $LogFile -Raw | Should -Match 'Tempo total: \d{2}:\d{2}:\d{2}'
        { Write-Log -Message 'x' } | Should -Throw
    }
}

Describe 'Connection' {

    It 'encontra o PsExec em Bin' {
        $Path = Get-PsExecPath

        $Path | Should -Not -BeNullOrEmpty
        Test-Path $Path -PathType Leaf | Should -BeTrue
        Test-PsExecInstalled | Should -BeTrue
    }

    It 'retorna $null quando o PsExec não existe' {
        Mock -ModuleName Connection Get-ToolkitConfig {
            [PSCustomObject]@{ Paths = [PSCustomObject]@{ PsExec = (Join-Path $TestDrive 'nao_existe.exe') } }
        }

        Get-PsExecPath | Should -BeNullOrEmpty
        Test-PsExecInstalled | Should -BeFalse
    }

    It 'retorna $false para host inexistente' {
        Test-ComputerReachable -ComputerName 'host-que-nao-existe.invalid' -TimeoutMilliseconds 200 | Should -BeFalse
    }

    It 'aceita nome com barras (\\PC) e responde para localhost' {
        # ICMP pode ser bloqueado em alguns ambientes; o importante é não lançar erro
        { Test-ComputerReachable -ComputerName '\\127.0.0.1' -TimeoutMilliseconds 500 } | Should -Not -Throw
    }

    It 'valida o intervalo de timeout' {
        { Test-ComputerReachable -ComputerName 'x' -TimeoutMilliseconds 10 } | Should -Throw
    }
}
