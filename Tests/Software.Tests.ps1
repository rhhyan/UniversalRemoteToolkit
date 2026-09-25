# Testes do módulo Software (repositório, instalação e desinstalação)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToolkitModules
    Start-TestLog -LogFile (Join-Path $TestDrive 'test.log')

    function New-PsExecResult {
        param($ExitCode = 0, $Output = '', $ErrorText = '', [switch]$TimedOut)

        [PSCustomObject]@{
            Success    = (-not $TimedOut -and $ExitCode -eq 0)
            ExitCode   = $ExitCode
            TimedOut   = [bool]$TimedOut
            Output     = $Output
            Error      = $ErrorText
            DurationMS = 10
        }
    }
}

Describe 'Get-SoftwareRepository / Find-SoftwareInstaller' {

    BeforeAll {
        $Repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $Repo 'Chrome/x64') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $Repo 'Chrome/x64/ChromeSetup.msi') | Out-Null
        New-Item -ItemType File -Path (Join-Path $Repo '7zip.exe') | Out-Null
        New-Item -ItemType File -Path (Join-Path $Repo 'setup.ps1') | Out-Null
        New-Item -ItemType File -Path (Join-Path $Repo 'leia-me.txt') | Out-Null

        InModuleScope Software -Parameters @{ Repo = $Repo } {
            param($Repo)
            $script:OriginalRepo = $REPOSITORY_PATH
            $script:REPOSITORY_PATH = $Repo
        }
    }

    AfterAll {
        InModuleScope Software { $script:REPOSITORY_PATH = $script:OriginalRepo }
    }

    It 'lista apenas extensões suportadas, inclusive em subpastas' {
        $Items = @(Get-SoftwareRepository)

        $Items | Should -HaveCount 3
        ($Items | Where-Object Name -eq 'ChromeSetup.msi').InstallerType | Should -Be 'MSI'
        ($Items | Where-Object Name -eq '7zip.exe').InstallerType | Should -Be 'Executable'
        ($Items | Where-Object Name -eq 'setup.ps1').InstallerType | Should -Be 'PowerShell'
    }

    It 'filtra pelo nome' {
        $Items = @(Get-SoftwareRepository -Filter 'chrome')

        $Items | Should -HaveCount 1
        $Items[0].Name | Should -Be 'ChromeSetup.msi'
    }

    It 'Find-SoftwareInstaller retorna $null quando não encontra' {
        Find-SoftwareInstaller -SoftwareName 'inexistente' | Should -BeNullOrEmpty
    }

    It 'lança erro quando o repositório está inacessível' {
        InModuleScope Software { $script:REPOSITORY_PATH = Join-Path $TestDrive 'sem_repo' }

        try {
            { Get-SoftwareRepository } | Should -Throw '*not accessible*'
        }
        finally {
            InModuleScope Software -Parameters @{ Repo = $Repo } { param($Repo) $script:REPOSITORY_PATH = $Repo }
        }
    }
}

Describe 'Install-RemoteSoftware' {

    BeforeEach {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode 0 }
    }

    It 'MSI usa msiexec /i com /quiet /norestart por padrão' {
        $Result = Install-RemoteSoftware -ComputerName 'PC' -InstallerPath 'C:\script_temp\App Setup.msi'

        $Result.Success | Should -BeTrue
        Should -Invoke -ModuleName Software Invoke-PsExecCommand -ParameterFilter {
            $Executable -eq 'msiexec.exe' -and $Arguments -eq '/i "C:\script_temp\App Setup.msi" /quiet /norestart'
        }
    }

    It 'PS1 usa powershell -File' {
        Install-RemoteSoftware -ComputerName 'PC' -InstallerPath 'C:\script_temp\setup.ps1' -Arguments '-Silent' | Out-Null

        Should -Invoke -ModuleName Software Invoke-PsExecCommand -ParameterFilter {
            $Executable -eq 'powershell.exe' -and $Arguments -eq '-NoProfile -ExecutionPolicy Bypass -File "C:\script_temp\setup.ps1" -Silent'
        }
    }

    It 'EXE executa o próprio instalador' {
        Install-RemoteSoftware -ComputerName 'PC' -InstallerPath 'C:\script_temp\7zip.EXE' -Arguments '/S' | Out-Null

        Should -Invoke -ModuleName Software Invoke-PsExecCommand -ParameterFilter {
            $Executable -eq 'C:\script_temp\7zip.EXE' -and $Arguments -eq '/S'
        }
    }

    It 'exit 3010 é sucesso com reinicialização pendente' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode 3010 }

        $Result = Install-RemoteSoftware -ComputerName 'PC' -InstallerPath 'C:\script_temp\a.msi'

        $Result.Success | Should -BeTrue
        $Result.RebootRequired | Should -BeTrue
    }

    It 'exit code de erro retorna falha' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode 1603 -ErrorText 'fatal' }

        $Result = Install-RemoteSoftware -ComputerName 'PC' -InstallerPath 'C:\script_temp\a.msi'

        $Result.Success | Should -BeFalse
        $Result.ExitCode | Should -Be 1603
    }

    It 'timeout retorna falha' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode $null -TimedOut }

        (Install-RemoteSoftware -ComputerName 'PC' -InstallerPath 'C:\script_temp\a.exe').Success | Should -BeFalse
    }

    It 'rejeita extensão não suportada' {
        $Result = Install-RemoteSoftware -ComputerName 'PC' -InstallerPath 'C:\script_temp\a.zip'

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'Unsupported'
        Should -Invoke -ModuleName Software Invoke-PsExecCommand -Times 0
    }
}

Describe 'Get-InstalledSoftware' {

    It 'converte a lista JSON ignorando texto antes e depois' {
        $Json = @(
            [PSCustomObject]@{ Name = '7-Zip'; Version = '23.01' }
            [PSCustomObject]@{ Name = 'Google Chrome'; Version = '120' }
        ) | ConvertTo-Json

        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -Output "aviso qualquer`n$Json`nfim" }

        $Apps = @(Get-InstalledSoftware -ComputerName 'PC')

        $Apps | Should -HaveCount 2
        $Apps[1].Name | Should -Be 'Google Chrome'
    }

    It 'aceita um único programa (objeto JSON), mesmo com colchetes no nome' {
        $Json = [PSCustomObject]@{ Name = 'Driver [x64]'; Version = '1.0' } | ConvertTo-Json

        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -Output $Json }

        $Apps = @(Get-InstalledSoftware -ComputerName 'PC')

        $Apps | Should -HaveCount 1
        $Apps[0].Name | Should -Be 'Driver [x64]'
    }

    It 'retorna lista vazia para [] ou saída vazia' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -Output '[]' }
        @(Get-InstalledSoftware -ComputerName 'PC') | Should -HaveCount 0

        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -Output '' }
        @(Get-InstalledSoftware -ComputerName 'PC') | Should -HaveCount 0
    }

    It 'retorna lista vazia quando a execução falha ou a saída é inválida' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode 1 -ErrorText 'Access denied' }
        @(Get-InstalledSoftware -ComputerName 'PC') | Should -HaveCount 0

        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -Output 'isso nao e json' }
        @(Get-InstalledSoftware -ComputerName 'PC') | Should -HaveCount 0
    }

    It 'envia o script como -EncodedCommand' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -Output '[]' }

        Get-InstalledSoftware -ComputerName 'PC' | Out-Null

        Should -Invoke -ModuleName Software Invoke-PsExecCommand -ParameterFilter {
            $Executable -eq 'powershell.exe' -and $Arguments -match '-EncodedCommand [A-Za-z0-9+/=]+$'
        }
    }
}

Describe 'Resolve-UninstallCommand' {

    It '<Case>' -ForEach @(
        @{
            Case = 'MSI pela chave GUID (troca /I por /x silencioso)'
            App  = @{ KeyName = '{12345678-1234-1234-1234-1234567890AB}'; WindowsInstaller = 1; UninstallString = 'MsiExec.exe /I{12345678-1234-1234-1234-1234567890AB}' }
            Type = 'MSI'; Exe = 'msiexec.exe'; ExpectedArgs = '/x {12345678-1234-1234-1234-1234567890AB} /qn /norestart'; Silent = $true
        }
        @{
            Case = 'MSI pelo GUID dentro do UninstallString'
            App  = @{ KeyName = 'AppX'; UninstallString = 'MsiExec.exe /X{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}' }
            Type = 'MSI'; Exe = 'msiexec.exe'; ExpectedArgs = '/x {AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE} /qn /norestart'; Silent = $true
        }
        @{
            Case = 'QuietUninstallString tem prioridade'
            App  = @{ KeyName = 'App'; UninstallString = '"C:\App\u.exe"'; QuietUninstallString = '"C:\Program Files\App\u.exe" /quiet' }
            Type = 'QuietUninstallString'; Exe = 'C:\Program Files\App\u.exe'; ExpectedArgs = '/quiet'; Silent = $true
        }
        @{
            Case = 'Inno Setup (unins000.exe)'
            App  = @{ KeyName = 'Notepad++_is1'; UninstallString = '"C:\Program Files\Notepad++\unins000.exe"' }
            Type = 'Inno Setup'; Exe = 'C:\Program Files\Notepad++\unins000.exe'; ExpectedArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'; Silent = $true
        }
        @{
            Case = 'Squirrel (Update.exe --uninstall)'
            App  = @{ KeyName = 'Discord'; UninstallString = 'C:\Users\u\AppData\Local\Discord\Update.exe --uninstall' }
            Type = 'Squirrel'; Exe = 'C:\Users\u\AppData\Local\Discord\Update.exe'; ExpectedArgs = '--uninstall -s'; Silent = $true
        }
        @{
            Case = 'Chromium (--uninstall)'
            App  = @{ KeyName = 'Google Chrome'; UninstallString = '"C:\Program Files\Google\Chrome\Application\120.0\Installer\setup.exe" --uninstall --channel=stable --system-level' }
            Type = 'Chromium'; Exe = 'C:\Program Files\Google\Chrome\Application\120.0\Installer\setup.exe'; ExpectedArgs = '--uninstall --channel=stable --system-level --force-uninstall'; Silent = $true
        }
        @{
            Case = 'NSIS sem aspas e com espaço no caminho'
            App  = @{ KeyName = 'VLC'; UninstallString = 'C:\Program Files\VideoLAN\VLC\uninstall.exe' }
            Type = 'NSIS'; Exe = 'C:\Program Files\VideoLAN\VLC\uninstall.exe'; ExpectedArgs = '/S'; Silent = $true
        }
        @{
            Case = 'NSIS não duplica /S'
            App  = @{ KeyName = 'X'; UninstallString = '"C:\X\Uninst.exe" /S' }
            Type = 'NSIS'; Exe = 'C:\X\Uninst.exe'; ExpectedArgs = '/S'; Silent = $true
        }
        @{
            Case = 'InstallShield não é silencioso'
            App  = @{ KeyName = 'Y'; UninstallString = '"C:\Program Files (x86)\InstallShield Installation Information\{GUID}\setup.exe" -runfromtemp -l0x0409 -removeonly' }
            Type = 'InstallShield'; Exe = 'C:\Program Files (x86)\InstallShield Installation Information\{GUID}\setup.exe'; ExpectedArgs = '-runfromtemp -l0x0409 -removeonly'; Silent = $false
        }
        @{
            Case = 'Genérico'
            App  = @{ KeyName = 'Z'; UninstallString = '"C:\Z\remove.exe" /x' }
            Type = 'Generic'; Exe = 'C:\Z\remove.exe'; ExpectedArgs = '/x'; Silent = $false
        }
    ) {
        $Plan = Resolve-UninstallCommand -Software ([PSCustomObject]$App)

        $Plan.InstallerType | Should -Be $Type
        $Plan.Executable | Should -Be $Exe
        $Plan.Arguments | Should -Be $ExpectedArgs
        $Plan.Silent | Should -Be $Silent
    }

    It 'coloca aspas no CommandLine quando o executável tem espaço' {
        $Plan = Resolve-UninstallCommand -Software ([PSCustomObject]@{ KeyName = 'VLC'; UninstallString = 'C:\Program Files\VLC\uninstall.exe' })

        $Plan.CommandLine | Should -Be '"C:\Program Files\VLC\uninstall.exe" /S'
    }

    It 'lança erro sem comando de desinstalação' {
        { Resolve-UninstallCommand -Software ([PSCustomObject]@{ Name = 'X'; KeyName = 'X' }) } |
            Should -Throw '*No uninstall command*'
    }

    It 'aceita entrada pelo pipeline' {
        ([PSCustomObject]@{ KeyName = 'X'; UninstallString = 'C:\X\uninst.exe' } | Resolve-UninstallCommand).InstallerType |
            Should -Be 'NSIS'
    }
}

Describe 'Uninstall-RemoteSoftware' {

    BeforeAll {
        $script:App = [PSCustomObject]@{
            Name            = 'VLC'
            KeyName         = 'VLC'
            Scope           = 'Machine'
            UninstallString = 'C:\Program Files\VideoLAN\VLC\uninstall.exe'
            RegistryPath    = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\VLC'
        }
    }

    BeforeEach {
        Mock -ModuleName Software Start-Sleep { }
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode 0 }
        Mock -ModuleName Software Test-RemoteSoftwareInstalled { $false }
    }

    It 'desinstala e confirma pela remoção da chave do registro' {
        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $App

        $Result.Success | Should -BeTrue
        $Result.Verified | Should -BeTrue
        $Result.UninstallerType | Should -Be 'NSIS'

        Should -Invoke -ModuleName Software Invoke-PsExecCommand -Times 1 -ParameterFilter {
            $Executable -eq 'C:\Program Files\VideoLAN\VLC\uninstall.exe' -and $Arguments -eq '/S'
        }
    }

    It 'aguarda o programa sumir do registro (desinstalador assíncrono)' {
        $script:Calls = 0
        Mock -ModuleName Software Test-RemoteSoftwareInstalled { $script:Calls++; $script:Calls -lt 3 }

        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $App

        $Result.Success | Should -BeTrue
        Should -Invoke -ModuleName Software Test-RemoteSoftwareInstalled -Times 3 -Exactly
    }

    It 'falha quando o programa continua registrado após o tempo limite' {
        Mock -ModuleName Software Test-RemoteSoftwareInstalled { $true }
        InModuleScope Software { $script:SavedVerify = $VERIFY_TIMEOUT; $script:VERIFY_TIMEOUT = 0 }

        try {
            $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $App
        }
        finally {
            InModuleScope Software { $script:VERIFY_TIMEOUT = $script:SavedVerify }
        }

        $Result.Success | Should -BeFalse
        $Result.Verified | Should -BeFalse
        $Result.Error | Should -Match 'still registered'
    }

    It 'argumentos personalizados substituem os resolvidos' {
        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $App -Arguments ' /quiet '

        $Result.UninstallCmd | Should -Be '"C:\Program Files\VideoLAN\VLC\uninstall.exe" /quiet'
        Should -Invoke -ModuleName Software Invoke-PsExecCommand -ParameterFilter { $Arguments -eq '/quiet' }
    }

    It 'MSI exit 1605 (não instalado) é aceito' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode 1605 }

        $Msi = [PSCustomObject]@{ Name = 'M'; KeyName = '{12345678-1234-1234-1234-1234567890AB}'; WindowsInstaller = 1; UninstallString = 'MsiExec.exe /I{12345678-1234-1234-1234-1234567890AB}' }
        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $Msi

        $Result.Success | Should -BeTrue
        $Result.Verified | Should -BeNullOrEmpty
    }

    It 'usa cmd /c quando o caminho tem variáveis de ambiente' {
        $Env = [PSCustomObject]@{ Name = 'E'; KeyName = 'E'; UninstallString = '%ProgramFiles%\E\uninst.exe' }

        Uninstall-RemoteSoftware -ComputerName 'PC' -Software $Env | Out-Null

        Should -Invoke -ModuleName Software Invoke-PsExecCommand -ParameterFilter {
            $Executable -eq 'cmd.exe' -and $Arguments -eq '/c ""%ProgramFiles%\E\uninst.exe" /S"'
        }
    }

    It 'no timeout encerra o desinstalador remoto (taskkill)' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode $null -TimedOut } -ParameterFilter { $Executable -ne 'taskkill.exe' }

        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $App -TimeoutSeconds 5

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'timed out'
        Should -Invoke -ModuleName Software Invoke-PsExecCommand -ParameterFilter {
            $Executable -eq 'taskkill.exe' -and $Arguments -eq '/f /t /im "uninstall.exe"'
        }
    }

    It 'modo -UninstallCommand confia no exit code (sem verificação)' {
        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -UninstallCommand '"C:\X\unins000.exe"'

        $Result.Success | Should -BeTrue
        $Result.Verified | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Software Test-RemoteSoftwareInstalled -Times 0
    }

    It 'retorna falha (sem lançar) quando não há comando registrado' {
        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software ([PSCustomObject]@{ Name = 'X' })

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'No uninstall command'
    }
}

Describe 'Test-RemoteSoftwareInstalled' {

    It 'interpreta PRESENT / ABSENT / resposta inválida' {
        InModuleScope Software {
            Mock Invoke-PsExecCommand { [PSCustomObject]@{ Output = 'PRESENT' } }
            Test-RemoteSoftwareInstalled -ComputerName 'PC' -RegistryPath "HKLM:\x\O'Brien" | Should -BeTrue

            Mock Invoke-PsExecCommand { [PSCustomObject]@{ Output = 'ABSENT' } }
            Test-RemoteSoftwareInstalled -ComputerName 'PC' -RegistryPath 'HKLM:\x' | Should -BeFalse

            Mock Invoke-PsExecCommand { [PSCustomObject]@{ Output = '' } }
            Test-RemoteSoftwareInstalled -ComputerName 'PC' -RegistryPath 'HKLM:\x' | Should -BeNullOrEmpty
        }
    }
}
