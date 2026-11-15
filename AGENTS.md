# Agent rules

## Scripts

Scripts live under `scripts/`.

## Terminal UX

Applies to every script, whatever the shell. Follow the current scripts (`scripts/Get-MachineInfo.ps1`, `scripts/SetupWin.ps1`):

- One aligned, colored status line per step (`[ok]`, `[failed]`, `[skipped]`; SetupWin uses `[installed]` for a successful install) with its timing.
- A short error line only under a failed step.
- A colored summary at the end (`Done in ...` in Get-MachineInfo).

## PowerShell

- **Target:** Windows PowerShell 5.1 and PowerShell 7+.
- **How it runs:** `powershell -ExecutionPolicy Bypass -File .\scripts\<Name>.ps1`
- **File naming:** `Verb-Noun.ps1` with an approved verb. Do not rename existing scripts.
- **Help:** comment-based help (`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`) so `Get-Help` works.
- **Line endings:** LF, no BOM (as in the current `.ps1` files), enforced by `.gitattributes`.
- **Lint:** `Invoke-ScriptAnalyzer -Path scripts -Recurse` must be clean.
- **Rules:** no ternary / `??`; no `-AsHashtable`; do not rely on `ConvertTo-Json` for dates or single-item arrays; write files with explicit UTF-8 encoding, not `Set-Content` defaults.

## Bash

- **Target:** Git Bash on Windows.
- **How it runs:** start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- **File naming:** kebab-case `.sh`.
- **Help:** `-h` / `--help` required; print usage and examples.
- **Line endings:** LF only (CRLF / `\r` breaks Bash in Git Bash), enforced by `.gitattributes`.
- **Lint:** ShellCheck clean.
- **Rules:** convert Windows paths with `cygpath` when needed.

## Generated output

Generated output (for example `machine-info-*/`) is never committed. Keep `.gitignore` current.
