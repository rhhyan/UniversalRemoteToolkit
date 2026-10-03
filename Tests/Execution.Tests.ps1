# Testes do módulo Execution (montagem de argumentos e controle do processo)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToolkitModules
    Start-TestLog -LogFile (Join-Path $TestDrive 'test.log')

    # Executável falso no lugar do PsExec: imprime stdout/stderr e sai com o
    # código recebido; "sleep" simula um processo travado.
    if ($IsWindows) {
        $script:FakePsExec = Join-Path $TestDrive 'fake.cmd'
        Set-Content $FakePsExec -Value @(
            '@echo off'
            'if "%1"=="sleep" ( ping -n 10 127.0.0.1 >nul & exit /b 0 )'
            'echo saida %1'
            'echo erro 1>&2'
            'exit /b %1'
        )
    }
    else {
        $script:FakePsExec = Join-Path $TestDrive 'fake.sh'
        Set-Content $FakePsExec -Value @(
            '#!/bin/sh'
            'if [ "$1" = "sleep" ]; then sleep 10; exit 0; fi'
            'echo "saida $1"'
            'echo erro >&2'
            'exit $1'
        )
        chmod +x $FakePsExec
    }
}

# Funções internas do módulo: chamadas com InModuleScope
Describe 'Build-PsExecArguments' {

    It 'adiciona \\ ao nome e as opções -accepteula -nobanner' {
        InModuleScope Execution { Build-PsExecArguments -ComputerName 'PC-001' -Executable 'cmd.exe' -Arguments '/c hostname' } |
            Should -Be '\\PC-001 -accepteula -nobanner cmd.exe /c hostname'
    }

    It 'não duplica \\ quando já informado' {
        InModuleScope Execution { Build-PsExecArguments -ComputerName '\\PC-001' -Executable 'cmd.exe' } |
            Should -Be '\\PC-001 -accepteula -nobanner cmd.exe'
    }

    It 'coloca aspas em executável com espaço' {
        InModuleScope Execution { Build-PsExecArguments -ComputerName 'PC' -Executable 'C:\Program Files\App\app.exe' -Arguments '/S' } |
            Should -Be '\\PC -accepteula -nobanner "C:\Program Files\App\app.exe" /S'
    }

    It 'não duplica aspas já existentes' {
        InModuleScope Execution { Build-PsExecArguments -ComputerName 'PC' -Executable '"C:\Program Files\a.exe"' } |
            Should -Be '\\PC -accepteula -nobanner "C:\Program Files\a.exe"'
    }

    It 'aplica -s e -i' {
        InModuleScope Execution { Build-PsExecArguments -ComputerName 'PC' -Executable 'x.exe' -System -Interactive } |
            Should -Be '\\PC -accepteula -nobanner -s -i x.exe'
    }
}

Describe 'Invoke-PsExecProcess' {

    It 'captura saída, erro e exit code 0' {
        $Result = InModuleScope Execution -Parameters @{ Exe = $FakePsExec } { param($Exe) Invoke-PsExecProcess -PsExecPath $Exe -ArgumentList '0' -TimeoutSeconds 10 }

        $Result.Success | Should -BeTrue
        $Result.ExitCode | Should -Be 0
        $Result.TimedOut | Should -BeFalse
        $Result.Output | Should -Be 'saida 0'
        $Result.Error | Should -Be 'erro'
    }

    It 'reporta falha com exit code diferente de zero' {
        $Result = InModuleScope Execution -Parameters @{ Exe = $FakePsExec } { param($Exe) Invoke-PsExecProcess -PsExecPath $Exe -ArgumentList '5' -TimeoutSeconds 10 }

        $Result.Success | Should -BeFalse
        $Result.ExitCode | Should -Be 5
    }

    It 'encerra o processo no timeout' {
        $Watch = [System.Diagnostics.Stopwatch]::StartNew()
        $Result = InModuleScope Execution -Parameters @{ Exe = $FakePsExec } { param($Exe) Invoke-PsExecProcess -PsExecPath $Exe -ArgumentList 'sleep' -TimeoutSeconds 1 }

        $Result.TimedOut | Should -BeTrue
        $Result.Success | Should -BeFalse
        $Result.ExitCode | Should -BeNullOrEmpty
        $Watch.Elapsed.TotalSeconds | Should -BeLessThan 8
    }

    It 'lança erro quando o executável não existe' {
        $Missing = Join-Path $TestDrive 'nada.exe'

        { InModuleScope Execution -Parameters @{ Exe = $Missing } { param($Exe) Invoke-PsExecProcess -PsExecPath $Exe -ArgumentList 'x' } } |
            Should -Throw '*not found*'
    }
}

Describe 'Invoke-PsExecCommand' {

    BeforeEach {
        Mock -ModuleName Execution Test-PsExecInstalled { $true }
        Mock -ModuleName Execution Test-ComputerReachable { $true }
        Mock -ModuleName Execution Get-PsExecPath { 'C:\fake\PsExec.exe' }
        Mock -ModuleName Execution Invoke-PsExecProcess {
            [PSCustomObject]@{ Success = $true; ExitCode = 0; TimedOut = $false; Output = 'ok'; Error = '' }
        }
    }

    It 'monta o comando e retorna o resultado estruturado' {
        $Result = Invoke-PsExecCommand -ComputerName 'PC-001' -Executable 'cmd.exe' -Arguments '/c ver' -TimeoutSeconds 30

        $Result.Success | Should -BeTrue
        $Result.Computer | Should -Be 'PC-001'
        $Result.Output | Should -Be 'ok'

        Should -Invoke -ModuleName Execution Invoke-PsExecProcess -Times 1 -ParameterFilter {
            $ArgumentList -eq '\\PC-001 -accepteula -nobanner cmd.exe /c ver' -and $TimeoutSeconds -eq 30
        }
    }

    It '-System executa como SYSTEM (PsExec -s)' {
        Invoke-PsExecCommand -ComputerName 'PC-001' -Executable 'cmd.exe' -Arguments '/c ver' -System | Out-Null

        Should -Invoke -ModuleName Execution Invoke-PsExecProcess -Times 1 -ParameterFilter {
            $ArgumentList -eq '\\PC-001 -accepteula -nobanner -s cmd.exe /c ver'
        }
    }

    It 'não executa quando o PsExec não existe' {
        Mock -ModuleName Execution Test-PsExecInstalled { $false }

        $Result = Invoke-PsExecCommand -ComputerName 'PC' -Executable 'cmd.exe'

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'PsExec'
        Should -Invoke -ModuleName Execution Invoke-PsExecProcess -Times 0
    }

    It 'não executa quando o computador está inacessível' {
        Mock -ModuleName Execution Test-ComputerReachable { $false }

        $Result = Invoke-PsExecCommand -ComputerName 'PC' -Executable 'cmd.exe'

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'not reachable'
        Should -Invoke -ModuleName Execution Invoke-PsExecProcess -Times 0
    }

    It 'propaga timeout' {
        Mock -ModuleName Execution Invoke-PsExecProcess {
            [PSCustomObject]@{ Success = $false; ExitCode = $null; TimedOut = $true; Output = ''; Error = '' }
        }

        $Result = Invoke-PsExecCommand -ComputerName 'PC' -Executable 'cmd.exe'

        $Result.TimedOut | Should -BeTrue
        $Result.Success | Should -BeFalse
    }
}

Describe 'Copy-FileToRemote' {

    BeforeAll {
        $script:Source = Join-Path $TestDrive 'setup.msi'
        Set-Content -Path $Source -Value 'x'
    }

    BeforeEach {
        Mock -ModuleName Execution Test-ComputerReachable { $true }
        # Só os caminhos UNC são simulados; o arquivo de origem é real
        Mock -ModuleName Execution Test-Path { Microsoft.PowerShell.Management\Test-Path @PesterBoundParameters }
        Mock -ModuleName Execution Test-Path { $false } -ParameterFilter { $LiteralPath -like '\\*' }
        Mock -ModuleName Execution New-Item { }
        Mock -ModuleName Execution Copy-Item { }
    }

    It 'cria a pasta pelo C$, copia e retorna os dois caminhos' {
        $Result = Copy-FileToRemote -ComputerName '\\PC-001' -SourcePath $Source -DestinationDirectory 'C:\script_temp\'

        $Result.Success | Should -BeTrue
        $Result.Reachable | Should -BeTrue
        $Result.FileName | Should -Be 'setup.msi'
        $Result.UncPath | Should -Be '\\PC-001\C$\script_temp\setup.msi'
        $Result.RemotePath | Should -Be 'C:\script_temp\setup.msi'

        Should -Invoke -ModuleName Execution New-Item -Times 1 -ParameterFilter { $Path -eq '\\PC-001\C$\script_temp' }
        Should -Invoke -ModuleName Execution Copy-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq $Source -and $Destination -eq '\\PC-001\C$\script_temp\setup.msi'
        }
    }

    It 'não recria a pasta que já existe' {
        Mock -ModuleName Execution Test-Path { $true } -ParameterFilter { $LiteralPath -like '\\*' }

        (Copy-FileToRemote -ComputerName 'PC' -SourcePath $Source -DestinationDirectory 'C:\script_temp').Success | Should -BeTrue

        Should -Invoke -ModuleName Execution New-Item -Times 0
    }

    It 'computador inacessível: não copia e marca Reachable = $false' {
        Mock -ModuleName Execution Test-ComputerReachable { $false }

        $Result = Copy-FileToRemote -ComputerName 'PC' -SourcePath $Source -DestinationDirectory 'C:\script_temp'

        $Result.Success | Should -BeFalse
        $Result.Reachable | Should -BeFalse
        $Result.Error | Should -Be "Computer 'PC' is not reachable."
        Should -Invoke -ModuleName Execution Copy-Item -Times 0
    }

    It 'arquivo de origem inexistente: não faz ping nem copia' {
        $Result = Copy-FileToRemote -ComputerName 'PC' -SourcePath (Join-Path $TestDrive 'nada.exe') -DestinationDirectory 'C:\script_temp'

        $Result.Success | Should -BeFalse
        $Result.Reachable | Should -BeNullOrEmpty
        $Result.Error | Should -Match 'not found'
        Should -Invoke -ModuleName Execution Test-ComputerReachable -Times 0
    }

    It 'erro na cópia vira resultado de falha (sem lançar)' {
        Mock -ModuleName Execution Copy-Item { throw 'Access denied' }

        $Result = Copy-FileToRemote -ComputerName 'PC' -SourcePath $Source -DestinationDirectory 'C:\script_temp'

        $Result.Success | Should -BeFalse
        $Result.Reachable | Should -BeTrue
        $Result.Error | Should -Match 'Access denied'
    }

    It 'rejeita destino que não é caminho local absoluto' {
        $Result = Copy-FileToRemote -ComputerName 'PC' -SourcePath $Source -DestinationDirectory 'script_temp'

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'absolute local path'
    }
}
