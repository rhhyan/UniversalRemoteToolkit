# Changelog

All notable changes to this project will be documented here.

---

## [Unreleased]

### Fixed

- Resultado de "Execute command" com here-string mal fechada: falhas não eram exibidas e o sucesso mostrava código-fonte
- PsExec podia travar até o timeout aguardando aceite da EULA (`-accepteula -nobanner`)
- Instalação de `.msi` agora usa `msiexec /i`; caminhos com espaços passam a funcionar
- Códigos 3010/1641 (reinicialização necessária) tratados como sucesso
- Desinstalação MSI com `/I{GUID}` abria a tela de "modificar" e travava; agora usa `/x {GUID} /quiet`
- `Get-ApplicationRoot` retornava a pasta `src` em vez da raiz
- `Show-ExecutionResult` vazava a entrada do usuário para o pipeline
- Menu exibia "0 - Exit" no topo
- Menus de Otimização/Ativação exibiam o título da opção errada (ex.: "1" mostrava "debloat", "3" mostrava "Voltar"): `[ordered]` indexado por inteiro usa a posição, não a chave
- Timeout do PsExec não era respeitado quando um processo filho mantinha o pipe de saída aberto; agora a árvore de processos é encerrada e a leitura tem espera limitada
- `Get-InstalledSoftware` retornava lista vazia quando havia um único programa com colchetes no nome (ex.: `Driver [x64]`)
- Acentos corrompidos no Windows PowerShell 5.1 (ex.: "InvÃ¡lida"): módulos com caracteres não ASCII agora são salvos em UTF-8 com BOM
- Aviso "unapproved verbs" exibido a cada inicialização

### Added

- Testes automatizados com Pester (`Tests/`, 213 testes): todos os módulos, com chamadas remotas (PsExec, compartilhamentos) simuladas; inclui verificação de sintaxe e encoding e um teste ponta a ponta do menu principal. Executar com `Invoke-Pester ./Tests`
- Menu Scripts (`Scripts.psm1`): execução remota de scripts de manutenção em uma ou várias máquinas, com resumo por computador
  - Otimização do Windows: limpeza de perfis + SFC, debloat, DISM, efeitos visuais e desativação de serviços
  - Ativação Windows/Office via KMS (`Scripts.KmsHost` no Settings.json) e consulta de status
- Desinstalador universal (`Resolve-UninstallCommand`): detecta MSI, Inno Setup, NSIS, Chromium, Squirrel e InstallShield e aplica o modo silencioso de cada um; para desinstaladores desconhecidos, pede os argumentos silenciosos
- Verificação pós-desinstalação: aguarda a chave do programa sumir do registro (`Software.UninstallVerifyTimeout`), cobrindo desinstaladores que retornam antes de terminar (NSIS, Squirrel) e falsos sucessos (ex.: MSI 1605)
- Listagem inclui instalações por usuário (perfis carregados em `HKEY_USERS`), com escopo, fabricante e ProductCode; ignora componentes de sistema e atualizações
- Em caso de timeout, o processo do desinstalador é encerrado na máquina remota
- Seleção entre múltiplos resultados na instalação/desinstalação (antes usava o primeiro silenciosamente)
- Uso de `QuietUninstallString` quando disponível
- Desinstalação do Office 2016 MSI (volume) via OffScrub da Microsoft (`Bin\OffScrub\OffScrub_O16msi.vbs`): o Office Setup Controller não tem modo silencioso que funcione como SYSTEM (`/config` falha com 30054 e `msiexec /x` com 1603)
  - Remove só o SKU registrado (ex.: `PROPLUS`, `STANDARD`), nunca `ALL`, para não levar outra edição junto
  - Timeout próprio de 3600 s (`Software.OffScrubTimeout`, opcional) e exit code tratado como máscara de bits (falha = bit 1; reinicialização = bits 2 e 32)
  - O `.vbs` copiado é apagado ao final; a pasta de log `OffScrub` só é apagada no sucesso e, na falha, o caminho do log aparece na mensagem de erro
  - No timeout o OffScrub não é encerrado (interromper a limpeza deixaria o Office pela metade)
  - Menu avisa que o OffScrub fecha Word/Excel/Outlook à força e pode levar 20+ min
  - Office 2013 MSI (`OffScrub_O15msi.vbs`) usa a mesma lógica quando o script estiver em `Bin\OffScrub`
  - Roda como SYSTEM (`PsExec -s`), como na validação manual
- `Invoke-PsExecCommand -System` para executar como SYSTEM (o padrão continua sendo a conta do operador)
- `Invoke-SoftwareInstallation`: copia o instalador, instala e apaga a cópia, mesmo quando a instalação falha
- `Find-InstalledSoftware`: busca programas instalados pelo nome e devolve todos os resultados
- `Invoke-RemotePowerShell`: executa um trecho de PowerShell na máquina remota via `-EncodedCommand`
- `Copy-FileToRemote` e `ConvertTo-AdminSharePath`: cópia única para a pasta temporária remota (`C:\x` -> `\\PC\C$\x`), com ping antes da cópia
- Teste de arquitetura: cada módulo declara `# Depende de:` no cabeçalho, e o teste falha se a declaração não bater com as chamadas reais ou se um módulo chamar função interna de outro
- Remoção do instalador copiado para a máquina remota após a instalação (também quando ela falha)
- Indicação de reinicialização pendente no resultado

### Fixed (desinstalação)

- `cmd /c` quebrava comandos com caminho entre aspas e argumentos; o executável agora é chamado diretamente (cmd só quando há `%VARIAVEL%`)

### Improved

- `Paths.PsExec`, `Paths.Logs`, `Logs.EnableConsole` e `Network.PingTimeout` do Settings.json agora são respeitados
- Ping com timeout configurável (máquinas offline falham rápido)
- Instalação em máquina offline falha na hora ("not reachable"), em vez de esperar o timeout do SMB; nome do computador com `\\` também é aceito na instalação
- Settings.json lido uma vez e mantido em cache (`Get-ToolkitConfig -Force` relê); antes era lido 3 vezes a cada comando remoto
- Mensagem clara quando `Software.RepositoryPath` não está configurado; `RemoteTempPath` e os timeouts padrão têm valor padrão quando faltam no Settings.json

### Changed (arquitetura)

Revisão de arquitetura para que cada módulo tenha uma responsabilidade e dependa só do necessário.

- Software e Scripts leem a configuração quando as funções rodam, não no import: os módulos carregam sem o Settings.json e o erro de configuração do script principal volta a aparecer formatado
- Fluxo de instalação saiu do menu para `Invoke-SoftwareInstallation`. Na tela, o prompt "Installation arguments" vem logo após "Installer found" e a cópia não aparece mais como etapa separada
- `Copy-SoftwareToRemote` e `Copy-ScriptToRemote` viraram wrappers de `Copy-FileToRemote`, mantendo as propriedades de retorno
- Config, Logger, Execution e ConsoleUI têm `Export-ModuleMember`; funções auxiliares (`Build-PsExecArguments`, `Invoke-PsExecProcess`, `Format-LogMessage`, `Format-CenteredText` etc.) agora são internas
- Exit code diferente de 0 é registrado como Info pelo `Invoke-PsExecCommand`; quem chama decide se é falha (3010, exit 2 dos Scripts e a máscara do OffScrub não são)
- `Write-Log` sem `Start-Log` não lança mais erro: a mensagem vai para o Verbose, e os módulos podem ser usados fora do menu
- Removidos por falta de uso: `Pause-Toolkit`, `Clear-Toolkit`, `Get-ApplicationRoot`, `Format-Duration`, `Format-Date` e `Get-SoftwareUninstallCommand` (substituída por `Find-InstalledSoftware`)

---

## [0.2.0] - Sprint 2 (In Progress)

### Added

- Execution.psm1
- Get-PsExecPath
- Test-ComputerReachable
- Build-PsExecArguments
- Invoke-PsExecProcess
- Invoke-PsExecCommand

### Improved

- Project architecture
- Separation of responsibilities
- Connection workflow

---

## [0.1.0] - Sprint 1

### Added

- Logger module
- Config module
- Repository organization
- Documentation
- Modular architecture