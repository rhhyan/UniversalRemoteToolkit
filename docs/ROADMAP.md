# Roadmap

## Sprint 1 — Foundation

- [x] Define project structure
- [x] Create configuration module
- [x] Create logger module
- [x] Create utility module
- [x] Establish initial project documentation

## Sprint 2 — Core Remote Execution

- [x] Connection module
- [x] PsExec path detection
- [x] PsExec installation validation
- [x] Remote computer reachability check
- [x] Execution module
- [x] PsExec argument builder
- [x] Native PsExec process execution
- [x] Process timeout handling
- [x] Structured execution results
- [x] Comment-based PowerShell documentation

## Sprint 3 — Console Interface

- [ ] Build ConsoleUI foundation
- [ ] Create main menu
- [ ] Add interactive computer selection
- [ ] Add command execution interface
- [ ] Add execution status display
- [ ] Add formatted operation results
- [ ] Integrate ConsoleUI with Logger
- [ ] Integrate ConsoleUI with Connection
- [ ] Integrate ConsoleUI with Execution

## Sprint 4 — Software Management

- [x] Software inventory (machine and per-user installations)
- [x] Remote software installation from network repository
- [x] Universal uninstaller (MSI, Inno Setup, NSIS, Chromium, Squirrel)
- [x] Silent uninstall command detection
- [x] Post-uninstall verification via registry
- [x] Remote uninstaller cleanup on timeout
- [ ] InstallShield silent uninstall (response file support)
- [ ] Per-user uninstall in the logged-on user's context

## Future

- [ ] Driver management
- [ ] Batch operations
- [ ] Improved error handling
- [ ] Automated tests
- [ ] Configuration profiles
- [ ] Advanced logging and reporting