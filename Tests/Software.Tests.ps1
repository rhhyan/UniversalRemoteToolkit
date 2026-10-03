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

Describe 'Copy-SoftwareToRemote' {

    BeforeAll {
        $script:Installer = Join-Path $TestDrive 'setup.msi'
        Set-Content -Path $Installer -Value 'x'
    }

    BeforeEach {
        Mock -ModuleName Execution Test-ComputerReachable { $true }
        # Só os caminhos UNC são simulados; o instalador de origem é real
        Mock -ModuleName Execution Test-Path { Microsoft.PowerShell.Management\Test-Path @PesterBoundParameters }
        Mock -ModuleName Execution Test-Path { $true } -ParameterFilter { $LiteralPath -like '\\*' }
        Mock -ModuleName Execution Copy-Item { }
    }

    It 'mantém RemotePath (UNC) e LocalPathOnly (caminho na máquina remota)' {
        $Result = Copy-SoftwareToRemote -ComputerName '\\PC-001' -InstallerPath $Installer

        $Result.Success | Should -BeTrue
        $Result.FileName | Should -Be 'setup.msi'
        $Result.LocalPath | Should -Be $Installer
        $Result.RemotePath | Should -Be '\\PC-001\C$\script_temp\setup.msi'
        $Result.LocalPathOnly | Should -Be 'C:\script_temp\setup.msi'
    }

    It 'faz o ping antes: máquina offline falha sem tentar copiar' {
        Mock -ModuleName Execution Test-ComputerReachable { $false }

        $Result = Copy-SoftwareToRemote -ComputerName 'PC' -InstallerPath $Installer

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'not reachable'
        $Result.RemotePath | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Execution Copy-Item -Times 0
    }

    It 'instalador inexistente mantém a mensagem de antes' {
        $Result = Copy-SoftwareToRemote -ComputerName 'PC' -InstallerPath (Join-Path $TestDrive 'nada.msi')

        $Result.Success | Should -BeFalse
        $Result.Error | Should -BeLike 'Installer file not found: *nada.msi'
        Should -Invoke -ModuleName Execution Test-ComputerReachable -Times 0
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

Describe 'Resolve-UninstallCommand (Office MSI / OffScrub)' {

    BeforeAll {
        # Bin\OffScrub falso: só o script do Office 2016 existe
        $OffScrubDir = Join-Path $TestDrive 'OffScrub'
        New-Item -ItemType Directory -Path $OffScrubDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $OffScrubDir 'OffScrub_O16msi.vbs') -Force | Out-Null

        InModuleScope Software -Parameters @{ Dir = $OffScrubDir } {
            param($Dir)
            $script:OriginalOffScrub = $OFFSCRUB_PATH
            $script:OFFSCRUB_PATH = $Dir
        }

        function New-OfficeEntry {
            param($Version = '16', $Sku = 'PROPLUS', $Programs = 'Program Files (x86)')

            [PSCustomObject]@{
                Name            = "Microsoft Office $Sku"
                KeyName         = "Office$Version.$Sku"
                UninstallString = "`"C:\$Programs\Common Files\Microsoft Shared\OFFICE$Version\Office Setup Controller\setup.exe`" /uninstall $Sku /dll OSETUP.DLL"
            }
        }
    }

    AfterAll {
        InModuleScope Software { $script:OFFSCRUB_PATH = $script:OriginalOffScrub }
    }

    It 'Office 2016 PROPLUS usa OffScrub só com o SKU' {
        $Plan = Resolve-UninstallCommand -Software (New-OfficeEntry)

        $Plan.InstallerType | Should -Be 'Office 2016 MSI (OffScrub)'
        $Plan.Silent | Should -BeTrue
        $Plan.Sku | Should -Be 'PROPLUS'
        $Plan.Executable | Should -Be 'cscript.exe'
        $Plan.Arguments | Should -Be '//nologo "C:\script_temp\OffScrub_O16msi.vbs" PROPLUS /Quiet /NoCancel /Force /Log "C:\script_temp\OffScrub"'
        $Plan.Arguments | Should -Not -Match '\bALL\b'
        $Plan.ScriptPath | Should -Be (Join-Path $OffScrubDir 'OffScrub_O16msi.vbs')
    }

    It 'extrai o SKU STANDARD' {
        $Plan = Resolve-UninstallCommand -Software (New-OfficeEntry -Sku 'Standard')

        $Plan.Sku | Should -Be 'STANDARD'
        $Plan.Arguments | Should -Match '\.vbs" STANDARD /Quiet'
    }

    It 'Office 2013 sem OffScrub_O15msi.vbs continua Genérico' {
        $Plan = Resolve-UninstallCommand -Software (New-OfficeEntry -Version '15' -Programs 'Program Files')

        $Plan.InstallerType | Should -Be 'Generic'
        $Plan.Silent | Should -BeFalse
    }

    It 'Office 2013 usa OffScrub quando o script existe' {
        $O15 = Join-Path $OffScrubDir 'OffScrub_O15msi.vbs'
        New-Item -ItemType File -Path $O15 -Force | Out-Null

        try {
            $Plan = Resolve-UninstallCommand -Software (New-OfficeEntry -Version '15' -Programs 'Program Files')
        }
        finally {
            Remove-Item -LiteralPath $O15 -Force
        }

        $Plan.InstallerType | Should -Be 'Office 2013 MSI (OffScrub)'
        $Plan.Arguments | Should -Match 'OffScrub_O15msi\.vbs" PROPLUS '
    }

    It 'setup.exe de outro programa não é tratado como Office' {
        $Plan = Resolve-UninstallCommand -Software ([PSCustomObject]@{ KeyName = 'X'; UninstallString = '"C:\X\setup.exe" /uninstall PROPLUS' })

        $Plan.InstallerType | Should -Be 'Generic'
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
            $Executable -eq 'C:\Program Files\VideoLAN\VLC\uninstall.exe' -and $Arguments -eq '/S' -and -not $System
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

Describe 'Uninstall-RemoteSoftware (Office MSI / OffScrub)' {

    BeforeAll {
        $OffScrubDir = Join-Path $TestDrive 'OffScrubBin'
        New-Item -ItemType Directory -Path $OffScrubDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $OffScrubDir 'OffScrub_O16msi.vbs') -Force | Out-Null

        InModuleScope Software -Parameters @{ Dir = $OffScrubDir } {
            param($Dir)
            $script:OriginalOffScrub = $OFFSCRUB_PATH
            $script:OFFSCRUB_PATH = $Dir
        }

        # Pasta que faz o papel de \\PC\C$\script_temp
        $script:RemoteDir = Join-Path $TestDrive 'remote'

        $script:Office = [PSCustomObject]@{
            Name            = 'Microsoft Office Professional Plus 2016'
            KeyName         = 'Office16.PROPLUS'
            Scope           = 'Machine'
            UninstallString = '"C:\Program Files (x86)\Common Files\Microsoft Shared\OFFICE16\Office Setup Controller\setup.exe" /uninstall PROPLUS /dll OSETUP.DLL'
            RegistryPath    = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Office16.PROPLUS'
        }
    }

    AfterAll {
        InModuleScope Software { $script:OFFSCRUB_PATH = $script:OriginalOffScrub }
    }

    BeforeEach {
        # Simula a cópia: cria o .vbs e a pasta de log "remotos"
        New-Item -ItemType Directory -Path (Join-Path $RemoteDir 'OffScrub') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $RemoteDir 'OffScrub_O16msi.vbs') -Force | Out-Null

        Mock -ModuleName Software Start-Sleep { }
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode 0 }
        Mock -ModuleName Software Test-RemoteSoftwareInstalled { $false }
        Mock -ModuleName Software Copy-SoftwareToRemote {
            [PSCustomObject]@{ Success = $true; RemotePath = (Join-Path $RemoteDir 'OffScrub_O16msi.vbs') }
        }
    }

    It 'copia o script, executa com timeout de 3600 s, verifica e limpa' {
        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $Office

        $Result.Success | Should -BeTrue
        $Result.Verified | Should -BeTrue
        $Result.RebootRequired | Should -BeFalse
        $Result.UninstallerType | Should -Be 'Office 2016 MSI (OffScrub)'

        Should -Invoke -ModuleName Software Copy-SoftwareToRemote -Times 1 -ParameterFilter {
            $ComputerName -eq 'PC' -and $InstallerPath -eq (Join-Path $OffScrubDir 'OffScrub_O16msi.vbs')
        }
        Should -Invoke -ModuleName Software Invoke-PsExecCommand -Times 1 -ParameterFilter {
            $Executable -eq 'cscript.exe' -and
            $Arguments -eq '//nologo "C:\script_temp\OffScrub_O16msi.vbs" PROPLUS /Quiet /NoCancel /Force /Log "C:\script_temp\OffScrub"' -and
            $TimeoutSeconds -eq 3600 -and
            $System
        }

        Join-Path $RemoteDir 'OffScrub_O16msi.vbs' | Should -Not -Exist
        Join-Path $RemoteDir 'OffScrub' | Should -Not -Exist
    }

    It 'respeita -TimeoutSeconds informado' {
        Uninstall-RemoteSoftware -ComputerName 'PC' -Software $Office -TimeoutSeconds 120 | Out-Null

        Should -Invoke -ModuleName Software Invoke-PsExecCommand -ParameterFilter { $TimeoutSeconds -eq 120 }
    }

    It 'exit code <Code>: sucesso=<Ok>, reboot=<Reboot>' -ForEach @(
        @{ Code = 2;    Ok = $true;  Reboot = $true }
        @{ Code = 32;   Ok = $true;  Reboot = $true }
        @{ Code = 8;    Ok = $true;  Reboot = $false }
        @{ Code = 10;   Ok = $true;  Reboot = $true }
        @{ Code = 3010; Ok = $true;  Reboot = $true }
        @{ Code = 1;    Ok = $false; Reboot = $false }
        @{ Code = 25;   Ok = $false; Reboot = $false }
        @{ Code = -1073741510; Ok = $false; Reboot = $false }
    ) {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode $Code }

        # Na falha o programa continua registrado
        if (-not $Ok) {
            Mock -ModuleName Software Test-RemoteSoftwareInstalled { $true }
        }

        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $Office

        $Result.Success | Should -Be $Ok
        $Result.RebootRequired | Should -Be $Reboot
        $Result.ExitCode | Should -Be $Code

        # O .vbs sempre é apagado; a pasta de log só no sucesso
        Join-Path $RemoteDir 'OffScrub_O16msi.vbs' | Should -Not -Exist

        if ($Ok) {
            Join-Path $RemoteDir 'OffScrub' | Should -Not -Exist
        }
        else {
            Join-Path $RemoteDir 'OffScrub' | Should -Exist
            $Result.Error | Should -BeLike '*Check the OffScrub log in C:\script_temp\OffScrub.'
        }
    }

    It 'falha sem verificação de registro também mantém o log' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode 1 -ErrorText 'OffScrub failed' }

        $NoRegistry = $Office.PSObject.Copy()
        $NoRegistry.RegistryPath = $null

        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $NoRegistry

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Be 'OffScrub failed. Check the OffScrub log in C:\script_temp\OffScrub.'
        Join-Path $RemoteDir 'OffScrub_O16msi.vbs' | Should -Not -Exist
        Join-Path $RemoteDir 'OffScrub' | Should -Exist
    }

    It 'falha na cópia não executa nada' {
        Mock -ModuleName Software Copy-SoftwareToRemote { [PSCustomObject]@{ Success = $false; Error = 'Access denied' } }

        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $Office

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'Access denied'
        Should -Invoke -ModuleName Software Invoke-PsExecCommand -Times 0
    }

    It 'no timeout não mata o OffScrub nem apaga os arquivos' {
        Mock -ModuleName Software Invoke-PsExecCommand { New-PsExecResult -ExitCode $null -TimedOut }

        $Result = Uninstall-RemoteSoftware -ComputerName 'PC' -Software $Office

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Match 'may still be running'
        $Result.Error | Should -BeLike '*Check the OffScrub log in C:\script_temp\OffScrub.'
        Should -Invoke -ModuleName Software Invoke-PsExecCommand -Times 1
        Join-Path $RemoteDir 'OffScrub_O16msi.vbs' | Should -Exist
        Join-Path $RemoteDir 'OffScrub' | Should -Exist
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
