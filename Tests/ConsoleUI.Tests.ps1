# Testes do módulo ConsoleUI (entrada do usuário e renderização)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-ToolkitModules

    # Simula a digitação do usuário: cada chamada de Read-Host consome uma resposta
    function Set-UserInput {
        param([string[]]$Answers)

        $script:Answers = [System.Collections.Queue]::new([object[]]$Answers)
        Mock -ModuleName ConsoleUI Read-Host { $script:Answers.Dequeue() }
    }

    Mock -ModuleName ConsoleUI Write-Host { }
}

Describe 'Format-CenteredText' {

    It 'centraliza com padding à esquerda' {
        Format-CenteredText -Text 'ab' -Width 6 | Should -Be '  ab'
    }

    It 'mantém texto maior que a largura' {
        Format-CenteredText -Text 'abcdef' -Width 3 | Should -Be 'abcdef'
    }

    It 'aceita texto vazio (só padding à esquerda)' {
        Format-CenteredText -Text '' -Width 4 | Should -Be '  '
    }
}

Describe 'Read-MenuSelection' {

    It 'ignora entradas inválidas até receber uma opção válida' {
        Set-UserInput 'abc', '9', '', '2'

        Read-MenuSelection -ValidOptions @(0, 1, 2) | Should -Be 2
        Should -Invoke -ModuleName ConsoleUI Read-Host -Times 4 -Exactly
    }

    It 'retorna inteiro' {
        Set-UserInput ' 0 '

        Read-MenuSelection -ValidOptions @(0, 1) | Should -BeOfType [int]
    }
}

Describe 'Read-UserInput' {

    It 'remove espaços' {
        Set-UserInput '  PC-001  '
        Read-UserInput -Prompt 'x' | Should -Be 'PC-001'
    }

    It 'usa o valor padrão quando vazio' {
        Set-UserInput ''
        Read-UserInput -Prompt 'x' -Default 'abc' | Should -Be 'abc'
    }

    It 'retorna string vazia quando Read-Host retorna $null' {
        Mock -ModuleName ConsoleUI Read-Host { $null }
        Read-UserInput -Prompt 'x' | Should -Be ''
    }
}

Describe 'Read-Confirmation' {

    It '"<Answer>" => <Expected>' -ForEach @(
        @{ Answer = 's'; Expected = $true }
        @{ Answer = 'SIM'; Expected = $true }
        @{ Answer = ' y '; Expected = $true }
        @{ Answer = 'yes'; Expected = $true }
        @{ Answer = ''; Expected = $false }
        @{ Answer = 'n'; Expected = $false }
        @{ Answer = 'talvez'; Expected = $false }
    ) {
        Set-UserInput $Answer
        Read-Confirmation -Prompt 'ok?' | Should -Be $Expected
    }
}

Describe 'Read-ItemSelection' {

    It 'lista vazia => $null sem perguntar' {
        Set-UserInput @()
        Read-ItemSelection -Items @() | Should -BeNullOrEmpty
        Should -Invoke -ModuleName ConsoleUI Read-Host -Times 0
    }

    It 'um item => retorna direto' {
        Set-UserInput @()
        Read-ItemSelection -Items @('a') | Should -Be 'a'
        Should -Invoke -ModuleName ConsoleUI Read-Host -Times 0
    }

    It 'vários itens => retorna o escolhido' {
        Set-UserInput '2'
        Read-ItemSelection -Items @('a', 'b', 'c') | Should -Be 'b'
    }

    It '0 cancela' {
        Set-UserInput '0'
        Read-ItemSelection -Items @('a', 'b') | Should -BeNullOrEmpty
    }

    It 'rejeita número fora da lista' {
        Set-UserInput '3', '1'
        Read-ItemSelection -Items @('a', 'b') | Should -Be 'a'
    }

    It 'usa DisplayProperty para exibir' {
        Set-UserInput '1'
        Read-ItemSelection -Items @([PSCustomObject]@{ N = 'x' }, [PSCustomObject]@{ N = 'y' }) -DisplayProperty { "item $($_.N)" } | Out-Null

        Should -Invoke -ModuleName ConsoleUI Write-Host -ParameterFilter { $Object -eq 'item y' }
    }
}

Describe 'Renderização' {

    It 'Show-Banner não falha com título maior que a caixa' {
        { Show-Banner -Title ('x' * 300) -Subtitle 'sub' -Width 20 } | Should -Not -Throw
    }

    It 'Show-MainMenu mostra a opção 0 por último' {
        $script:Keys = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName ConsoleUI Write-MenuOption { $script:Keys.Add("$Key") }

        Show-MainMenu -MenuItems @{ 0 = 'Sair'; 2 = 'B'; 1 = 'A' }

        $script:Keys | Should -Be @('1', '2', '0')
    }

    It 'Show-Section, Show-Properties e Write-Status não falham' {
        { Show-Section -Title ('t' * 100) } | Should -Not -Throw
        { Show-Properties -Properties ([ordered]@{ A = $null; Longo = '' ; C = 0 }) } | Should -Not -Throw
        { Show-Properties -Properties @{} } | Should -Not -Throw
        foreach ($Status in 'Running', 'Success', 'Warning', 'Error', 'Info') {
            { Write-Status -Status $Status -Message 'm' } | Should -Not -Throw
        }
    }

    It 'Show-ExecutionResult com -Pause $false não lê entrada' {
        Set-UserInput @()

        { Show-ExecutionResult -Status Success -Message 'ok' -Properties ([ordered]@{ A = 1 }) -Details "l1`r`nl2" -DetailsTitle 'Out' -Pause $false } |
            Should -Not -Throw
        Should -Invoke -ModuleName ConsoleUI Read-Host -Times 0
    }

    It 'Show-ExecutionResult aguarda Enter por padrão' {
        Set-UserInput ''

        Show-ExecutionResult -Status Info -Message 'ok'
        Should -Invoke -ModuleName ConsoleUI Read-Host -Times 1 -Exactly
    }

    It 'Initialize-ConsoleUI não falha' {
        { Initialize-ConsoleUI -Title 'teste' } | Should -Not -Throw
    }
}
