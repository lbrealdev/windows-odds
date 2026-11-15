#Requires -Version 5.1
<#
.SYNOPSIS
    Installs applications from a list of winget package IDs.

.DESCRIPTION
    Reads winget package IDs from a text file and installs any that are not
    already present. Skips IDs that are already installed. A failure for one
    ID does not stop the rest. Prints a short summary at the end.

.PARAMETER AppList
    Path to the app list. Defaults to winget-apps.txt next to this script.
    One winget package ID per line. Blank lines and # comments are ignored.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\SetupWin.ps1
#>
[CmdletBinding()]
param(
    [string]$AppList
)

$ErrorActionPreference = 'Stop'

if (-not $AppList) {
    $AppList = Join-Path $PSScriptRoot 'winget-apps.txt'
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is not available.'
}

if (-not (Test-Path -LiteralPath $AppList)) {
    throw "App list not found: $AppList"
}

$ids = @(
    Get-Content -LiteralPath $AppList |
        ForEach-Object { ($_ -split '#', 2)[0].Trim() } |
        Where-Object { $_ }
)

$installed = @()
$skipped = @()
$failed = @()

foreach ($id in $ids) {
    Write-Host "Checking $id..."
    $listOut = & winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $listOut -notmatch 'No installed package found' -and $listOut -match [regex]::Escape($id)) {
        Write-Host "Skipping $id (already installed)"
        $skipped += $id
        continue
    }

    Write-Host "Installing $id..."
    & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements --source winget
    if ($LASTEXITCODE -eq 0) {
        $installed += $id
    } else {
        Write-Host "Failed $id (exit $LASTEXITCODE)"
        $failed += $id
    }
}

Write-Host ''
Write-Host "Installed: $($installed.Count)  Skipped: $($skipped.Count)  Failed: $($failed.Count)"
if ($failed.Count -gt 0) {
    exit 1
}
