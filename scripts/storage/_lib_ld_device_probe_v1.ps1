param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDPROBE-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDPROBE-HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($t)
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function LDPROBE-GetDeviceId([object]$Disk){
  $seed = "disk|" + `
    [string]$Disk.Number + "|" + `
    [string]$Disk.FriendlyName + "|" + `
    [string]$Disk.SerialNumber + "|" + `
    [string]$Disk.BusType + "|" + `
    [string]([UInt64]$Disk.Size)

  return ("win.disk.v1:" + [string]$Disk.Number + ":" + (LDPROBE-HexSha256TextLf $seed))
}

function LDPROBE-GetPartitions([int]$DiskNumber){
  $rows = @()
  $parts = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue)

  foreach($p in $parts){
    $rows += ,([ordered]@{
      partition_number = [int]$p.PartitionNumber
      drive_letter = [string]$p.DriveLetter
      type = [string]$p.Type
      size_bytes = [UInt64]$p.Size
    })
  }

  return @($rows)
}

function LDPROBE-GetVolumesFromPartitions([object[]]$Partitions){
  $rows = @()

  foreach($p in @($Partitions)){
    if([string]::IsNullOrWhiteSpace([string]$p.drive_letter)){ continue }

    $v = $null
    try {
      $v = Get-Volume -DriveLetter ([string]$p.drive_letter) -ErrorAction Stop
    } catch {
      $v = $null
    }

    if($null -eq $v){
      $rows += ,([ordered]@{
        drive_letter = [string]$p.drive_letter
        file_system = ""
        file_system_label = ""
        size_bytes = [UInt64]0
        size_remaining_bytes = [UInt64]0
        drive_type = ""
      })
      continue
    }

    $rows += ,([ordered]@{
      drive_letter = [string]$v.DriveLetter
      file_system = [string]$v.FileSystem
      file_system_label = [string]$v.FileSystemLabel
      size_bytes = [UInt64]$v.Size
      size_remaining_bytes = [UInt64]$v.SizeRemaining
      drive_type = [string]$v.DriveType
    })
  }

  return @($rows)
}

function LDPROBE-GetDiskProbe([int]$DiskNumber){
  if($DiskNumber -lt 0){
    LDPROBE-Die "DISKNUMBER_REQUIRED" "disk number must be >= 0"
  }

  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  $deviceId = LDPROBE-GetDeviceId $disk
  $parts = @(LDPROBE-GetPartitions -DiskNumber $DiskNumber)
  $vols = @(LDPROBE-GetVolumesFromPartitions -Partitions $parts)

  return [ordered]@{
    schema = "ld.device.probe.v1"
    device_id = $deviceId
    disk_number = [int]$disk.Number
    friendly_name = [string]$disk.FriendlyName
    serial_number = [string]$disk.SerialNumber
    bus_type = [string]$disk.BusType
    partition_style = [string]$disk.PartitionStyle
    is_boot = [bool]$disk.IsBoot
    is_system = [bool]$disk.IsSystem
    operational_status = [string]$disk.OperationalStatus
    health_status = [string]$disk.HealthStatus
    size_bytes = [UInt64]$disk.Size
    partitions = @($parts)
    volumes = @($vols)
  }
}

function LDPROBE-ListDisks(){
  $rows = @()

  foreach($disk in @(Get-Disk | Sort-Object Number)){
    $rows += ,([ordered]@{
      disk_number = [int]$disk.Number
      device_id = LDPROBE-GetDeviceId $disk
      friendly_name = [string]$disk.FriendlyName
      bus_type = [string]$disk.BusType
      size_bytes = [UInt64]$disk.Size
      partition_style = [string]$disk.PartitionStyle
      operational_status = [string]$disk.OperationalStatus
      health_status = [string]$disk.HealthStatus
    })
  }

  return @($rows)
}

function LDPROBE-ExportModuleInfo(){
  return [ordered]@{
    schema = "ld.device.probe.lib.info.v1"
    name = "_lib_ld_device_probe_v1.ps1"
    provides = @(
      "LDPROBE-GetDeviceId",
      "LDPROBE-GetPartitions",
      "LDPROBE-GetVolumesFromPartitions",
      "LDPROBE-GetDiskProbe",
      "LDPROBE-ListDisks"
    )
  }
}