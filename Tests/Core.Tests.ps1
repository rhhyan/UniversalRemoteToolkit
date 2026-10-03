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

    It 'lê o Settings.json do disco uma vez só (cache) e relê com -Force' {
        InModuleScope Config { $script:ConfigCache = $null }
        Mock -ModuleName Config Get-Content { '{ "Application": { "Name": "Cache" } }' }

        try {
            (Get-ToolkitConfig).Application.Name | Should -Be 'Cache'
            (Get-ToolkitConfig).Application.Name | Should -Be 'Cache'
            Should -Invoke -ModuleName Config Get-Content -Times 1 -Exactly

            Get-ToolkitConfig -Force | Out-Null
            Should -Invoke -ModuleName Config Get-Content -Times 2 -Exactly
        }
        finally {
            # Não deixa o JSON falso no cache para os outros testes
            InModuleScope Config { $script:ConfigCache = $null }
        }
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

    It 'Test-IsAdministrator retorna booleano' {
        Test-IsAdministrator | Should -BeOfType [bool]
    }

    It 'ConvertTo-AdminSharePath: <Computer> + <Path> -> <Expected>' -ForEach @(
        @{ Computer = 'PC-001';   Path = 'C:\script_temp';  Expected = '\\PC-001\C$\script_temp' }
        @{ Computer = '\\PC-001'; Path = 'C:\script_temp';  Expected = '\\PC-001\C$\script_temp' }
        @{ Computer = 'PC-001';   Path = 'd:\apps\temp\';   Expected = '\\PC-001\D$\apps\temp' }
        @{ Computer = 'PC-001';   Path = 'C:\';             Expected = '\\PC-001\C$' }
        @{ Computer = 'PC-001';   Path = 'C:';              Expected = '\\PC-001\C$' }
    ) {
        ConvertTo-AdminSharePath -ComputerName $Computer -Path $Path | Should -Be $Expected
    }

    It 'ConvertTo-AdminSharePath rejeita <Case>' -ForEach @(
        @{ Case = 'caminho relativo';     Computer = 'PC'; Path = 'script_temp' }
        @{ Case = 'caminho UNC';          Computer = 'PC'; Path = '\\srv\share' }
        @{ Case = 'computador só com \\'; Computer = '\\'; Path = 'C:\x' }
    ) {
        { ConvertTo-AdminSharePath -ComputerName $Computer -Path $Path } | Should -Throw
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

    It 'Write-Log sem sessão iniciada não lança erro e vai para o Verbose' {
        Stop-Log

        { Write-Log -Message 'x' } | Should -Not -Throw

        $Verbose = Write-Log -Level Warning -Message 'sem sessão' -Verbose 4>&1
        "$Verbose" | Should -Match '\[WARNING\] sem sessão'
    }

    It 'Write-Log sem sessão não cria arquivo de log' {
        Stop-Log
        Write-Log -Message 'x'

        Test-Path $LogsPath | Should -BeFalse
    }

    It 'usa a pasta Logs na raiz do projeto quando a configuração não pode ser lida' {
        Mock -ModuleName Logger Get-ToolkitConfig { throw 'sem Settings.json' }
        Mock -ModuleName Logger Get-ToolkitRoot { $TestDrive }

        Start-Log

        Get-ChildItem (Join-Path $TestDrive 'Logs') -Filter 'URT_*.log' | Should -HaveCount 1
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

        # Depois do Stop-Log nada mais vai para o arquivo
        Write-Log -Message 'depois do stop'
        Get-Content $LogFile -Raw | Should -Not -Match 'depois do stop'
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
