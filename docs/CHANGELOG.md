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

### Added

- Menu Scripts (`Scripts.psm1`): execução remota de scripts de manutenção em uma ou várias máquinas, com resumo por computador
  - Otimização do Windows: limpeza de perfis + SFC, debloat, DISM, efeitos visuais e desativação de serviços
  - Ativação Windows/Office via KMS (`Scripts.KmsHost` no Settings.json) e consulta de status
- Desinstalador universal (`Resolve-UninstallCommand`): detecta MSI, Inno Setup, NSIS, Chromium, Squirrel e InstallShield e aplica o modo silencioso de cada um; para desinstaladores desconhecidos, pede os argumentos silenciosos
- Verificação pós-desinstalação: aguarda a chave do programa sumir do registro (`Software.UninstallVerifyTimeout`), cobrindo desinstaladores que retornam antes de terminar (NSIS, Squirrel) e falsos sucessos (ex.: MSI 1605)
- Listagem inclui instalações por usuário (perfis carregados em `HKEY_USERS`), com escopo, fabricante e ProductCode; ignora componentes de sistema e atualizações
- Em caso de timeout, o processo do desinstalador é encerrado na máquina remota
- Seleção entre múltiplos resultados na instalação/desinstalação (antes usava o primeiro silenciosamente)
- Uso de `QuietUninstallString` quando disponível
- Remoção do instalador copiado para a máquina remota após a instalação
- Indicação de reinicialização pendente no resultado

### Fixed (desinstalação)

- `cmd /c` quebrava comandos com caminho entre aspas e argumentos; o executável agora é chamado diretamente (cmd só quando há `%VARIAVEL%`)

### Improved

- `Paths.PsExec`, `Paths.Logs`, `Logs.EnableConsole` e `Network.PingTimeout` do Settings.json agora são respeitados
- Ping com timeout configurável (máquinas offline falham rápido)

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