Import-Module "$PSScriptRoot\Modules\Config.psm1"
Import-Module "$PSScriptRoot\Modules\Logger.psm1"
Import-Module "$PSScriptRoot\Modules\Connection.psm1"

Start-Log

Write-Log -Message "Universal Remote Toolkit iniciado." -Level Info

$config = Get-ToolkitConfig

Connect-RemoteComputer -ComputerName "192.168.0.10"

Stop-Log