#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Collects a read-only inventory of this Windows machine.

.DESCRIPTION
    Reads hardware, firmware, Windows version, license, security and update
    state. Changes nothing on the system and sends nothing anywhere. Results are
    written to a local folder: one JSON file, one text summary, and the
    powercfg battery report when a battery exists.

.PARAMETER OutputPath
    Folder for the results. Defaults to a timestamped folder next to the script.

.PARAMETER SkipUpdateSearch
    Skip the online search for pending Windows updates, which can take minutes.

.PARAMETER IncludeProductKey
    Include the full OEM firmware product key in the output. By default only
    whether a firmware key is present and its last five characters are recorded.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Get-MachineInfo.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$SkipUpdateSearch,
    [switch]$IncludeProductKey
)

$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $PSScriptRoot "machine-info-$env:COMPUTERNAME-$stamp"
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$report = [ordered]@{}
$script:okCount = 0
$script:failedCount = 0
$script:skippedCount = 0
$script:failedNames = @()
$sectionNameWidth = 16
$totalTimer = [System.Diagnostics.Stopwatch]::StartNew()

function Format-Elapsed {
    param([TimeSpan]$Elapsed)
    $sec = [int][Math]::Round($Elapsed.TotalSeconds)
    if ($sec -ge 60) {
        '{0}:{1:D2}' -f [int][Math]::Floor($sec / 60), ($sec % 60)
    } else {
        '{0}s' -f $sec
    }
}

function Format-Duration {
    param([TimeSpan]$Elapsed)
    $sec = [int][Math]::Round($Elapsed.TotalSeconds)
    if ($sec -lt 0) { $sec = 0 }
    $h = [int][Math]::Floor($sec / 3600)
    $m = [int][Math]::Floor(($sec % 3600) / 60)
    $s = $sec % 60
    if ($h -gt 0) {
        '{0}h{1}m{2}s' -f $h, $m, $s
    } elseif ($m -gt 0) {
        '{0}m{1}s' -f $m, $s
    } else {
        '{0}s' -f $s
    }
}

function Write-StatusLine {
    param(
        [string]$Tag,
        [string]$Name,
        [int]$NameWidth,
        [string]$Detail,
        [ConsoleColor]$Color
    )
    $tagText = ('[{0}]' -f $Tag).PadRight(11)
    $nameText = $Name.PadRight($NameWidth)
    Write-Host ("  {0} {1}  {2}" -f $tagText, $nameText, $Detail) -ForegroundColor $Color
}

# Win32_QuickFixEngineering.InstalledOn is a locale-dependent string. Get-HotFix
# wraps it in a ScriptProperty that calls DateTime.Parse and throws on non-US
# dates. Read the raw CIM value and parse it without using that property.
function ConvertTo-HotFixInstalledOn {
    param($Value)
    try {
        if ($null -eq $Value) { return $null }
        if ($Value -is [datetime]) { return [datetime]$Value }
        $text = "$Value".Trim()
        if ($text -eq '') { return $null }

        $parsed = [datetime]::MinValue
        $invariant = [System.Globalization.CultureInfo]::InvariantCulture
        $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
        if ([datetime]::TryParse($text, $invariant, $styles, [ref]$parsed)) {
            return $parsed
        }
        foreach ($fmt in @('M/d/yyyy', 'd/M/yyyy', 'yyyyMMdd')) {
            if ([datetime]::TryParseExact($text, $fmt, $invariant, $styles, [ref]$parsed)) {
                return $parsed
            }
        }

        $hex = $text
        if ($hex.StartsWith('0x') -or $hex.StartsWith('0X')) {
            $hex = $hex.Substring(2)
        }
        if ($hex -match '^[0-9A-Fa-f]{8,16}$') {
            $fileTime = [convert]::ToInt64($hex, 16)
            return [datetime]::FromFileTime($fileTime)
        }
        return $null
    } catch {
        return $null
    }
}

function Add-Section {
    param([string]$Name, [scriptblock]$Collect)
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $tag = 'ok'
    $color = [ConsoleColor]::Green
    $detailExtra = $null
    $errorText = $null
    try {
        $value = & $Collect
        $report[$Name] = $value
        if ($value -eq 'No battery') {
            $tag = 'skipped'
            $color = [ConsoleColor]::Yellow
            $detailExtra = 'no battery'
            $script:skippedCount++
        } elseif ($value -eq 'Skipped') {
            $tag = 'skipped'
            $color = [ConsoleColor]::Yellow
            $detailExtra = 'skipped'
            $script:skippedCount++
        } else {
            $script:okCount++
        }
    } catch {
        $report[$Name] = [ordered]@{ Error = $_.Exception.Message }
        $tag = 'failed'
        $color = [ConsoleColor]::Red
        $errorText = ($_.Exception.Message -split '\r?\n')[0]
        $script:failedCount++
        $script:failedNames += $Name
    }
    $timer.Stop()
    $elapsed = Format-Elapsed $timer.Elapsed
    if ($detailExtra) {
        $detail = '{0}  {1}' -f $detailExtra, $elapsed
    } else {
        $detail = $elapsed
    }
    Write-StatusLine -Tag $tag -Name $Name -NameWidth $sectionNameWidth -Detail $detail -Color $color
    if ($errorText) {
        Write-Host ("    {0}" -f $errorText)
    }
}

function Get-Cim {
    [CmdletBinding()]
    param([string]$Class, [string]$Namespace = 'root/cimv2', [string]$Filter)
    $params = @{
        ClassName   = $Class
        Namespace   = $Namespace
        ErrorAction = $ErrorActionPreference
    }
    if ($Filter) { $params.Filter = $Filter }
    Get-CimInstance @params
}

function ConvertFrom-WmiByteString {
    param($Codes)
    if ($null -eq $Codes) { return $null }
    $sb = New-Object System.Text.StringBuilder
    if ($Codes -is [string]) {
        foreach ($ch in $Codes.ToCharArray()) {
            if ([int][char]$ch -ne 0) { [void]$sb.Append($ch) }
        }
    } else {
        foreach ($code in @($Codes)) {
            if ($null -eq $code) { continue }
            $n = [int]$code
            if ($n -ne 0) { [void]$sb.Append([char]$n) }
        }
    }
    $text = $sb.ToString().Trim()
    if ($text -eq '') { return $null }
    $text
}

function Resolve-MemoryManufacturer {
    param($Raw)
    $rawText = if ($null -eq $Raw) { '' } else { "$Raw".Trim() }
    $jedec = @{
        '80AD' = 'SK Hynix'
        '80CE' = 'Samsung'
        '802C' = 'Micron'
        '0198' = 'Kingston'
        '859B' = 'Crucial'
        '029E' = 'Corsair'
        '04CD' = 'G.Skill'
        '04CB' = 'ADATA'
        '830B' = 'Nanya'
        '0443' = 'Ramaxel'
    }
    $name = $rawText
    if ($rawText -match '^[0-9A-Fa-f]{4}') {
        $code = $rawText.Substring(0, 4).ToUpperInvariant()
        if ($jedec.ContainsKey($code)) { $name = $jedec[$code] }
    }
    [ordered]@{
        Manufacturer    = $name
        ManufacturerRaw = $rawText
    }
}

function Select-UninstallEntry {
    param($Records)
    $seen = @{}
    $apps = foreach ($app in @($Records)) {
        $name = $app.DisplayName
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        if ($app.SystemComponent) { continue }
        $version = $app.DisplayVersion
        $key = "$name|$version"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [ordered]@{
            Name      = $name
            Version   = $version
            Publisher = $app.Publisher
        }
    }
    , @($apps | Sort-Object { $_['Name'] })
}

function Get-DesignCapacityFromBatteryReportXml {
    param([string]$XmlPath)
    if (-not $XmlPath -or -not (Test-Path -LiteralPath $XmlPath)) { return $null }
    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($XmlPath)
        $nodes = @($xml.SelectNodes('//DesignCapacity'))
        foreach ($node in $nodes) {
            $text = "$($node.InnerText)".Trim()
            if ($text -eq '') { continue }
            $n = 0L
            if ([int64]::TryParse($text, [ref]$n) -and $n -gt 0) { return $n }
        }
    } catch {
        return $null
    }
    $null
}

function Get-MatchedBatteryCapacity {
    param($StaticRows, $FullRows, [string]$XmlPath)
    $design = $null
    $fullCap = $null
    foreach ($s in @($StaticRows)) {
        if ($null -eq $s) { continue }
        $rowDesign = $s.DesignedCapacity
        $match = @(
            @($FullRows) | Where-Object { $_ -and $_.InstanceName -eq $s.InstanceName }
        )
        if ($match.Count -gt 0) {
            $fullCap = $match[0].FullChargedCapacity
            if ($rowDesign) { $design = $rowDesign }
            if ($design -and $fullCap) { break }
        } elseif ($rowDesign -and -not $design) {
            $design = $rowDesign
        }
    }
    if ($null -eq $fullCap) {
        foreach ($f in @($FullRows)) {
            if ($f -and $f.FullChargedCapacity) {
                $fullCap = $f.FullChargedCapacity
                break
            }
        }
    }
    if (-not $design) {
        $fromXml = Get-DesignCapacityFromBatteryReportXml $XmlPath
        if ($fromXml) { $design = $fromXml }
    }
    if (-not $design) { $design = $null }
    if (-not $fullCap) { $fullCap = $null }
    $health = $null
    if ($null -ne $design -and $null -ne $fullCap) {
        $health = [math]::Round(100 * $fullCap / $design, 1)
    }
    [ordered]@{
        DesignCapacityMWh     = $design
        FullChargeCapacityMWh = $fullCap
        HealthPercent         = $health
    }
}

function ConvertTo-ReportJson {
    param($Value, [int]$Depth = 8, [int]$Level = 0)
    $pad = ' ' * (4 * $Level)
    $inner = ' ' * (4 * ($Level + 1))

    if ($null -eq $Value) { return 'null' }

    $base = $Value
    if ($Value -is [psobject] -and $null -ne $Value.PSObject.BaseObject) {
        $base = $Value.PSObject.BaseObject
    }

    if ($base -is [datetime]) {
        return (ConvertTo-Json -InputObject $base.ToString('o'))
    }
    if ($base -is [bool]) {
        if ($base) { return 'true' } else { return 'false' }
    }
    if ($base -is [char]) {
        return (ConvertTo-ReportJson -Value ([string]$base) -Depth $Depth -Level $Level)
    }
    if ($base -is [string]) {
        return (ConvertTo-Json -InputObject $base)
    }
    $isNumber = $base -is [byte] -or $base -is [sbyte] -or
        $base -is [int16] -or $base -is [uint16] -or
        $base -is [int] -or $base -is [uint32] -or
        $base -is [long] -or $base -is [uint64] -or
        $base -is [decimal] -or $base -is [double] -or $base -is [single]
    if ($isNumber) {
        return (ConvertTo-Json -InputObject $base)
    }

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Depth -le 0) { return (ConvertTo-Json -InputObject "$Value") }
        $keys = @($Value.Keys)
        if ($keys.Count -eq 0) { return '{}' }
        $parts = foreach ($key in $keys) {
            $k = ConvertTo-Json -InputObject ([string]$key)
            $v = ConvertTo-ReportJson -Value $Value[$key] -Depth ($Depth - 1) -Level ($Level + 1)
            '{0}{1}: {2}' -f $inner, $k, $v
        }
        return ('{{{0}{1}{0}{2}}}' -f "`n", ($parts -join ",`n"), $pad)
    }

    if ($base -is [System.Collections.IEnumerable]) {
        if ($Depth -le 0) { return (ConvertTo-Json -InputObject "$Value") }
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $Value) { [void]$items.Add($item) }
        if ($items.Count -eq 0) { return '[]' }
        $parts = foreach ($item in $items) {
            '{0}{1}' -f $inner, (ConvertTo-ReportJson -Value $item -Depth ($Depth - 1) -Level ($Level + 1))
        }
        return ('[{0}{1}{0}{2}]' -f "`n", ($parts -join ",`n"), $pad)
    }

    $noteProps = @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
    if ($noteProps.Count -gt 0) {
        $map = [ordered]@{}
        foreach ($p in $noteProps) { $map[$p.Name] = $p.Value }
        return (ConvertTo-ReportJson -Value $map -Depth $Depth -Level $Level)
    }

    ConvertTo-Json -InputObject "$Value"
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

$scriptName = Split-Path -Leaf $PSCommandPath
if (-not $scriptName) { $scriptName = 'Get-MachineInfo.ps1' }
Write-Host ("{0}  (read-only)" -f $scriptName)
Write-Host ''

$report['Collected'] = [ordered]@{
    Date              = (Get-Date).ToString('o')
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
}

Add-Section 'System' {
    $cs = Get-Cim Win32_ComputerSystem
    $prod = Get-Cim Win32_ComputerSystemProduct
    $enc = Get-Cim Win32_SystemEnclosure
    [ordered]@{
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        SystemSKU    = $cs.SystemSKUNumber
        SerialNumber = $prod.IdentifyingNumber
        UUID         = $prod.UUID
        ChassisTypes = $enc.ChassisTypes
        AssetTag     = $enc.SMBIOSAssetTag
        SystemType   = $cs.SystemType
        Domain       = $cs.Domain
        PartOfDomain = $cs.PartOfDomain
    }
}

Add-Section 'Firmware' {
    $bios = Get-Cim Win32_BIOS
    $board = Get-Cim Win32_BaseBoard
    $secureBoot = try { Confirm-SecureBootUEFI } catch { 'Unsupported or legacy BIOS' }
    [ordered]@{
        BiosVendor       = $bios.Manufacturer
        BiosVersion      = $bios.SMBIOSBIOSVersion
        BiosReleaseDate  = $bios.ReleaseDate
        BiosSerialNumber = $bios.SerialNumber
        BoardMaker       = $board.Manufacturer
        BoardProduct     = $board.Product
        BoardSerial      = $board.SerialNumber
        SecureBoot       = $secureBoot
        FirmwareType     = $env:firmware_type
    }
}

Add-Section 'Windows' {
    $os = Get-Cim Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [ordered]@{
        Caption        = $os.Caption
        Edition        = $cv.EditionID
        DisplayVersion = $cv.DisplayVersion
        Version        = $os.Version
        Build          = "$($cv.CurrentBuildNumber).$($cv.UBR)"
        Architecture   = $os.OSArchitecture
        Language       = $os.MUILanguages
        InstallDate    = $os.InstallDate
        LastBoot       = $os.LastBootUpTime
        RegisteredUser = $cv.RegisteredOwner
    }
}

Add-Section 'License' {
    $svc = Get-Cim SoftwareLicensingService
    $statusNames = @{
        0 = 'Unlicensed'; 1 = 'Licensed'; 2 = 'OOBGrace'; 3 = 'OOTGrace'
        4 = 'NonGenuineGrace'; 5 = 'Notification'; 6 = 'ExtendedGrace'
    }
    $products = Get-Cim SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'"
    $oemKey = $svc.OA3xOriginalProductKey
    $license = [ordered]@{}
    if ($IncludeProductKey) {
        $license.OEMProductKeyInFirmware = $oemKey
    } else {
        $license.OEMProductKeyPresent = -not [string]::IsNullOrEmpty($oemKey)
        $license.OEMProductKeyLast5 = if ([string]::IsNullOrEmpty($oemKey)) {
            $null
        } else {
            $keyText = "$oemKey"
            if ($keyText.Length -le 5) { $keyText } else { $keyText.Substring($keyText.Length - 5) }
        }
    }
    $license.OEMKeyDescription = $svc.OA3xOriginalProductKeyDescription
    $license.Products = @($products | ForEach-Object {
        [ordered]@{
            Name              = $_.Name
            Description       = $_.Description
            Channel           = $_.ProductKeyChannel
            PartialProductKey = $_.PartialProductKey
            Status            = $statusNames[[int]$_.LicenseStatus]
        }
    })
    $license
}

Add-Section 'Processor' {
    ,@(Get-Cim Win32_Processor | ForEach-Object {
        [ordered]@{
            Name              = $_.Name.Trim()
            Cores             = $_.NumberOfCores
            LogicalProcessors = $_.NumberOfLogicalProcessors
            MaxClockMHz       = $_.MaxClockSpeed
            Virtualization    = $_.VirtualizationFirmwareEnabled
        }
    })
}

Add-Section 'Memory' {
    $modules = @(Get-Cim Win32_PhysicalMemory)
    $array = Get-Cim Win32_PhysicalMemoryArray
    [ordered]@{
        TotalGB     = [math]::Round(($modules | Measure-Object Capacity -Sum).Sum / 1GB, 2)
        Slots       = ($array | Measure-Object MemoryDevices -Sum).Sum
        MaxGB       = [math]::Round(($array | Measure-Object MaxCapacityEx -Sum).Sum / 1MB, 2)
        Modules     = @($modules | ForEach-Object {
            $maker = Resolve-MemoryManufacturer $_.Manufacturer
            [ordered]@{
                Slot            = $_.DeviceLocator
                CapacityGB      = [math]::Round($_.Capacity / 1GB, 2)
                SpeedMHz        = $_.ConfiguredClockSpeed
                Manufacturer    = $maker.Manufacturer
                ManufacturerRaw = $maker.ManufacturerRaw
                PartNumber      = "$($_.PartNumber)".Trim()
                SerialNumber    = $_.SerialNumber
            }
        })
    }
}

Add-Section 'Disks' {
    ,@(Get-PhysicalDisk | ForEach-Object {
        $rel = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        [ordered]@{
            Model           = $_.FriendlyName
            SerialNumber    = "$($_.SerialNumber)".Trim()
            Firmware        = $_.FirmwareVersion
            MediaType       = "$($_.MediaType)"
            BusType         = "$($_.BusType)"
            SizeGB          = [math]::Round($_.Size / 1GB, 2)
            Health          = "$($_.HealthStatus)"
            PowerOnHours    = $rel.PowerOnHours
            Wear            = $rel.Wear
            TemperatureC    = $rel.Temperature
        }
    })
}

Add-Section 'Partitions' {
    ,@(Get-Partition | ForEach-Object {
        $vol = $_ | Get-Volume -ErrorAction SilentlyContinue
        [ordered]@{
            Disk        = $_.DiskNumber
            Partition   = $_.PartitionNumber
            Type        = $_.Type
            DriveLetter = ConvertFrom-WmiByteString $_.DriveLetter
            SizeGB      = [math]::Round($_.Size / 1GB, 2)
            Label       = $vol.FileSystemLabel
            FileSystem  = $vol.FileSystem
            FreeGB      = if ($vol) { [math]::Round($vol.SizeRemaining / 1GB, 2) } else { $null }
        }
    })
}

Add-Section 'Graphics' {
    ,@(Get-Cim Win32_VideoController | ForEach-Object {
        [ordered]@{
            Name          = $_.Name
            DriverVersion = $_.DriverVersion
            DriverDate    = $_.DriverDate
            Resolution    = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
        }
    })
}

Add-Section 'Monitors' {
    ,@(Get-Cim WmiMonitorID -Namespace 'root/wmi' | ForEach-Object {
        [ordered]@{
            Manufacturer = ConvertFrom-WmiByteString $_.ManufacturerName
            Model        = ConvertFrom-WmiByteString $_.UserFriendlyName
            SerialNumber = ConvertFrom-WmiByteString $_.SerialNumberID
            Year         = $_.YearOfManufacture
        }
    })
}

Add-Section 'Network' {
    ,@(Get-NetAdapter -IncludeHidden:$false | ForEach-Object {
        [ordered]@{
            Name        = $_.Name
            Description = $_.InterfaceDescription
            MacAddress  = $_.MacAddress
            Status      = "$($_.Status)"
            LinkSpeed   = $_.LinkSpeed
            Driver      = $_.DriverVersion
        }
    })
}

Add-Section 'Battery' {
    $batteries = @(try { Get-Cim Win32_Battery -ErrorAction SilentlyContinue } catch { @() })
    if (-not $batteries) { return 'No battery' }
    $static = @(try {
        Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -Property DesignedCapacity,InstanceName -ErrorAction Stop
    } catch {
        try { Get-Cim BatteryStaticData -Namespace 'root/wmi' -ErrorAction Stop } catch { @() }
    })
    $full = @(try { Get-Cim BatteryFullChargedCapacity -Namespace 'root/wmi' -ErrorAction SilentlyContinue } catch { @() })
    $batteryReport = Join-Path $OutputPath 'battery-report.html'
    powercfg /batteryreport /output "$batteryReport" | Out-Null
    $cap = Get-MatchedBatteryCapacity -StaticRows $static -FullRows $full
    if (-not $cap.DesignCapacityMWh) {
        $xmlPath = Join-Path $OutputPath 'battery-report.xml'
        try { powercfg /batteryreport /xml /output "$xmlPath" | Out-Null } catch { $null = $_ }
        $cap = Get-MatchedBatteryCapacity -StaticRows $static -FullRows $full -XmlPath $xmlPath
        if (Test-Path -LiteralPath $xmlPath) {
            Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
        }
    }
    [ordered]@{
        Name                   = $batteries.Name
        ChargePercent          = $batteries.EstimatedChargeRemaining
        DesignCapacityMWh      = $cap.DesignCapacityMWh
        FullChargeCapacityMWh  = $cap.FullChargeCapacityMWh
        HealthPercent          = $cap.HealthPercent
        Report                 = 'battery-report.html'
    }
}

Add-Section 'Security' {
    $tpm = $null
    $tpmVersion = $null
    $tpmError = $null
    try {
        $tpm = Get-Tpm
        $tpmVersion = (Get-Cim Win32_Tpm -Namespace 'root/cimv2/Security/MicrosoftTpm').SpecVersion
    } catch {
        $tpmError = $_.Exception.Message
    }

    $bitlocker = $null
    try {
        $bitlocker = @(Get-BitLockerVolume -ErrorAction SilentlyContinue | ForEach-Object {
            [ordered]@{
                Mount      = $_.MountPoint
                Protection = "$($_.ProtectionStatus)"
                Status     = "$($_.VolumeStatus)"
                Method     = "$($_.EncryptionMethod)"
            }
        })
    } catch {
        $bitlocker = [ordered]@{ Error = $_.Exception.Message }
    }

    $defender = $null
    $defenderError = $null
    try {
        $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    } catch {
        $defenderError = $_.Exception.Message
    }

    $sec = [ordered]@{
        TpmPresent        = $tpm.TpmPresent
        TpmReady          = $tpm.TpmReady
        TpmVersion        = $tpmVersion
        TpmManufacturer   = $tpm.ManufacturerIdTxt
        BitLocker         = $bitlocker
        DefenderEnabled   = $defender.AntivirusEnabled
        DefenderSignature = $defender.AntivirusSignatureVersion
    }
    if ($tpmError) { $sec.TpmError = $tpmError }
    if ($defenderError) { $sec.DefenderError = $defenderError }
    $sec
}

Add-Section 'InstalledUpdates' {
    $items = foreach ($hf in @(Get-HotFix)) {
        $raw = $null
        try {
            $raw = $hf.CimInstanceProperties['InstalledOn'].Value
        } catch {
            $raw = $null
        }
        [ordered]@{
            Id          = $hf.HotFixID
            Description = $hf.Description
            InstalledOn = ConvertTo-HotFixInstalledOn $raw
        }
    }
    , @($items | Sort-Object { $_['InstalledOn'] } -Descending)
}

Add-Section 'PendingUpdates' {
    if ($SkipUpdateSearch) { return 'Skipped' }
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
    ,@($result.Updates | ForEach-Object {
        [ordered]@{
            Title    = $_.Title
            KB       = ($_.KBArticleIDs | ForEach-Object { "KB$_" }) -join ', '
            Category = ($_.Categories | Select-Object -First 1).Name
            SizeMB   = [math]::Round($_.MaxDownloadSize / 1MB, 1)
        }
    })
}

Add-Section 'Drivers' {
    ,@(Get-Cim Win32_PnPSignedDriver -Filter 'DeviceName IS NOT NULL' |
        Sort-Object DeviceClass, DeviceName | ForEach-Object {
            [ordered]@{
                Class    = $_.DeviceClass
                Device   = $_.DeviceName
                Provider = $_.DriverProviderName
                Version  = $_.DriverVersion
                Date     = $_.DriverDate
            }
        })
}

Add-Section 'InstalledApps' {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    ,(Select-UninstallEntry (Get-ItemProperty $keys -ErrorAction SilentlyContinue))
}

$jsonPath = Join-Path $OutputPath 'machine-info.json'
Write-Utf8NoBom $jsonPath (ConvertTo-ReportJson -Value $report -Depth 8)

$summary = foreach ($name in $report.Keys) {
    "==== $name ===="
    $value = $report[$name]
    if ($value -is [array]) {
        $value | ForEach-Object { [pscustomobject]$_ } | Format-List | Out-String -Width 200
    } elseif ($value -is [System.Collections.IDictionary]) {
        [pscustomobject]$value | Format-List | Out-String -Width 200
    } else {
        "$value`n"
    }
}
$summaryPath = Join-Path $OutputPath 'machine-info.txt'
Write-Utf8NoBom $summaryPath (($summary -join [Environment]::NewLine) + [Environment]::NewLine)

$totalTimer.Stop()
$elapsedText = Format-Duration $totalTimer.Elapsed
Write-Host ''
if ($script:failedCount -gt 0) {
    Write-Host 'Done with errors' -ForegroundColor Yellow -NoNewline
    Write-Host (' in {0}   {1} ok   ' -f $elapsedText, $script:okCount) -NoNewline
    Write-Host ('{0} failed' -f $script:failedCount) -ForegroundColor Red -NoNewline
    Write-Host ('   {0} skipped' -f $script:skippedCount)
    Write-Host ('  failed: {0}  (details in machine-info.txt)' -f ($script:failedNames -join ', '))
} else {
    Write-Host 'Done' -ForegroundColor Green -NoNewline
    Write-Host (' in {0}   {1} ok   {2} failed   {3} skipped' -f $elapsedText, $script:okCount, $script:failedCount, $script:skippedCount)
}

Write-Host ''
Write-Host ('Saved to {0}' -f [System.IO.Path]::GetFullPath($OutputPath))

$files = @(Get-ChildItem -LiteralPath $OutputPath -File)
$txt = @($files | Where-Object { $_.Extension -eq '.txt' } | Sort-Object Name)
$json = @($files | Where-Object { $_.Extension -eq '.json' } | Sort-Object Name)
$rest = @($files | Where-Object { $_.Extension -ne '.txt' -and $_.Extension -ne '.json' } | Sort-Object Name)
$descs = @{
    'machine-info.txt'    = 'readable summary'
    'machine-info.json'   = 'full data'
    'battery-report.html' = 'battery report'
}
$rows = @(foreach ($f in @($txt + $json + $rest)) {
    $kb = [int][Math]::Round($f.Length / 1KB)
    if ($kb -lt 1) { $kb = 1 }
    [pscustomobject]@{ Name = $f.Name; Kb = $kb; Desc = $descs[$f.Name] }
})
if ($rows.Count -gt 0) {
    $nameWidth = ($rows | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $sizeWidth = ($rows | ForEach-Object { $_.Kb.ToString().Length } | Measure-Object -Maximum).Maximum
    foreach ($row in $rows) {
        $descPart = ''
        if ($row.Desc) { $descPart = '   {0}' -f $row.Desc }
        Write-Host ('  {0}   {1} KB{2}' -f $row.Name.PadRight($nameWidth), $row.Kb.ToString().PadLeft($sizeWidth), $descPart)
    }
}
