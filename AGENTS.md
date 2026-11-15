# Agent rules

## Scripts

Scripts live under `scripts/`.

## Console output

Applies to every script, whatever the shell. Follow the current scripts (`scripts/Get-MachineInfo.ps1`, `scripts/SetupWin.ps1`):

- One aligned, colored status line per step (`[ok]`, `[failed]`, `[skipped]`; SetupWin uses `[installed]` for a successful install) with its timing.
- A short error line only under a failed step.
- A colored summary at the end (`Done in ...` in Get-MachineInfo).

## PowerShell

Scripts must run on Windows PowerShell 5.1 as well as PowerShell 7+. Avoid 7-only syntax and cmdlet behavior. The current scripts show the patterns to follow:

- No ternary (`cond ? a : b`) or `??`. Use `if` / `else`, as in both existing scripts.
- Do not use `ConvertFrom-Json -AsHashtable` (PowerShell 6+). Build `[ordered]@{}` hashtables by hand, as `Get-MachineInfo.ps1` does.
- `ConvertTo-Json` differs between 5.1 and 7 for dates (`/Date(...)/` vs ISO) and single-element arrays (unrolled vs wrapped). `Get-MachineInfo.ps1` uses `ConvertTo-ReportJson` (ISO 8601 dates) and the unary comma (`, @(...)`) instead of relying on `ConvertTo-Json` for the report.
- `Get-Content` / `Set-Content` encoding defaults differ (5.1: ANSI / Unicode; 7: UTF-8). `Get-MachineInfo.ps1` writes UTF-8 without BOM with `[System.IO.File]::WriteAllText` (`Write-Utf8NoBom`), not `Set-Content`.

`Invoke-ScriptAnalyzer -Path scripts -Recurse` must be clean.

## Bash

Bash scripts must run in Git Bash.

## Generated output

Generated output (for example `machine-info-*/`) is never committed. Keep `.gitignore` current.
