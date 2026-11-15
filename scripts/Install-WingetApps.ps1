#Requires -Version 5.1
<#
.SYNOPSIS
    Installs applications from a list of winget package IDs.

.DESCRIPTION
    Reads winget package IDs from a text file and installs any that are not
    already present. Skips IDs that are already installed. A failure for one
    ID does not stop the rest. Prints one status line per app; winget's own
    output is shown only if an install fails. Prints a short summary at the end.

.PARAMETER AppList
    Path to the app list. Defaults to winget-apps.txt next to this script.
    One winget package ID per line. Blank lines and # comments are ignored.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-WingetApps.ps1
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

function Invoke-Winget {
    param([string[]]$ArgumentList)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $output = & winget @ArgumentList 2>&1 | Out-String -Width 4096
        [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Format-Elapsed {
    param([TimeSpan]$Elapsed)
    $sec = [int][Math]::Round($Elapsed.TotalSeconds)
    if ($sec -ge 60) {
        '{0}:{1:D2}' -f [int][Math]::Floor($sec / 60), ($sec % 60)
    } else {
        '{0}s' -f $sec
    }
}

function Get-WingetVersion {
    param([string]$Output, [string]$Id)
    $pattern = 'Found .+ \[{0}\] Version (\S+)' -f [regex]::Escape($Id)
    if ($Output -match $pattern) { $Matches[1] }
}

function Get-CleanWingetOutput {
    param([string]$Text)
    $bar = -join ([char[]]@(0x2588, 0x2591, 0x2592, 0x2593, 0x258C, 0x2590, 0x25A0, 0x25A1, 0x25AA, 0x25AB, 0x25AC, 0x2500, 0x2501))
    foreach ($raw in $Text -split '\r?\n') {
        $trim = [regex]::Replace($raw, '\x1B\[[0-9;]*[A-Za-z]', '').Trim()
        if (-not $trim) { continue }
        if ($trim.IndexOfAny($bar.ToCharArray()) -ge 0) { continue }
        if ($trim -match '^[-\\|/]+$') { continue }
        $trim
    }
}

function Write-StatusLine {
    param(
        [string]$Tag,
        [string]$Id,
        [int]$IdWidth,
        [string]$Detail,
        [ConsoleColor]$Color
    )
    $tagText = ('[{0}]' -f $Tag).PadRight(11)
    $idText = $Id.PadRight($IdWidth)
    Write-Host ("  {0} {1}  {2}" -f $tagText, $idText, $Detail) -ForegroundColor $Color
}

$idWidth = 1
if ($ids.Count -gt 0) {
    $idWidth = ($ids | Measure-Object -Property Length -Maximum).Maximum
}

$installed = @()
$skipped = @()
$failed = @()

Write-Host ("Installing {0} apps from {1}" -f $ids.Count, (Split-Path $AppList -Leaf))
Write-Host ''

foreach ($id in $ids) {
    $listed = Invoke-Winget @(
        'list', '--id', $id, '--exact', '--disable-interactivity', '--accept-source-agreements'
    )
    if ($listed.ExitCode -eq 0 -and $listed.Output -notmatch 'No installed package found' -and $listed.Output -match [regex]::Escape($id)) {
        Write-StatusLine -Tag 'skipped' -Id $id -IdWidth $idWidth -Detail 'already installed' -Color DarkGray
        $skipped += $id
        continue
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-Winget @(
        'install', '--id', $id, '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements',
        '--source', 'winget', '--disable-interactivity'
    )
    $timer.Stop()
    $elapsed = Format-Elapsed $timer.Elapsed
    $version = Get-WingetVersion -Output $result.Output -Id $id
    if ($version) {
        $detail = '{0}  {1}' -f $version, $elapsed
    } else {
        $detail = $elapsed
    }

    if ($result.ExitCode -eq 0) {
        Write-StatusLine -Tag 'installed' -Id $id -IdWidth $idWidth -Detail $detail -Color Green
        $installed += $id
    } else {
        Write-StatusLine -Tag 'failed' -Id $id -IdWidth $idWidth -Detail $detail -Color Red
        Write-Host ("    exit {0}" -f $result.ExitCode)
        Get-CleanWingetOutput $result.Output | ForEach-Object { Write-Host "    $_" }
        $failed += $id
    }
}

Write-Host ''
$summaryColor = [ConsoleColor]::Green
if ($failed.Count -gt 0) { $summaryColor = [ConsoleColor]::Red }
Write-Host "Installed: $($installed.Count)  Skipped: $($skipped.Count)  Failed: $($failed.Count)" -ForegroundColor $summaryColor
if ($failed.Count -gt 0) {
    exit 1
}
