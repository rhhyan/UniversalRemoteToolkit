# Testes do módulo Scripts e dos scripts remotos (Otimizacao/Ativacao)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToolkitModules
    Start-TestLog -LogFile (Join-Path $TestDrive 'test.log')

    $script:RemoteScripts = Join-Path $ModulesPath 'Scripts'
}

Describe 'Get-ToolkitScript' {

    It 'lista os scripts do catálogo e todos existem' {
        $Scripts = @(Get-ToolkitScript)

        $Scripts.Name | Should -Be @('Otimizacao', 'Ativacao')
        $Scripts | ForEach-Object { $_.Available | Should -BeTrue -Because $_.LocalPath }
    }
}

Describe 'Invoke-RemoteToolkitScript' {

    BeforeEach {
        Mock -ModuleName Scripts Copy-ScriptToRemote {
            [PSCustomObject]@{ Success = $true; RemoteUnc = (Join-Path $TestDrive 'copia.ps1'); RemotePath = 'C:\script_temp\Ativacao.ps1'; Error = $null }
        }
        Mock -ModuleName Scripts Remove-Item { }
        Mock -ModuleName Scripts Invoke-PsExecCommand {
            [PSCustomObject]@{ Success = $true; ExitCode = 0; TimedOut = $false; Output = 'ok'; Error = '' }
        }
    }

    It 'copia, executa com powershell -File e remove a cópia' {
        $Result = Invoke-RemoteToolkitScript -ComputerName 'PC' -ScriptName 'Ativacao' -Arguments '-Target Status'

        $Result.Success | Should -BeTrue
        $Result.Status | Should -Be 'Success'

        Should -Invoke -ModuleName Scripts Invoke-PsExecCommand -ParameterFilter {
            $Executable -eq 'powershell.exe' -and
            $Arguments -eq '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\script_temp\Ativacao.ps1" -Target Status' -and
            $TimeoutSeconds -eq 300
        }
        Should -Invoke -ModuleName Scripts Remove-Item -Times 1
    }

    It 'exit <ExitCode> => <Status>' -ForEach @(
        @{ ExitCode = 2; TimedOut = $false; Status = 'Partial'; Success = $true }
        @{ ExitCode = 1; TimedOut = $false; Status = 'Failed'; Success = $false }
        @{ ExitCode = $null; TimedOut = $true; Status = 'Timeout'; Success = $false }
    ) {
        Mock -ModuleName Scripts Invoke-PsExecCommand {
            [PSCustomObject]@{ Success = $false; ExitCode = $ExitCode; TimedOut = $TimedOut; Output = ''; Error = 'x' }
        }

        $Result = Invoke-RemoteToolkitScript -ComputerName 'PC' -ScriptName 'Otimizacao'

        $Result.Status | Should -Be $Status
        $Result.Success | Should -Be $Success
    }

    It 'falha quando o PsExec não pôde ser executado (exit code nulo)' {
        Mock -ModuleName Scripts Invoke-PsExecCommand {
            [PSCustomObject]@{ Success = $false; ExitCode = $null; TimedOut = $false; Output = $null; Error = 'PsExec executable was not found.' }
        }

        $Result = Invoke-RemoteToolkitScript -ComputerName 'PC' -ScriptName 'Ativacao'

        $Result.Status | Should -Be 'Failed'
        $Result.Success | Should -BeFalse
    }

    It 'rejeita script fora do catálogo' {
        $Result = Invoke-RemoteToolkitScript -ComputerName 'PC' -ScriptName 'Nada'

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'catalog'
        Should -Invoke -ModuleName Scripts Copy-ScriptToRemote -Times 0
    }

    It 'computador inacessível: não executa e mantém a mensagem de antes' {
        Mock -ModuleName Scripts Copy-ScriptToRemote {
            [PSCustomObject]@{ Success = $false; Reachable = $false; Error = "Computer 'PC' is not reachable." }
        }

        $Result = Invoke-RemoteToolkitScript -ComputerName 'PC' -ScriptName 'Ativacao'

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Be "Computer 'PC' is not reachable."
        Should -Invoke -ModuleName Scripts Invoke-PsExecCommand -Times 0
    }

    It 'não executa quando a cópia falha' {
        Mock -ModuleName Scripts Copy-ScriptToRemote { [PSCustomObject]@{ Success = $false; Reachable = $true; Error = 'Access denied' } }

        $Result = Invoke-RemoteToolkitScript -ComputerName 'PC' -ScriptName 'Ativacao'

        $Result.Error | Should -Be 'Copy failed: Access denied'
        Should -Invoke -ModuleName Scripts Invoke-PsExecCommand -Times 0
    }
}

Describe 'Invoke-WindowsOptimization / Invoke-LicenseActivation' {

    BeforeEach {
        Mock -ModuleName Scripts Invoke-RemoteToolkitScript { [PSCustomObject]@{ Arguments = $Arguments; Script = $ScriptName } }
    }

    It 'CleanProfiles filtra matrículas inválidas e repassa -SkipSfc' {
        $Result = Invoke-WindowsOptimization -ComputerName 'PC' -Action CleanProfiles -KeepProfiles 'TH1, TH2;TH3', 'x"; rm', 'TH4' -SkipSfc

        $Result.Arguments | Should -Be '-Action CleanProfiles -KeepProfiles "TH1,TH2,TH3,rm,TH4" -SkipSfc'
    }

    It 'outras ações ignoram KeepProfiles' {
        (Invoke-WindowsOptimization -ComputerName 'PC' -Action Debloat -KeepProfiles 'TH1' -SkipSfc).Arguments |
            Should -Be '-Action Debloat'
    }

    It 'rejeita ação inválida' {
        { Invoke-WindowsOptimization -ComputerName 'PC' -Action Formatar } | Should -Throw
    }

    It 'ativação usa o KMS do Settings.json por padrão' {
        $Result = Invoke-LicenseActivation -ComputerName 'PC' -Target Office

        $Result.Script | Should -Be 'Ativacao'
        $Result.Arguments | Should -Be "-Target Office -KmsHost $((Get-ToolkitConfig).Scripts.KmsHost)"
    }

    It 'KmsHost aceita porta e rejeita injeção' {
        (Invoke-LicenseActivation -ComputerName 'PC' -Target Windows -KmsHost 'kms.local:1688').Arguments |
            Should -Be '-Target Windows -KmsHost kms.local:1688'

        { Invoke-LicenseActivation -ComputerName 'PC' -Target Windows -KmsHost 'kms; calc' } | Should -Throw
    }
}

Describe 'Copy-ScriptToRemote' {

    It 'retorna falha quando o script local não existe' {
        $Result = Copy-ScriptToRemote -ComputerName 'PC' -ScriptPath (Join-Path $TestDrive 'nada.ps1')

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'not found'
    }

    It 'copia pelo C$ e mantém RemoteUnc / RemotePath' {
        Mock -ModuleName Execution Test-ComputerReachable { $true }
        Mock -ModuleName Execution Test-Path { Microsoft.PowerShell.Management\Test-Path @PesterBoundParameters }
        Mock -ModuleName Execution Test-Path { $true } -ParameterFilter { $LiteralPath -like '\\*' }
        Mock -ModuleName Execution Copy-Item { }

        $Result = Copy-ScriptToRemote -ComputerName '\\PC-001' -ScriptPath (Join-Path $RemoteScripts 'Ativacao.ps1')

        $Result.Success | Should -BeTrue
        $Result.RemoteUnc | Should -Be '\\PC-001\C$\script_temp\Ativacao.ps1'
        $Result.RemotePath | Should -Be 'C:\script_temp\Ativacao.ps1'
        Should -Invoke -ModuleName Execution Copy-Item -Times 1 -ParameterFilter { $Destination -eq '\\PC-001\C$\script_temp\Ativacao.ps1' }
    }

    It 'computador inacessível: Reachable = $false' {
        Mock -ModuleName Execution Test-ComputerReachable { $false }
        Mock -ModuleName Execution Copy-Item { }

        $Result = Copy-ScriptToRemote -ComputerName 'PC' -ScriptPath (Join-Path $RemoteScripts 'Ativacao.ps1')

        $Result.Success | Should -BeFalse
        $Result.Reachable | Should -BeFalse
        Should -Invoke -ModuleName Execution Copy-Item -Times 0
    }
}

Describe 'Scripts remotos' {

    It '<Name> é ASCII puro, tem BOM e parâmetros validados' -ForEach @(
        @{ Name = 'Otimizacao.ps1'; Param = 'Action' }
        @{ Name = 'Ativacao.ps1'; Param = 'Target' }
    ) {
        $Path = Join-Path $RemoteScripts $Name
        $Bytes = [System.IO.File]::ReadAllBytes($Path)

        # Saída via PsExec: somente ASCII (depois do BOM)
        @($Bytes | Select-Object -Skip 3 | Where-Object { $_ -gt 127 }) | Should -HaveCount 0

        $Command = Get-Command $Path
        $Command.Parameters[$Param].Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] }) |
            Should -Not -BeNullOrEmpty
    }

    It 'ações do catálogo batem com o ValidateSet de Otimizacao.ps1' {
        $Set = (Get-Command (Join-Path $RemoteScripts 'Otimizacao.ps1')).Parameters['Action'].Attributes.Where({
            $_ -is [System.Management.Automation.ValidateSetAttribute]
        })[0].ValidValues

        $Wrapper = (Get-Command Invoke-WindowsOptimization).Parameters['Action'].Attributes.Where({
            $_ -is [System.Management.Automation.ValidateSetAttribute]
        })[0].ValidValues

        $Wrapper | Should -Be $Set
    }
}
