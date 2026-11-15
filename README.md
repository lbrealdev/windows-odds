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
| Get-MachineInfo.ps1 | PowerShell | Read-only inventory of a Windows machine: hardware, serial numbers, firmware, Windows edition and build, license and activation, disks and battery health, TPM/BitLocker/Defender, installed and pending updates, drivers and installed programs. | read-only | required | [docs/Get-MachineInfo.md](docs/Get-MachineInfo.md) |
| SetupWin.ps1 | PowerShell | Installs the winget packages listed in `scripts/winget-apps.txt`. Already installed packages are skipped. A failure for one package does not stop the rest. | installs apps | not required for most apps | [docs/SetupWin.md](docs/SetupWin.md) |
