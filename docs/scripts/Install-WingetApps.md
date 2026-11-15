# Install-WingetApps.ps1

Installs the winget packages listed in `scripts/winget-apps.txt` (next to the script). Already installed packages are skipped. A failure for one package does not stop the rest. Elevation is not required for most apps. Each package is reported on one line; winget's own output is shown only if an install fails.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- winget (App Installer)

## Usage

```powershell
git clone https://github.com/lbrealdev/windows-toolbox.git
cd windows-toolbox

powershell -ExecutionPolicy Bypass -File .\scripts\Install-WingetApps.ps1

# Custom list
powershell -ExecutionPolicy Bypass -File .\scripts\Install-WingetApps.ps1 -AppList C:\path\to\winget-apps.txt
```

## Parameters

- `-AppList`: path to the app list. Defaults to `winget-apps.txt` next to the script. One winget package ID per line. Blank lines and `#` comments are ignored.

## Output

Each package is reported on one line; winget's own output is shown only if an install fails. A short summary of installed, skipped, and failed counts is printed at the end.

## Adding apps

Edit `scripts/winget-apps.txt`: one winget package ID per line. Blank lines and `#` comments are ignored. Find IDs with `winget search <name>`.
