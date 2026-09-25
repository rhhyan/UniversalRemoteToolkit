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
- [x] Automated testing (Pester)

### In Progress

- [ ] Console UI
- [ ] Remote command execution workflow
- [ ] Software management features

## Running the Tests

The test suite uses [Pester](https://pester.dev) 5+ and mocks every remote
call (PsExec, network shares), so it runs on any machine with PowerShell 7:

```powershell
Invoke-Pester ./Tests
```
