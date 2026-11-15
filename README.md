# windows-toolbox

A toolbox for Windows: how-to notes, troubleshooting guides and scripts.

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
| Get-MachineInfo.ps1 | PowerShell | Read-only machine inventory | read-only | required | [docs/scripts/Get-MachineInfo.md](docs/scripts/Get-MachineInfo.md) |
| Install-WingetApps.ps1 | PowerShell | Install apps from a winget list | installs apps | not required for most apps | [docs/scripts/Install-WingetApps.md](docs/scripts/Install-WingetApps.md) |
