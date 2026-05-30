param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$DiskNumber = -1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function NormalizeDriveLetter([object]$Value){
  if($null -eq $Value){ return "" }

  $s = [string]$Value
  $s = $s.Replace([string][char]0,"").Trim()

  if([string]::IsNullOrWhiteSpace($s)){ return "" }

  return $s
}

function SafeStr([object]$Value){
  if($null -eq $Value){ return "" }
  return [string]$Value
}

function SafeBool([object]$Value){
  if($null -eq $Value){ return $false }
  return [bool]$Value
}

function SafeU64([object]$Value){
  if($null -eq $Value){ return [UInt64]0 }
  return [UInt64]$Value
}

function HasProp([object]$Obj,[string]$Name){
  if($null -eq $Obj){ return $false }
  return (@($Obj.PSObject.Properties.Name) -contains $Name)
}

function GetProp([object]$Obj,[string]$Name){
  if(-not (HasProp $Obj $Name)){ return $null }
  return $Obj.PSObject.Properties[$Name].Value
}

function ClassifyHealth([object]$Disk,[object[]]$Volumes,[object]$PhysicalDisk){
  $signals = @()

  $diskHealth = SafeStr (GetProp $Disk "HealthStatus")
  $diskOperational = SafeStr (GetProp $Disk "OperationalStatus")
  $isOffline = SafeBool (GetProp $Disk "IsOffline")
  $isReadOnly = SafeBool (GetProp $Disk "IsReadOnly")

  if($isOffline){ $signals += "DISK_OFFLINE" }
  if($isReadOnly){ $signals += "DISK_READ_ONLY" }
  if(-not [string]::IsNullOrWhiteSpace($diskHealth)){ $signals += ("DISK_HEALTH:" + $diskHealth.ToUpperInvariant()) }
  if(-not [string]::IsNullOrWhiteSpace($diskOperational)){ $signals += ("DISK_OPERATIONAL:" + $diskOperational.ToUpperInvariant()) }

  foreach($v in @($Volumes)){
    $dl = NormalizeDriveLetter (GetProp $v "DriveLetter")
    $fs = SafeStr (GetProp $v "FileSystem")
    $vh = SafeStr (GetProp $v "HealthStatus")
    $vo = SafeStr (GetProp $v "OperationalStatus")

    $label = $dl
    if([string]::IsNullOrWhiteSpace($label)){
      $label = SafeStr (GetProp $v "Path")
    }

    if(-not [string]::IsNullOrWhiteSpace($fs)){
      $signals += ("VOLUME_FS:" + $label + ":" + $fs.ToUpperInvariant())
    }

    if(-not [string]::IsNullOrWhiteSpace($vh)){
      $signals += ("VOLUME_HEALTH:" + $label + ":" + $vh.ToUpperInvariant())
    }

    if(-not [string]::IsNullOrWhiteSpace($vo)){
      $signals += ("VOLUME_OPERATIONAL:" + $label + ":" + $vo.ToUpperInvariant())
    }
  }

  if($null -ne $PhysicalDisk){
    $pdHealth = SafeStr (GetProp $PhysicalDisk "HealthStatus")
    $pdOperational = SafeStr (GetProp $PhysicalDisk "OperationalStatus")
    $mediaType = SafeStr (GetProp $PhysicalDisk "MediaType")
    $canPool = SafeStr (GetProp $PhysicalDisk "CanPool")

    if(-not [string]::IsNullOrWhiteSpace($pdHealth)){ $signals += ("PHYSICAL_HEALTH:" + $pdHealth.ToUpperInvariant()) }
    if(-not [string]::IsNullOrWhiteSpace($pdOperational)){ $signals += ("PHYSICAL_OPERATIONAL:" + $pdOperational.ToUpperInvariant()) }
    if(-not [string]::IsNullOrWhiteSpace($mediaType)){ $signals += ("PHYSICAL_MEDIA_TYPE:" + $mediaType.ToUpperInvariant()) }
    if(-not [string]::IsNullOrWhiteSpace($canPool)){ $signals += ("PHYSICAL_CAN_POOL:" + $canPool.ToUpperInvariant()) }
  } else {
    $signals += "PHYSICAL_DISK_METADATA_UNAVAILABLE"
  }

  $summary = "HEALTH_REVIEW"
  if($isOffline){
    $summary = "OFFLINE"
  } elseif($diskHealth -match "Unhealthy|Warning|Unknown") {
    $summary = "REVIEW_REQUIRED"
  } elseif($diskOperational -notmatch "Online|OK") {
    $summary = "REVIEW_REQUIRED"
  } else {
    $summary = "WINDOWS_HEALTH_OK"
  }

  return [ordered]@{
    health_summary = $summary
    signals = @($signals)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$diskList = @()
if($DiskNumber -ge 0){
  $diskList = @(Get-Disk -Number $DiskNumber -ErrorAction Stop)
} else {
  $diskList = @(Get-Disk | Sort-Object Number)
}

$physicalDisks = @()
try {
  $physicalDisks = @(Get-PhysicalDisk -ErrorAction Stop)
} catch {
  $physicalDisks = @()
}

$allVolumes = @()
try {
  $allVolumes = @(Get-Volume -ErrorAction Stop)
} catch {
  $allVolumes = @()
}

$rows = @()

foreach($disk in @($diskList)){
  $dn = [int]$disk.Number

  $parts = @(Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)
  $diskVolumes = @()

  foreach($p in @($parts)){
    $dl = NormalizeDriveLetter $p.DriveLetter

    if(-not [string]::IsNullOrWhiteSpace($dl)){
      try {
        $diskVolumes += ,(Get-Volume -DriveLetter $dl -ErrorAction Stop)
      } catch {
      }
    } else {
      foreach($ap in @($p.AccessPaths)){
        if([string]::IsNullOrWhiteSpace([string]$ap)){ continue }

        foreach($v in @($allVolumes)){
          if((SafeStr (GetProp $v "Path")) -eq [string]$ap){
            $diskVolumes += ,$v
          }
        }
      }
    }
  }

  $physicalMatch = $null
  foreach($pd in @($physicalDisks)){
    $pdFriendly = SafeStr (GetProp $pd "FriendlyName")
    $diskFriendly = SafeStr (GetProp $disk "FriendlyName")

    if(( -not [string]::IsNullOrWhiteSpace($pdFriendly)) -and ($pdFriendly -eq $diskFriendly)){
      $physicalMatch = $pd
      break
    }
  }

  $classification = ClassifyHealth -Disk $disk -Volumes @($diskVolumes) -PhysicalDisk $physicalMatch

  $volumeRows = @()
  foreach($v in @($diskVolumes)){
    $volumeRows += ,([ordered]@{
      drive_letter = NormalizeDriveLetter (GetProp $v "DriveLetter")
      path = SafeStr (GetProp $v "Path")
      file_system = SafeStr (GetProp $v "FileSystem")
      label = SafeStr (GetProp $v "FileSystemLabel")
      drive_type = SafeStr (GetProp $v "DriveType")
      health_status = SafeStr (GetProp $v "HealthStatus")
      operational_status = SafeStr (GetProp $v "OperationalStatus")
      size_bytes = SafeU64 (GetProp $v "Size")
      size_remaining_bytes = SafeU64 (GetProp $v "SizeRemaining")
    })
  }

  $physicalRow = $null
  if($null -ne $physicalMatch){
    $physicalRow = [ordered]@{
      friendly_name = SafeStr (GetProp $physicalMatch "FriendlyName")
      serial_number = SafeStr (GetProp $physicalMatch "SerialNumber")
      media_type = SafeStr (GetProp $physicalMatch "MediaType")
      health_status = SafeStr (GetProp $physicalMatch "HealthStatus")
      operational_status = SafeStr (GetProp $physicalMatch "OperationalStatus")
      can_pool = SafeStr (GetProp $physicalMatch "CanPool")
      size_bytes = SafeU64 (GetProp $physicalMatch "Size")
    }
  }

  $rows += ,([ordered]@{
    disk_number = $dn
    friendly_name = SafeStr (GetProp $disk "FriendlyName")
    serial_number = SafeStr (GetProp $disk "SerialNumber")
    bus_type = SafeStr (GetProp $disk "BusType")
    partition_style = SafeStr (GetProp $disk "PartitionStyle")
    operational_status = SafeStr (GetProp $disk "OperationalStatus")
    health_status = SafeStr (GetProp $disk "HealthStatus")
    is_boot = SafeBool (GetProp $disk "IsBoot")
    is_system = SafeBool (GetProp $disk "IsSystem")
    is_offline = SafeBool (GetProp $disk "IsOffline")
    is_read_only = SafeBool (GetProp $disk "IsReadOnly")
    size_bytes = SafeU64 (GetProp $disk "Size")
    volume_count = [int]$volumeRows.Count
    volumes = @($volumeRows)
    physical_disk = $physicalRow
    smart_claim = "NOT_CLAIMED"
    health_summary = [string]$classification.health_summary
    signals = @($classification.signals)
  })
}

$receipt = [ordered]@{
  schema = "ld.device.health_probe.receipt.v1"
  event_type = "ld.device.health_probe.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  disk_filter = $(if($DiskNumber -ge 0){ [string]$DiskNumber } else { "all" })
  disk_count = [int]$rows.Count
  disks = @($rows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_health_probe"
EnsureDir $outDir
$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$outPath = Join-Path $outDir ("health_probe_" + $stamp + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_HEALTH_PROBE_PATH: " + $outPath)
Write-Output ("DEVICE_HEALTH_PROBE_COUNT: " + [string]$rows.Count)
Write-Output $json
Write-Output "LD_DEVICE_HEALTH_PROBE_OK"
