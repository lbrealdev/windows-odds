# windows-toolbox

Notes and procedures for Windows, plus scripts in PowerShell and Bash. Scripts live under `scripts/`.

## Quick start

```
git clone https://github.com/lbrealdev/windows-toolbox.git
cd windows-toolbox
```

PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\<Script>.ps1
```

`-ExecutionPolicy Bypass` applies only to that run and does not change the system policy.

| Script | Shell | What it does | Changes the system | Admin | Docs |
| --- | --- | --- | --- | --- | --- |
| Get-MachineInfo.ps1 | PowerShell | Read-only machine inventory | read-only | required | [docs/Get-MachineInfo.md](docs/Get-MachineInfo.md) |
| SetupWin.ps1 | PowerShell | Install apps from a winget list | installs apps | not required for most apps | [docs/SetupWin.md](docs/SetupWin.md) |
