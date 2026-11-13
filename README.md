# windows-odds
Odds and ends for Windows. PowerShell scripts for when you have to touch it.

## Get-MachineInfo.ps1

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
powershell -ExecutionPolicy Bypass -File .\Get-MachineInfo.ps1

# Skip the pending update search
powershell -ExecutionPolicy Bypass -File .\Get-MachineInfo.ps1 -SkipUpdateSearch

# Write the results somewhere else
powershell -ExecutionPolicy Bypass -File .\Get-MachineInfo.ps1 -OutputPath C:\Temp\machine-info
```

Without git, download the script from GitHub and run the same command from the folder it is in. `-ExecutionPolicy Bypass` applies only to that run and does not change the system policy.

### Parameters

- `-OutputPath`: folder where the results are written. Defaults to `machine-info-<COMPUTERNAME>-<timestamp>` next to the script.
- `-SkipUpdateSearch`: skip the online search for pending Windows updates.

### Output

The output folder contains:

- `machine-info.json`: all collected data
- `machine-info.txt`: human-readable summary
- `battery-report.html`: `powercfg` battery report (only on machines with a battery)

If a section fails, the error is recorded in that section and the script continues with the rest.

The output contains serial numbers and the Windows product key. Do not commit or share it publicly. `.gitignore` already excludes `machine-info-*/`.
