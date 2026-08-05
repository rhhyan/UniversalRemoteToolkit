Import-Module "$PSScriptRoot\Modules\Config.psm1"
Import-Module "$PSScriptRoot\Modules\Logger.psm1"
Import-Module "$PSScriptRoot\Modules\Connection.psm1"
Import-Module "$PSScriptRoot\Modules\Execution.psm1"
Import-Module "$PSScriptRoot\Modules\ConsoleUI.psm1"
Import-Module "$PSScriptRoot\Modules\Utils.psm1"

Start-Log

try {

    Write-Log -Level Info -Message "Universal Remote Toolkit iniciado."

    $Config = Get-ToolkitConfig

    Show-MainMenu

}
catch {

    Write-Log -Level Error -Message $_.Exception.Message

}
finally {

    Stop-Log

}

$Choice = Show-MainMenu

switch ($Choice) {

    '1' {
        # Futuramente:
        # Show-ExecutionMenu
    }

    '2' {
        # Show-SoftwareMenu
    }

    '3' {
        # Show-SettingsMenu
    }

    '0' {
        Write-Host "Bye!"
    }

    default {
        Write-Host "Invalid option."
    }
}