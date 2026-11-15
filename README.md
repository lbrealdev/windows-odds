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

| Script | Description | Docs |
| --- | --- | --- |
| Get-MachineInfo.ps1 | Read-only machine inventory | [Get-MachineInfo.md](docs/scripts/Get-MachineInfo.md) |
| Install-WingetApps.ps1 | Install apps from a winget list | [Install-WingetApps.md](docs/scripts/Install-WingetApps.md) |
