<#
.SYNOPSIS
    Ativacao Windows/Office via KMS corporativo - versao remota para o UTR.

.DESCRIPTION
    Porta do "Ativar WindowsOffice Atualizado.bat" para execucao via PsExec.

    Diferencas em relacao ao .bat:
      - Office: detecta sozinho se e 32 ou 64 bits (Office16/Office15).
      - Windows: usa cscript slmgr.vbs (o slmgr normal abre popup e trava no PsExec).
      - Windows: so instala a chave GVLK se a maquina ainda nao for cliente KMS,
        e escolhe a chave pela edicao (Pro/Enterprise).
      - Valida o resultado consultando o status de licenca.

.PARAMETER Target
    Office | Windows | Status

.PARAMETER KmsHost
    Servidor KMS (padrao: kmspw01.oi.corp.net).

.NOTES
    Compativel com Windows PowerShell 5.1. Somente ASCII.
    Exit code: 0 = ativado/ok, 1 = falha.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Office', 'Windows', 'Status')]
    [string]$Target,

    [Parameter()]
    [string]$KmsHost = 'kmspw01.oi.corp.net'
)

$ErrorActionPreference = 'Continue'
$WindowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'

# Chaves GVLK publicas da Microsoft (KMS client setup keys)
$Gvlk = @{
    'Professional'           = 'W269N-WFGWX-YVC9B-4J6C9-T83GX'
    'ProfessionalN'          = 'MH37W-N47XK-V7XM9-C7227-GCQG9'
    'Enterprise'             = 'NPPR9-FWDCX-D2C8J-H872K-2YT43'
    'EnterpriseN'            = 'DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4'
    'Education'              = 'NW6C2-QMPVW-D7KKK-3GKT6-VCFB2'
    'ProfessionalWorkstation' = 'NRG8B-VKK3Q-CXVCJ-9G2XF-6Q84J'
}

function Write-Step {
    param([string]$Level, [string]$Message)
    Write-Host ("[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)
}

function Get-WindowsLicense {
    Get-CimInstance -ClassName SoftwareLicensingProduct `
        -Filter "ApplicationID='$WindowsAppId' AND PartialProductKey IS NOT NULL" `
        -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-LicenseStatusText {
    param([int]$Code)
    switch ($Code) {
        0 { 'Nao licenciado' }
        1 { 'ATIVADO' }
        2 { 'Periodo de carencia (OOB)' }
        3 { 'Carencia (OOT)' }
        4 { 'Nao genuino' }
        5 { 'Notificacao' }
        6 { 'Carencia estendida' }
        default { "Desconhecido ($Code)" }
    }
}

function Get-OsppPath {
    $Candidates = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs",
        "$env:ProgramFiles\Microsoft Office\Office15\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office15\ospp.vbs"
    )
    $Candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Invoke-Cscript {
    param([string]$Script, [string[]]$Arguments)
    $Out = & cscript.exe //nologo $Script @Arguments 2>&1 | Out-String
    [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $Out.Trim() }
}

# ------------------------------------------------------------
# Office
# ------------------------------------------------------------
function Invoke-OfficeActivation {
    $Ospp = Get-OsppPath
    if (-not $Ospp) {
        Write-Step 'ERRO' 'ospp.vbs nao encontrado - Office 2013/2016+ nao instalado?'
        return $false
    }

    $Arch = if ($Ospp -like '*(x86)*') { '32 bits' } else { '64 bits' }
    Write-Step 'INFO' "Office $Arch detectado: $Ospp"

    # ospp /sethst nao aceita "host:porta"; a porta vai em /setprt
    $KmsName, $KmsPort = $KmsHost -split ':', 2

    $r = Invoke-Cscript $Ospp @("/sethst:$KmsName")
    Write-Step 'INFO' "sethst -> $KmsName"

    if ($KmsPort) {
        Invoke-Cscript $Ospp @("/setprt:$KmsPort") | Out-Null
        Write-Step 'INFO' "setprt -> $KmsPort"
    }

    $r = Invoke-Cscript $Ospp @('/act')
    $r.Output -split "`r?`n" | Where-Object { $_ -match 'LICENSE NAME|successful|ERROR' } |
        ForEach-Object { Write-Step 'INFO' $_.Trim() }

    if ($r.Output -match 'Product activation successful') {
        Write-Step 'OK' 'Office ativado com sucesso'
        return $true
    }
    Write-Step 'ERRO' 'Office NAO foi ativado - verifique acesso ao KMS (porta 1688)'
    return $false
}

# ------------------------------------------------------------
# Windows
# ------------------------------------------------------------
function Invoke-WindowsActivation {
    $Slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
    $Edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    Write-Step 'INFO' "Edicao do Windows: $Edition"

    $Lic = Get-WindowsLicense
    $IsKmsClient = $Lic -and ($Lic.Description -match 'VOLUME_KMSCLIENT')

    if (-not $IsKmsClient) {
        if ($Gvlk.ContainsKey($Edition)) {
            Write-Step 'INFO' 'Instalando chave GVLK (KMS client)...'
            $r = Invoke-Cscript $Slmgr @('/ipk', $Gvlk[$Edition])
            if ($r.ExitCode -ne 0) { Write-Step 'AVISO' "ipk: $($r.Output)" }
        }
        else {
            Write-Step 'AVISO' "Sem GVLK mapeada para '$Edition' - mantendo chave atual"
        }
    }
    else {
        Write-Step 'INFO' 'Maquina ja e cliente KMS - chave mantida'
    }

    Invoke-Cscript $Slmgr @('/skms', $KmsHost) | Out-Null
    Write-Step 'INFO' "skms -> $KmsHost"

    $r = Invoke-Cscript $Slmgr @('/ato')
    Write-Step 'INFO' ($r.Output -replace "`r?`n", ' ')

    $Lic = Get-WindowsLicense
    if ($Lic -and $Lic.LicenseStatus -eq 1) {
        Write-Step 'OK' 'Windows ativado com sucesso'
        return $true
    }
    Write-Step 'ERRO' "Windows NAO ativado - status: $(Get-LicenseStatusText $Lic.LicenseStatus)"
    return $false
}

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------
function Show-ActivationStatus {
    $Lic = Get-WindowsLicense
    if ($Lic) {
        Write-Step 'INFO' "Windows : $(Get-LicenseStatusText $Lic.LicenseStatus) | $($Lic.Name) | KMS: $($Lic.KeyManagementServiceMachine)"
    }
    else {
        Write-Step 'AVISO' 'Windows : nenhuma licenca encontrada'
    }

    $Ospp = Get-OsppPath
    if ($Ospp) {
        $r = Invoke-Cscript $Ospp @('/dstatus')
        $r.Output -split "`r?`n" |
            Where-Object { $_ -match 'LICENSE NAME|LICENSE STATUS|KMS machine name|REMAINING GRACE' } |
            ForEach-Object { Write-Step 'INFO' ("Office  : " + $_.Trim()) }
    }
    else {
        Write-Step 'INFO' 'Office  : ospp.vbs nao encontrado'
    }
    return $true
}

# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------
try {
    $Ok = switch ($Target) {
        'Office'  { Invoke-OfficeActivation }
        'Windows' { Invoke-WindowsActivation }
        'Status'  { Show-ActivationStatus }
    }
    if ($Ok) { exit 0 } else { exit 1 }
}
catch {
    Write-Step 'ERRO' "Erro inesperado: $($_.Exception.Message)"
    exit 1
}
