function Connect-RemoteComputer {

    param(
        [string]$ComputerName
    )

    Write-Log -Message "Tentando conectar em $ComputerName..." -Level Info

    # PsExec

    Write-Log -Message "Conexão realizada com sucesso." -Level Success
}


function Get-PsExecPath {
    [CmdletBinding()]
    param()

    process {
        try {
            $ToolkitRoot = Resolve-Path (
                Join-Path $PSScriptRoot "./Bin/PsExec.exe"
            )
            if (Test-Path $psExecPath) {
                Write-Log -Level Success -Message "PsExec localizado: $psExecPath"
                return $true
            }

            Write-Log -Level Error -Message "PsExec não localizado."
            return $false
        }
        catch {
            Write-Log `
                -Level Error `
                -Message "Erro ao verificar PsExec: $($_.Exception.Message)"
        }
    }
}

function Test-ComputerReachable {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    process {

        try {
            # Escreve no Log
            Write-Log `
                -Level Info `
                -Message "Verificando computador $ComputerName..."
            # Teste Ping
            if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop) {

                Write-Log `
                    -Level Success `
                    -Message "Computador $ComputerName está online."

                return $true
            }

            Write-Log `
                -Level Warning `
                -Message "Computador $ComputerName não respondeu."

            return $false

    }
        catch {

            Write-Log `
                -Level Error `
                -Message "Erro durante Test-Connection: $($_.Exception.Message)"

            return $false
        }

    }
}


<#
function ... {

    [CmdletBinding()]
    param()

    process {

        try {

            ...

            Write-Log ...

            return $true

        }
        catch {

            Write-Log ...

            return $false

        }

    }
}
#>