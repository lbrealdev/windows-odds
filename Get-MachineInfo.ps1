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

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Get-MachineInfo.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$SkipUpdateSearch
)

$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $PSScriptRoot "machine-info-$env:COMPUTERNAME-$stamp"
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$report = [ordered]@{}

function Add-Section {
    param([string]$Name, [scriptblock]$Collect)
    Write-Host "Collecting $Name..."
    try {
        $report[$Name] = & $Collect
    } catch {
        $report[$Name] = [ordered]@{ Error = $_.Exception.Message }
        Write-Warning "$Name failed: $($_.Exception.Message)"
    }
}

function Get-Cim {
    [CmdletBinding()]
    param([string]$Class, [string]$Namespace = 'root/cimv2', [string]$Filter)
    $params = @{ ClassName = $Class; Namespace = $Namespace }
    if ($Filter) { $params.Filter = $Filter }
    Get-CimInstance @params
}

Add-Section 'Collected' {
    [ordered]@{
        Date              = (Get-Date).ToString('o')
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    }
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
    [ordered]@{
        OEMProductKeyInFirmware = $svc.OA3xOriginalProductKey
        OEMKeyDescription       = $svc.OA3xOriginalProductKeyDescription
        Products                = @($products | ForEach-Object {
            [ordered]@{
                Name              = $_.Name
                Description       = $_.Description
                Channel           = $_.ProductKeyChannel
                PartialProductKey = $_.PartialProductKey
                Status            = $statusNames[[int]$_.LicenseStatus]
            }
        })
    }
}

Add-Section 'Processor' {
    @(Get-Cim Win32_Processor | ForEach-Object {
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
            [ordered]@{
                Slot         = $_.DeviceLocator
                CapacityGB   = [math]::Round($_.Capacity / 1GB, 2)
                SpeedMHz     = $_.ConfiguredClockSpeed
                Manufacturer = $_.Manufacturer
                PartNumber   = "$($_.PartNumber)".Trim()
                SerialNumber = $_.SerialNumber
            }
        })
    }
}

Add-Section 'Disks' {
    @(Get-PhysicalDisk | ForEach-Object {
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
    @(Get-Partition | ForEach-Object {
        $vol = $_ | Get-Volume -ErrorAction SilentlyContinue
        [ordered]@{
            Disk        = $_.DiskNumber
            Partition   = $_.PartitionNumber
            Type        = $_.Type
            DriveLetter = "$($_.DriveLetter)".Trim()
            SizeGB      = [math]::Round($_.Size / 1GB, 2)
            Label       = $vol.FileSystemLabel
            FileSystem  = $vol.FileSystem
            FreeGB      = if ($vol) { [math]::Round($vol.SizeRemaining / 1GB, 2) } else { $null }
        }
    })
}

Add-Section 'Graphics' {
    @(Get-Cim Win32_VideoController | ForEach-Object {
        [ordered]@{
            Name          = $_.Name
            DriverVersion = $_.DriverVersion
            DriverDate    = $_.DriverDate
            Resolution    = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
        }
    })
}

Add-Section 'Monitors' {
    $decode = { param($codes) -join ($codes | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) }
    @(Get-Cim WmiMonitorID -Namespace 'root/wmi' | ForEach-Object {
        [ordered]@{
            Manufacturer = & $decode $_.ManufacturerName
            Model        = & $decode $_.UserFriendlyName
            SerialNumber = & $decode $_.SerialNumberID
            Year         = $_.YearOfManufacture
        }
    })
}

Add-Section 'Network' {
    @(Get-NetAdapter -IncludeHidden:$false | ForEach-Object {
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
    $batteries = @(Get-Cim Win32_Battery)
    if (-not $batteries) { return 'No battery' }
    $static = @(Get-Cim BatteryStaticData -Namespace 'root/wmi' -ErrorAction SilentlyContinue)
    $full = @(Get-Cim BatteryFullChargedCapacity -Namespace 'root/wmi' -ErrorAction SilentlyContinue)
    $batteryReport = Join-Path $OutputPath 'battery-report.html'
    powercfg /batteryreport /output "$batteryReport" | Out-Null
    [ordered]@{
        Name                   = $batteries.Name
        ChargePercent          = $batteries.EstimatedChargeRemaining
        DesignCapacityMWh      = $static.DesignedCapacity
        FullChargeCapacityMWh  = $full.FullChargedCapacity
        HealthPercent          = if ($static -and $full) {
            [math]::Round(100 * $full[0].FullChargedCapacity / $static[0].DesignedCapacity, 1)
        } else { $null }
        Report                 = 'battery-report.html'
    }
}

Add-Section 'Security' {
    $tpm = Get-Tpm
    $tpmVersion = (Get-Cim Win32_Tpm -Namespace 'root/cimv2/Security/MicrosoftTpm').SpecVersion
    $bitlocker = @(Get-BitLockerVolume -ErrorAction SilentlyContinue | ForEach-Object {
        [ordered]@{
            Mount      = $_.MountPoint
            Protection = "$($_.ProtectionStatus)"
            Status     = "$($_.VolumeStatus)"
            Method     = "$($_.EncryptionMethod)"
        }
    })
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    [ordered]@{
        TpmPresent        = $tpm.TpmPresent
        TpmReady          = $tpm.TpmReady
        TpmVersion        = $tpmVersion
        TpmManufacturer   = $tpm.ManufacturerIdTxt
        BitLocker         = $bitlocker
        DefenderEnabled   = $defender.AntivirusEnabled
        DefenderSignature = $defender.AntivirusSignatureVersion
    }
}

Add-Section 'InstalledUpdates' {
    @(Get-HotFix | Sort-Object InstalledOn -Descending | ForEach-Object {
        [ordered]@{
            Id          = $_.HotFixID
            Description = $_.Description
            InstalledOn = $_.InstalledOn
        }
    })
}

Add-Section 'PendingUpdates' {
    if ($SkipUpdateSearch) { return 'Skipped' }
    Write-Host '  Searching Windows Update online, this can take a few minutes...'
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
    @($result.Updates | ForEach-Object {
        [ordered]@{
            Title    = $_.Title
            KB       = ($_.KBArticleIDs | ForEach-Object { "KB$_" }) -join ', '
            Category = ($_.Categories | Select-Object -First 1).Name
            SizeMB   = [math]::Round($_.MaxDownloadSize / 1MB, 1)
        }
    })
}

Add-Section 'Drivers' {
    @(Get-Cim Win32_PnPSignedDriver -Filter 'DeviceName IS NOT NULL' |
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
    )
    @(Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        Sort-Object DisplayName -Unique | ForEach-Object {
            [ordered]@{
                Name      = $_.DisplayName
                Version   = $_.DisplayVersion
                Publisher = $_.Publisher
            }
        })
}

$jsonPath = Join-Path $OutputPath 'machine-info.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

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
$summary | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "`nDone. Results in: $OutputPath"
