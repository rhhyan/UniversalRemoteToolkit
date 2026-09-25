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

Describe 'Build-PsExecArguments' {

    It 'adiciona \\ ao nome e as opções -accepteula -nobanner' {
        Build-PsExecArguments -ComputerName 'PC-001' -Executable 'cmd.exe' -Arguments '/c hostname' |
            Should -Be '\\PC-001 -accepteula -nobanner cmd.exe /c hostname'
    }

    It 'não duplica \\ quando já informado' {
        Build-PsExecArguments -ComputerName '\\PC-001' -Executable 'cmd.exe' |
            Should -Be '\\PC-001 -accepteula -nobanner cmd.exe'
    }

    It 'coloca aspas em executável com espaço' {
        Build-PsExecArguments -ComputerName 'PC' -Executable 'C:\Program Files\App\app.exe' -Arguments '/S' |
            Should -Be '\\PC -accepteula -nobanner "C:\Program Files\App\app.exe" /S'
    }

    It 'não duplica aspas já existentes' {
        Build-PsExecArguments -ComputerName 'PC' -Executable '"C:\Program Files\a.exe"' |
            Should -Be '\\PC -accepteula -nobanner "C:\Program Files\a.exe"'
    }

    It 'aplica -s e -i' {
        Build-PsExecArguments -ComputerName 'PC' -Executable 'x.exe' -System -Interactive |
            Should -Be '\\PC -accepteula -nobanner -s -i x.exe'
    }
}

Describe 'Invoke-PsExecProcess' {

    It 'captura saída, erro e exit code 0' {
        $Result = Invoke-PsExecProcess -PsExecPath $FakePsExec -ArgumentList '0' -TimeoutSeconds 10

        $Result.Success | Should -BeTrue
        $Result.ExitCode | Should -Be 0
        $Result.TimedOut | Should -BeFalse
        $Result.Output | Should -Be 'saida 0'
        $Result.Error | Should -Be 'erro'
    }

    It 'reporta falha com exit code diferente de zero' {
        $Result = Invoke-PsExecProcess -PsExecPath $FakePsExec -ArgumentList '5' -TimeoutSeconds 10

        $Result.Success | Should -BeFalse
        $Result.ExitCode | Should -Be 5
    }

    It 'encerra o processo no timeout' {
        $Watch = [System.Diagnostics.Stopwatch]::StartNew()
        $Result = Invoke-PsExecProcess -PsExecPath $FakePsExec -ArgumentList 'sleep' -TimeoutSeconds 1

        $Result.TimedOut | Should -BeTrue
        $Result.Success | Should -BeFalse
        $Result.ExitCode | Should -BeNullOrEmpty
        $Watch.Elapsed.TotalSeconds | Should -BeLessThan 8
    }

    It 'lança erro quando o executável não existe' {
        { Invoke-PsExecProcess -PsExecPath (Join-Path $TestDrive 'nada.exe') -ArgumentList 'x' } |
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
