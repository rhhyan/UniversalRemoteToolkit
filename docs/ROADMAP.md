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

- [x] Build ConsoleUI foundation
- [x] Create main menu
- [x] Add interactive computer selection
- [x] Add command execution interface
- [x] Add execution status display
- [x] Add formatted operation results
- [x] Integrate ConsoleUI with Logger
- [x] Integrate ConsoleUI with Connection
- [x] Integrate ConsoleUI with Execution

## Sprint 4 — Software Management

- [x] Software inventory (machine and per-user installations)
- [x] Remote software installation from network repository
- [x] Universal uninstaller (MSI, Inno Setup, NSIS, Chromium, Squirrel)
- [x] Silent uninstall command detection
- [x] Post-uninstall verification via registry
- [x] Remote uninstaller cleanup on timeout
- [ ] InstallShield silent uninstall (response file support)
- [ ] Per-user uninstall in the logged-on user's context

## Sprint 5 — Maintenance Scripts

- [x] Scripts menu with remote script catalog
- [x] Run scripts on multiple computers with per-computer summary
- [x] Windows optimization (profile cleanup + SFC, debloat, DISM, visual effects, services)
- [x] Windows/Office KMS activation and status check

## Sprint 6 — Quality

- [x] Automated tests with Pester (all modules, remote calls mocked)
- [x] End-to-end smoke test of the main menu
- [x] Syntax and encoding checks (Windows PowerShell 5.1 compatibility)
- [ ] Run the test suite in CI (GitHub Actions)
- [ ] Validate remote workflows on a real Windows test machine

## Future

- [ ] Driver management
- [ ] Batch operations
- [ ] Improved error handling
- [ ] Configuration profiles
- [ ] Advanced logging and reporting