function Show-MainMenu {

    [CmdletBinding()]
    param()

    Clear-Host

    Write-Host ""
    Write-Host "=========================================================="
    Write-Host "           Universal Remote Toolkit (URT)"
    Write-Host "=========================================================="
    Write-Host ""
    Write-Host "  Remote Administration Toolkit"
    Write-Host ""
    Write-Host "----------------------------------------------------------"
    Write-Host ""
    Write-Host "  [1] Remote Command Execution"
    Write-Host "  [2] Software Installation"
    Write-Host "  [3] Software Removal"
    Write-Host "  [4] Computer Information"
    Write-Host "  [5] Settings"
    Write-Host ""
    Write-Host "  [0] Exit"
    Write-Host ""
    Write-Host "----------------------------------------------------------"
    Write-Host ""

    return (Read-Host "Select an option")
}

Export-ModuleMember -Function Show-MainMenu