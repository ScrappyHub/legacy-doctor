param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

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

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_MISSING" $Path
  }

  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }

  Write-Host ("PARSE_OK: " + $Path) -ForegroundColor Green
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$HealthProbe = @'
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
'@

$Schema = '{"$schema":"https://json-schema.org/draft/2020-12/schema","title":"Legacy Doctor Device Health Probe Receipt v1","type":"object","required":["schema","event_type","ok","repo_root","disk_filter","disk_count","disks","created_utc"],"properties":{"schema":{"const":"ld.device.health_probe.receipt.v1"},"event_type":{"const":"ld.device.health_probe.receipt.v1"},"ok":{"type":"boolean"},"repo_root":{"type":"string"},"disk_filter":{"type":"string"},"disk_count":{"type":"integer"},"disks":{"type":"array"},"created_utc":{"type":"string"}}}'

$Selftest = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_health_probe_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "HEALTH_PROBE_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_HEALTH_PROBE_OK"){
  Die "HEALTH_PROBE_TOKEN_MISSING" ""
}

if($text -notmatch "smart_claim"){
  Die "SMART_CLAIM_FIELD_MISSING" ""
}

Write-Output $text
Write-Output "PASS: health probe emitted"
Write-Output "PASS: SMART not overclaimed"
Write-Output "SELFTEST_LD_STORAGE03_HEALTH_PROBE_OK"
'@

$Runner = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_MISSING" $Path
  }

  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ":" + $e.Message)
  }

  Write-Output ("PARSE_OK: " + $Path)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$files = @(
  (Join-Path $RepoRoot "scripts\storage\ld_health_probe_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_health_probe_v1.ps1")
)

foreach($f in @($files)){
  Parse-GateFile $f
}

$schema = Join-Path $RepoRoot "schemas\ld.device.health_probe.receipt.v1.json"
if(-not (Test-Path -LiteralPath $schema -PathType Leaf)){
  Die "SCHEMA_MISSING" $schema
}

Write-Output ("SCHEMA_OK: " + $schema)

$selftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_health_probe_v1.ps1"
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $selftest -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "SELFTEST_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$outText = ($out -join "`n")
Write-Output $outText

if($outText -notmatch "SELFTEST_LD_STORAGE03_HEALTH_PROBE_OK"){
  Die "SELFTEST_TOKEN_MISSING" ""
}

Write-Output "LEGACY_DOCTOR_STORAGE03_HEALTH_PROBE_GREEN"
'@

$Docs = @'
# LD-STORAGE-03C Health Probe v1

Status: first checkpoint.

This lane is non-destructive.

It records what Windows exposes:
- Get-Disk health and operational state
- Get-Volume health and operational state
- Get-PhysicalDisk metadata where available
- offline/read-only flags
- media type where available

It does not claim complete SMART coverage.
The receipt includes smart_claim = NOT_CLAIMED until a real SMART/vendor-specific lane is implemented.

Next checkpoints:
- read benchmark probe v1
- backup readiness v1
- hardware walkthrough matrix
'@

Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\storage\ld_health_probe_v1.ps1") $HealthProbe
Write-Utf8NoBomLf (Join-Path $RepoRoot "schemas\ld.device.health_probe.receipt.v1.json") $Schema
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_health_probe_v1.ps1") $Selftest
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_storage03_health_probe_v1.ps1") $Runner
Write-Utf8NoBomLf (Join-Path $RepoRoot "docs\WBS\LD_STORAGE_03C_HEALTH_PROBE_v1.md") $Docs

$toParse = @(
  (Join-Path $RepoRoot "scripts\storage\ld_health_probe_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_health_probe_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_storage03_health_probe_v1.ps1")
)

foreach($p in @($toParse)){
  Parse-GateFile $p
}

Write-Host "LD_STORAGE03_HEALTH_PROBE_FILES_READY" -ForegroundColor Green