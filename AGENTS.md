# AGENTS.md

## Scripts

Scripts live under `scripts/`.

## Terminal UX

Applies to every script, whatever the shell.

- Start with one header line: the script name.
- Print one status line per step: a bracketed status (`[ok]`, `[failed]`, `[skipped]`, or a specific verb such as `[installed]`), the step name, and its duration. Keep the columns aligned.
- Under a failed step, print one short error line. Show raw tool output only when a step fails.
- End with one summary line: `Done in <duration>   <n> ok   <n> failed   <n> skipped`, or `Done with errors in <duration> ...` when any step failed, followed by `failed: <steps>`.
- If the script writes files, print `Saved to <full path>`, then one line per file with its size and a short description.
- Format durations as `5s`, `1m31s`, `1h2m5s`.
- Colors: green for success and `Done`, red for failures, yellow for `Done with errors`.

## PowerShell

- **Target:** Windows PowerShell 5.1 and PowerShell 7+.
- **How it runs:** `powershell -ExecutionPolicy Bypass -File .\scripts\<Name>.ps1`
- **File naming:** official Verb-Noun with an approved verb (see `Get-Verb`), e.g. `Get-MachineInfo.ps1`, `Install-WingetApps.ps1`, `Set-PowerPlan.ps1`, `Clear-TempFiles.ps1`. No version or date in file names.
- **Help:** comment-based help (`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`) so `Get-Help` works.
- **Line endings:** LF, no BOM.
- **Lint:** `Invoke-ScriptAnalyzer -Path scripts -Recurse` must be clean.
- **Rules:** no ternary / `??`; no `-AsHashtable`; do not rely on `ConvertTo-Json` for dates or single-item arrays; write files with explicit UTF-8 encoding, not `Set-Content` defaults.

## Bash

- **Target:** Git Bash on Windows.
- **How it runs:** start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- **File naming:** kebab-case `.sh`, e.g. `check-disk.sh`, `fix-line-endings.sh`, `clean-temp.sh`. No version or date in file names.
- **Help:** `-h` / `--help` required; print usage and examples.
- **Line endings:** Bash scripts must use LF line endings; CRLF breaks loops and tests in Git Bash.
- **Lint:** ShellCheck clean.
- **Rules:** convert Windows paths with `cygpath` when needed.

## Generated output

Generated output (for example `machine-info-*/`) is never committed. Keep `.gitignore` current.
