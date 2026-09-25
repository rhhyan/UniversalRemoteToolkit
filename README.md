## Project Status

The Universal Remote Toolkit is currently under active development.

### Completed

- [x] Project structure
- [x] Configuration module
- [x] Logger module
- [x] Utility functions
- [x] Connection module
- [x] Execution module
- [x] Comment-based PowerShell documentation
- [x] Console UI
- [x] Remote command execution workflow
- [x] Software management (install, inventory, universal uninstaller)
- [x] Maintenance scripts (Windows optimization, KMS activation)
- [x] Automated testing (Pester)

### In Progress

- [ ] Run the test suite in CI (GitHub Actions)
- [ ] Validate remote workflows on a real Windows test machine
- [ ] InstallShield silent uninstall and per-user uninstall

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full roadmap.

## Running the Tests

The test suite uses [Pester](https://pester.dev) 5+ and mocks every remote
call (PsExec, network shares), so it runs on any machine with PowerShell 7:

```powershell
Invoke-Pester ./Tests
```
