<#
.SYNOPSIS
    Otimizacao do Windows - versao remota (nao interativa) para o UTR.

.DESCRIPTION
    Porta do "Otimizacao do Windows.bat" para execucao via PsExec.
    Nao usa menus nem "pause": a acao e escolhida por parametro.

    Acoes:
      CleanProfiles   - Remove perfis BC, XTR, XTC, TEMP e TH (exceto excecoes),
                        remove as chaves ProfileList correspondentes (inclusive TH),
                        limpa C:\Windows\Temp e roda SFC /SCANNOW.
      Debloat         - Remove apps pre-instalados (todos os usuarios + provisionados).
      RepairImage     - DISM /Online /Cleanup-Image /RestoreHealth.
      VisualEffects   - Ajusta efeitos visuais para "melhor desempenho".
      DisableServices - Desativa Spooler, WSearch, SysMain + ajustes de notificacao.

.PARAMETER Action
    Acao a executar.

.PARAMETER KeepProfiles
    Matriculas TH a manter, separadas por virgula, ponto e virgula ou espaco.

.PARAMETER SkipSfc
    Nao executa SFC /SCANNOW ao final do CleanProfiles.

.NOTES
    Compativel com Windows PowerShell 5.1. Somente ASCII (saida via PsExec).
    Exit code: 0 = sucesso, 1 = falha, 2 = sucesso parcial.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('CleanProfiles', 'Debloat', 'RepairImage', 'VisualEffects', 'DisableServices')]
    [string]$Action,

    [Parameter()]
    [string]$KeepProfiles = '',

    [Parameter()]
    [switch]$SkipSfc
)

$ErrorActionPreference = 'Continue'
$LogDir  = 'C:\script_temp'
$LogFile = Join-Path $LogDir 'Log_script_otimizacao.txt'
$script:Failures = 0

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Step {
    param([string]$Level, [string]$Message)
    $Line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $Line
    Add-Content -Path $LogFile -Value $Line -ErrorAction SilentlyContinue
    if ($Level -eq 'ERRO') { $script:Failures++ }
}

# ------------------------------------------------------------
# Helper: grava um valor de registro em todos os perfis
# (hives carregados em HKU + perfil Default para novos usuarios)
# ------------------------------------------------------------
function Set-RegistryForAllUsers {
    param(
        [string]$SubKey,
        [string]$Name,
        [ValidateSet('REG_DWORD', 'REG_SZ', 'REG_BINARY')]
        [string]$Type,
        [string]$Data
    )

    $Hives = @(
        Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } |
            ForEach-Object { $_.PSChildName }
    )

    $DefaultLoaded = $false
    $DefaultHive = 'C:\Users\Default\NTUSER.DAT'
    if (Test-Path $DefaultHive) {
        & reg.exe load 'HKU\UTR_Default' $DefaultHive 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $DefaultLoaded = $true
            $Hives += 'UTR_Default'
        }
    }

    foreach ($Hive in $Hives) {
        & reg.exe add "HKU\$Hive\$SubKey" /v $Name /t $Type /d $Data /f 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Step 'AVISO' "Falha ao gravar $SubKey\$Name em HKU\$Hive"
        }
    }

    if ($DefaultLoaded) {
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        & reg.exe unload 'HKU\UTR_Default' 2>&1 | Out-Null
    }

    Write-Step 'OK' "$SubKey\$Name aplicado em $($Hives.Count) perfil(is)"
}

# ------------------------------------------------------------
# 1 - Limpeza de perfis
# ------------------------------------------------------------
function Invoke-CleanProfiles {
    $Exceptions = @($KeepProfiles -split '[,; ]+' | Where-Object { $_ })
    $Ignore = @('All Users', 'Default', 'Default User', 'Public', 'SISTEMA',
                'SUPERVISOR', 'Manager', $env:USERNAME)

    Write-Step 'INFO' "Excecoes TH informadas: $(if ($Exceptions) { $Exceptions -join ', ' } else { '(nenhuma)' })"

    $CimProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Special })

    $Deleted = @(); $Kept = @(); $Skipped = @()

    foreach ($Folder in Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue) {
        $Name = $Folder.Name
        if ($Ignore -contains $Name) { continue }

        $Delete = $false
        if ($Name -like 'BC*' -or $Name -like 'XTR*' -or $Name -like 'XTC*' -or $Name -like 'TEMP*') {
            $Delete = $true
        }
        elseif ($Name -like 'TH*') {
            if ($Exceptions -contains $Name) { $Kept += $Name } else { $Delete = $true }
        }
        if (-not $Delete) { continue }

        $UserProfile = $CimProfiles | Where-Object { $_.LocalPath -eq $Folder.FullName } | Select-Object -First 1

        if ($UserProfile -and $UserProfile.Loaded) {
            Write-Step 'AVISO' "Perfil em uso, ignorado: $Name"
            $Skipped += $Name
            continue
        }

        try {
            if ($UserProfile) {
                # Remove pasta + chave ProfileList de uma vez
                Remove-CimInstance -InputObject $UserProfile -ErrorAction Stop
            }
            else {
                & cmd.exe /c "rd /s /q `"$($Folder.FullName)`"" 2>&1 | Out-Null
            }

            if (Test-Path $Folder.FullName) {
                & cmd.exe /c "rd /s /q `"$($Folder.FullName)`"" 2>&1 | Out-Null
            }

            if (Test-Path $Folder.FullName) {
                Write-Step 'ERRO' "Pasta nao removida por completo: $Name"
            }
            else {
                Write-Step 'OK' "Perfil removido: $Name"
                $Deleted += $Name
            }
        }
        catch {
            Write-Step 'ERRO' "Falha ao remover $Name : $($_.Exception.Message)"
        }
    }

    # Chaves orfas no ProfileList (pastas que nao existem mais)
    $ProfileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($Key in Get-ChildItem $ProfileList -ErrorAction SilentlyContinue) {
        $Path = (Get-ItemProperty -Path $Key.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $Path) { continue }
        $Leaf = Split-Path $Path -Leaf
        $Target = ($Leaf -like 'BC*' -or $Leaf -like 'XTR*' -or $Leaf -like 'XTC*' -or $Leaf -like 'TEMP*' -or
                   ($Leaf -like 'TH*' -and $Exceptions -notcontains $Leaf))
        if ($Target -and -not (Test-Path $Path)) {
            try {
                Remove-Item -Path $Key.PSPath -Recurse -Force -ErrorAction Stop
                Write-Step 'OK' "Chave ProfileList orfa removida: $Leaf ($($Key.PSChildName))"
            }
            catch {
                Write-Step 'ERRO' "Falha ao remover chave de $Leaf : $($_.Exception.Message)"
            }
        }
    }

    Write-Step 'INFO' "Resumo: removidos=$($Deleted.Count) | mantidos(excecao)=$($Kept.Count) | em uso=$($Skipped.Count)"
    if ($Kept) { Write-Step 'INFO' "Mantidos: $($Kept -join ', ')" }

    # Substitui o cleanmgr (GUI, trava via PsExec)
    Write-Step 'INFO' 'Limpando C:\Windows\Temp...'
    Get-ChildItem 'C:\Windows\Temp' -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step 'OK' 'C:\Windows\Temp limpo (arquivos em uso foram mantidos)'

    if (-not $SkipSfc) {
        Write-Step 'INFO' 'Executando SFC /SCANNOW (pode levar varios minutos)...'
        & sfc.exe /scannow | Out-Null
        switch ($LASTEXITCODE) {
            0       { Write-Step 'OK' 'SFC concluido' }
            default { Write-Step 'AVISO' "SFC retornou codigo $LASTEXITCODE - verifique CBS.log ou rode RepairImage (DISM)" }
        }
    }
}

# ------------------------------------------------------------
# 2 - Debloat
# ------------------------------------------------------------
function Invoke-Debloat {
    $Packages = @(
        'MicrosoftCorporationII.MicrosoftFamily', 'Clipchamp.Clipchamp', 'Microsoft.3DBuilder',
        'Microsoft.Microsoft3DViewer', 'Microsoft.BingWeather', 'Microsoft.BingSports',
        'Microsoft.BingFinance', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.BingNews',
        'Microsoft.Office.OneNote', 'Microsoft.Office.Sway', 'Microsoft.WindowsPhone',
        'Microsoft.CommsPhone', 'Microsoft.YourPhone', 'Microsoft.Getstarted',
        'Microsoft.549981C3F5F10', 'Microsoft.Messaging', 'Microsoft.WindowsSoundRecorder',
        'Microsoft.MixedReality.Portal', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsCamera',
        'Microsoft.WindowsMaps', 'Microsoft.MinecraftUWP', 'Microsoft.People', 'Microsoft.Wallet',
        'Microsoft.Print3D', 'Microsoft.MicrosoftSolitaireCollection',
        'microsoft.windowscommunicationsapps', 'Microsoft.SkypeApp', 'Microsoft.GroupMe10',
        'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.GetHelp', 'Microsoft.XboxApp',
        'Microsoft.Xbox.TCUI', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay',
        'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.GamingApp'
    )

    $Provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)

    foreach ($Pkg in $Packages) {
        $Installed = @(Get-AppxPackage -AllUsers -Name $Pkg -ErrorAction SilentlyContinue)
        foreach ($App in $Installed) {
            try {
                Remove-AppxPackage -Package $App.PackageFullName -AllUsers -ErrorAction Stop
                Write-Step 'OK' "Removido: $($App.Name)"
            }
            catch {
                Write-Step 'AVISO' "Nao removido: $($App.Name) - $($_.Exception.Message)"
            }
        }

        # Impede reinstalacao em novos perfis
        foreach ($Prov in ($Provisioned | Where-Object { $_.DisplayName -eq $Pkg })) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $Prov.PackageName -ErrorAction Stop | Out-Null
                Write-Step 'OK' "Desprovisionado: $Pkg"
            }
            catch {
                Write-Step 'AVISO' "Falha ao desprovisionar $Pkg - $($_.Exception.Message)"
            }
        }
    }

    $Deprov = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
    foreach ($Id in 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp',
                    'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay') {
        & reg.exe add "$Deprov\$($Id)_8wekyb3d8bbwe" /f 2>&1 | Out-Null
    }

    foreach ($Svc in 'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc') {
        if (Get-Service -Name $Svc -ErrorAction SilentlyContinue) {
            Stop-Service -Name $Svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $Svc -StartupType Manual -ErrorAction SilentlyContinue
            Write-Step 'OK' "Servico $Svc -> Manual"
        }
    }
}

# ------------------------------------------------------------
# 3 - DISM
# ------------------------------------------------------------
function Invoke-RepairImage {
    Write-Step 'INFO' 'Executando DISM /RestoreHealth (pode levar 10-30 min)...'
    & DISM.exe /Online /Cleanup-Image /RestoreHealth /NoRestart | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Step 'OK' 'DISM concluido com sucesso'
    }
    else {
        Write-Step 'ERRO' "DISM retornou codigo $LASTEXITCODE - veja C:\Windows\Logs\DISM\dism.log"
    }
}

# ------------------------------------------------------------
# 4 - Efeitos visuais (melhor desempenho)
# ------------------------------------------------------------
function Invoke-VisualEffects {
    Set-RegistryForAllUsers 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 'REG_DWORD' '2'
    Set-RegistryForAllUsers 'Control Panel\Desktop' 'UserPreferencesMask' 'REG_BINARY' '9012038010000000'
    Set-RegistryForAllUsers 'Control Panel\Desktop\WindowMetrics' 'MinAnimate' 'REG_SZ' '0'
    Set-RegistryForAllUsers 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 'REG_DWORD' '0'
    Write-Step 'INFO' 'Efeitos visuais aplicados - valem a partir do proximo logon do usuario'
}

# ------------------------------------------------------------
# 5 - Servicos e ajustes
# ------------------------------------------------------------
function Invoke-DisableServices {
    Set-RegistryForAllUsers 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
    Set-RegistryForAllUsers 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
    Set-RegistryForAllUsers 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 'REG_DWORD' '0'
    Set-RegistryForAllUsers 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 'REG_DWORD' '0'
    Set-RegistryForAllUsers 'Control Panel\Desktop' 'MenuShowDelay' 'REG_SZ' '0'
    Set-RegistryForAllUsers 'Control Panel\Mouse' 'MouseHoverTime' 'REG_SZ' '0'

    foreach ($Svc in 'Spooler', 'WSearch', 'SysMain') {
        if (-not (Get-Service -Name $Svc -ErrorAction SilentlyContinue)) {
            Write-Step 'INFO' "Servico $Svc nao existe nesta maquina"
            continue
        }
        try {
            Stop-Service -Name $Svc -Force -ErrorAction Stop
            Set-Service -Name $Svc -StartupType Disabled -ErrorAction Stop
            Write-Step 'OK' "Servico $Svc parado e desativado"
        }
        catch {
            Write-Step 'ERRO' "Falha no servico $Svc : $($_.Exception.Message)"
        }
    }
}

# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------
Add-Content -Path $LogFile -Value ("`r`n==== Otimizacao [{0}] - {1} - executado por {2} ====" -f $Action, (Get-Date), $env:USERNAME) -ErrorAction SilentlyContinue

try {
    switch ($Action) {
        'CleanProfiles'   { Invoke-CleanProfiles }
        'Debloat'         { Invoke-Debloat }
        'RepairImage'     { Invoke-RepairImage }
        'VisualEffects'   { Invoke-VisualEffects }
        'DisableServices' { Invoke-DisableServices }
    }
}
catch {
    Write-Step 'ERRO' "Erro inesperado: $($_.Exception.Message)"
    exit 1
}

Write-Step 'INFO' "Log completo em $LogFile"
if ($script:Failures -gt 0) { exit 2 }
exit 0
