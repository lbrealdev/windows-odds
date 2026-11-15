# windows-odds
Odds and ends for Windows. PowerShell scripts for when you have to touch it.

## scripts/Get-MachineInfo.ps1

Read-only inventory of a Windows machine: hardware, serial numbers, firmware, Windows edition and build, license and activation, disks and battery health, TPM/BitLocker/Defender, installed and pending updates, drivers and installed programs.

It changes nothing on the system and sends nothing over the network. The only online access is the Windows Update search for pending updates, which `-SkipUpdateSearch` turns off.

### Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- An elevated (Run as administrator) PowerShell session

### Usage

```powershell
git clone https://github.com/lbrealdev/windows-odds.git
cd windows-odds

# Full inventory (the pending update search can take a few minutes)
powershell -ExecutionPolicy Bypass -File .\scripts\Get-MachineInfo.ps1

# Skip the pending update search
powershell -ExecutionPolicy Bypass -File .\scripts\Get-MachineInfo.ps1 -SkipUpdateSearch

# Include the full OEM firmware product key
powershell -ExecutionPolicy Bypass -File .\scripts\Get-MachineInfo.ps1 -IncludeProductKey

# Write the results somewhere else
powershell -ExecutionPolicy Bypass -File .\scripts\Get-MachineInfo.ps1 -OutputPath C:\Temp\machine-info
```

Without git, download the script from GitHub and run the same command from the folder it is in. `-ExecutionPolicy Bypass` applies only to that run and does not change the system policy.

### Parameters

- `-OutputPath`: folder where the results are written. Defaults to `machine-info-<COMPUTERNAME>-<timestamp>` next to the script.
- `-SkipUpdateSearch`: skip the online search for pending Windows updates.
- `-IncludeProductKey`: include the full OEM firmware product key in the output. By default the script only records whether a firmware key is present and its last five characters.

### Output

The output folder contains:

- `machine-info.json`: all collected data
- `machine-info.txt`: human-readable summary
- `battery-report.html`: `powercfg` battery report (only on machines with a battery)

If a section fails, the error is recorded in that section and the script continues with the rest.

The firmware product key is only present on OEM machines that store it in firmware. It is often empty on retail, volume, or digital-license installs.

The output contains serial numbers and the Windows product key (when included). Do not commit or share it publicly. `.gitignore` already excludes `machine-info-*/`.

## SetupWin.ps1

Installs the winget packages listed in `scripts/winget-apps.txt` (next to the script). Already installed packages are skipped. A failure for one package does not stop the rest. Elevation is not required for most apps. Each package is reported on one line; winget's own output is shown only if an install fails.

### Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- winget (App Installer)

### Usage

```powershell
git clone https://github.com/lbrealdev/windows-odds.git
cd windows-odds

powershell -ExecutionPolicy Bypass -File .\scripts\SetupWin.ps1

# Custom list
powershell -ExecutionPolicy Bypass -File .\scripts\SetupWin.ps1 -AppList C:\path\to\winget-apps.txt
```

### Adding apps

Edit `scripts/winget-apps.txt`: one winget package ID per line. Blank lines and `#` comments are ignored. Find IDs with `winget search <name>`.
