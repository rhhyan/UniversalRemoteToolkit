# Carrega os módulos do toolkit na mesma ordem do UniversalRemoteToolkit.ps1

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:ModulesPath = Join-Path $RepoRoot 'src/Modules'

function Import-ToolkitModules {
    foreach ($Module in 'Config', 'Logger', 'Connection', 'Execution', 'ConsoleUI', 'Utils', 'Software', 'Scripts') {
        Import-Module (Join-Path $script:ModulesPath "$Module.psm1") -Force -DisableNameChecking -ErrorAction Stop
    }
}

# Abre uma sessão de log em um arquivo temporário, sem saída no console
function Start-TestLog {
    param([Parameter(Mandatory)][string]$LogFile)

    InModuleScope Logger -Parameters @{ LogFile = $LogFile } {
        param($LogFile)

        $script:LogSession = @{
            StartedAt     = Get-Date
            LogFile       = $LogFile
            EnableConsole = $false
        }
    }
}
