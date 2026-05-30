param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDHEALTH-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDHEALTH-GetRecommendation([hashtable]$Probe){
  if($null -eq $Probe){
    LDHEALTH-Die "NULL_PROBE" "probe"
  }

  $bus = [string]$Probe.bus_type
  $health = [string]$Probe.health_status
  $volumes = @($Probe.volumes)
  $partitionStyle = [string]$Probe.partition_style

  if($volumes.Count -eq 0){
    return "NO_MEDIA_PRESENT"
  }

  $hasBlankFs = $false
  foreach($v in $volumes){
    if([string]::IsNullOrWhiteSpace([string]$v.file_system)){
      $hasBlankFs = $true
    }
  }

  if($hasBlankFs){
    return "READ_ONLY_BACKUP_FIRST"
  }

  if($health -eq "Unhealthy" -or $health -eq "Warning"){
    return "READ_ONLY_BACKUP_FIRST"
  }

  if($bus -eq "USB"){
    return "SAFE_FILE_COPY"
  }

  if($partitionStyle -eq "RAW"){
    return "FORMAT_ONLY_AFTER_CAPTURE"
  }

  return "RAW_IMAGE_RECOMMENDED"
}

function LDHEALTH-GetHealthSignals([hashtable]$Probe){
  if($null -eq $Probe){
    LDHEALTH-Die "NULL_PROBE" "probe"
  }

  $signals = @()

  if([bool]$Probe.is_boot){ $signals += "BOOT_DISK" }
  if([bool]$Probe.is_system){ $signals += "SYSTEM_DISK" }

  $health = [string]$Probe.health_status
  if(-not [string]::IsNullOrWhiteSpace($health)){
    $signals += ("WINDOWS_HEALTH:" + $health.ToUpperInvariant())
  }

  $op = [string]$Probe.operational_status
  if(-not [string]::IsNullOrWhiteSpace($op)){
    $signals += ("WINDOWS_OPERATIONAL:" + $op.ToUpperInvariant())
  }

  foreach($v in @($Probe.volumes)){
    $fs = [string]$v.file_system
    if([string]::IsNullOrWhiteSpace($fs)){
      $signals += ("VOLUME_" + [string]$v.drive_letter + "_NO_FILESYSTEM")
    } else {
      $signals += ("VOLUME_" + [string]$v.drive_letter + "_FS_" + $fs.ToUpperInvariant())
    }
  }

  return $signals
}

function LDHEALTH-GetHealthSummary([hashtable]$Probe){
  if($null -eq $Probe){
    LDHEALTH-Die "NULL_PROBE" "probe"
  }

  $health = [string]$Probe.health_status
  if($health -eq "Unhealthy"){ return "AT_RISK" }
  if($health -eq "Warning"){ return "WARNING" }

  foreach($v in @($Probe.volumes)){
    if([string]::IsNullOrWhiteSpace([string]$v.file_system)){
      return "WARNING"
    }
  }

  if([string]::IsNullOrWhiteSpace([string]$health)){
    return "UNKNOWN"
  }

  if($health -eq "Healthy"){ return "HEALTHY" }
  return "UNKNOWN"
}

function LDHEALTH-BuildHealthReceipt([string]$RepoRoot,[hashtable]$Probe){
  if([string]::IsNullOrWhiteSpace($RepoRoot)){
    LDHEALTH-Die "BAD_ARG" "RepoRoot"
  }
  if($null -eq $Probe){
    LDHEALTH-Die "NULL_PROBE" "probe"
  }

  return [ordered]@{
    schema = "ld.device.health.receipt.v1"
    event_type = "ld.device.health.receipt.v1"
    ok = $true
    repo_root = $RepoRoot
    device_id = [string]$Probe.device_id
    disk_number = [int]$Probe.disk_number
    health_summary = (LDHEALTH-GetHealthSummary -Probe $Probe)
    signals = (LDHEALTH-GetHealthSignals -Probe $Probe)
    preservation_recommendation = (LDHEALTH-GetRecommendation -Probe $Probe)
  }
}

function LDHEALTH-BuildInspectReceipt([string]$RepoRoot,[hashtable]$Probe){
  if([string]::IsNullOrWhiteSpace($RepoRoot)){
    LDHEALTH-Die "BAD_ARG" "RepoRoot"
  }
  if($null -eq $Probe){
    LDHEALTH-Die "NULL_PROBE" "probe"
  }

  return [ordered]@{
    schema = "ld.device.inspect.receipt.v1"
    event_type = "ld.device.inspect.receipt.v1"
    ok = $true
    repo_root = $RepoRoot
    device_id = [string]$Probe.device_id
    disk_number = [int]$Probe.disk_number
    friendly_name = [string]$Probe.friendly_name
    serial_number = [string]$Probe.serial_number
    bus_type = [string]$Probe.bus_type
    partition_style = [string]$Probe.partition_style
    is_boot = [bool]$Probe.is_boot
    is_system = [bool]$Probe.is_system
    operational_status = [string]$Probe.operational_status
    health_status = [string]$Probe.health_status
    size_bytes = [UInt64]$Probe.size_bytes
    partitions = @($Probe.partitions)
    volumes = @($Probe.volumes)
    preservation_recommendation = (LDHEALTH-GetRecommendation -Probe $Probe)
  }
}

function LDHEALTH-ExportModuleInfo(){
  return [ordered]@{
    schema = "ld.device.health.lib.info.v1"
    name = "_lib_ld_health_v1.ps1"
    provides = @(
      "LDHEALTH-GetRecommendation",
      "LDHEALTH-GetHealthSignals",
      "LDHEALTH-GetHealthSummary",
      "LDHEALTH-BuildHealthReceipt",
      "LDHEALTH-BuildInspectReceipt"
    )
  }
}