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

$Inventory = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
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

function Str([object]$Value){
  if($null -eq $Value){ return "" }
  return [string]$Value
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$disks = @()

foreach($disk in @(Get-Disk | Sort-Object Number)){
  $dn = [int]$disk.Number

  $parts = @()
  foreach($p in @(Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)){
    $access = @()
    try {
      foreach($ap in @($p.AccessPaths)){
        if(-not [string]::IsNullOrWhiteSpace([string]$ap)){
          $access += [string]$ap
        }
      }
    } catch {
      $access = @()
    }

    $parts += ,([ordered]@{
      partition_number = [int]$p.PartitionNumber
      drive_letter = [string]$p.DriveLetter
      type = [string]$p.Type
      size_bytes = [UInt64]$p.Size
      access_paths = @($access)
    })
  }

  $vols = @()
  foreach($v in @(Get-Volume -ErrorAction SilentlyContinue | Sort-Object DriveLetter)){
    $vols += ,([ordered]@{
      drive_letter = [string]$v.DriveLetter
      path = [string]$v.Path
      file_system = [string]$v.FileSystem
      label = [string]$v.FileSystemLabel
      drive_type = [string]$v.DriveType
      health_status = [string]$v.HealthStatus
      operational_status = [string]$v.OperationalStatus
      size_bytes = $(if($null -ne $v.Size){ [UInt64]$v.Size } else { [UInt64]0 })
      size_remaining_bytes = $(if($null -ne $v.SizeRemaining){ [UInt64]$v.SizeRemaining } else { [UInt64]0 })
    })
  }

  $disks += ,([ordered]@{
    disk_number = $dn
    friendly_name = Str $disk.FriendlyName
    serial_number = Str $disk.SerialNumber
    bus_type = Str $disk.BusType
    partition_style = Str $disk.PartitionStyle
    operational_status = Str $disk.OperationalStatus
    health_status = Str $disk.HealthStatus
    is_boot = [bool]$disk.IsBoot
    is_system = [bool]$disk.IsSystem
    is_offline = [bool]$disk.IsOffline
    is_read_only = [bool]$disk.IsReadOnly
    size_bytes = [UInt64]$disk.Size
    partition_count = [int]$parts.Count
    partitions = @($parts)
  })
}

$receipt = [ordered]@{
  schema = "ld.device.inventory.receipt.v1"
  event_type = "ld.device.inventory.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  disk_count = [int]$disks.Count
  disks = @($disks)
  visible_volume_count = [int]$vols.Count
  visible_volumes = @($vols)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_inventory"
EnsureDir $outDir
$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$outPath = Join-Path $outDir ("inventory_" + $stamp + ".json")

$json = $receipt | ConvertTo-Json -Depth 80 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_INVENTORY_PATH: " + $outPath)
Write-Output ("DEVICE_INVENTORY_COUNT: " + [string]$disks.Count)
Write-Output $json
Write-Output "LD_DEVICE_INVENTORY_OK"
'@

$Mount = @'
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

function ClassifyRow([object]$Disk,[object]$Partition,[object[]]$AccessPaths,[object]$Volume){
  if([bool]$Disk.IsOffline){ return "disk_offline" }
  if($null -eq $Partition){ return "no_partition" }

  $dl = [string]$Partition.DriveLetter

  if(-not [string]::IsNullOrWhiteSpace($dl)){
    if($null -eq $Volume){ return "drive_letter_present_volume_lookup_failed" }
    if([string]::IsNullOrWhiteSpace([string]$Volume.FileSystem)){ return "drive_letter_raw_or_unformatted" }
    return "drive_letter_mounted"
  }

  if($AccessPaths -and $AccessPaths.Count -gt 0){
    return "mounted_without_drive_letter"
  }

  return "partition_without_mount"
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$diskList = @()
if($DiskNumber -ge 0){
  $diskList = @(Get-Disk -Number $DiskNumber -ErrorAction Stop)
} else {
  $diskList = @(Get-Disk | Sort-Object Number)
}

$rows = @()

foreach($disk in @($diskList)){
  $dn = [int]$disk.Number
  $parts = @(Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)

  if($parts.Count -eq 0){
    $rows += ,([ordered]@{
      disk_number = $dn
      partition_number = $null
      bus_type = [string]$disk.BusType
      drive_letter = ""
      access_paths = @()
      file_system = ""
      mount_state = "no_partition"
      backup_relevance = "RAW_DISK_ONLY"
    })
    continue
  }

  foreach($p in @($parts)){
    $access = @()
    try {
      foreach($ap in @($p.AccessPaths)){
        if(-not [string]::IsNullOrWhiteSpace([string]$ap)){
          $access += [string]$ap
        }
      }
    } catch {
      $access = @()
    }

    $vol = $null
    if(-not [string]::IsNullOrWhiteSpace([string]$p.DriveLetter)){
      try {
        $vol = Get-Volume -DriveLetter ([string]$p.DriveLetter) -ErrorAction Stop
      } catch {
        $vol = $null
      }
    }

    $state = ClassifyRow -Disk $disk -Partition $p -AccessPaths $access -Volume $vol

    $relevance = "RAW_IMAGE_REVIEW"
    if($state -eq "drive_letter_mounted"){
      $relevance = "FILE_BACKUP_AND_RAW_IMAGE_CANDIDATE"
    } elseif($state -eq "mounted_without_drive_letter") {
      $relevance = "RAW_IMAGE_CANDIDATE_NON_LETTERED"
    } elseif($state -match "raw|unformatted") {
      $relevance = "RAW_IMAGE_RECOMMENDED_BEFORE_FORMAT"
    } elseif($state -eq "partition_without_mount") {
      $relevance = "RAW_IMAGE_CANDIDATE_NO_MOUNT"
    } elseif($state -eq "disk_offline") {
      $relevance = "OFFLINE_NEEDS_OPERATOR_ACTION"
    }

    $rows += ,([ordered]@{
      disk_number = $dn
      partition_number = [int]$p.PartitionNumber
      bus_type = [string]$disk.BusType
      disk_operational_status = [string]$disk.OperationalStatus
      disk_health_status = [string]$disk.HealthStatus
      disk_is_offline = [bool]$disk.IsOffline
      disk_is_read_only = [bool]$disk.IsReadOnly
      partition_type = [string]$p.Type
      partition_size_bytes = [UInt64]$p.Size
      drive_letter = [string]$p.DriveLetter
      access_paths = @($access)
      file_system = $(if($null -ne $vol){ [string]$vol.FileSystem } else { "" })
      volume_label = $(if($null -ne $vol){ [string]$vol.FileSystemLabel } else { "" })
      volume_health_status = $(if($null -ne $vol){ [string]$vol.HealthStatus } else { "" })
      volume_operational_status = $(if($null -ne $vol){ [string]$vol.OperationalStatus } else { "" })
      mount_state = $state
      backup_relevance = $relevance
    })
  }
}

$receipt = [ordered]@{
  schema = "ld.device.mount_state.receipt.v1"
  event_type = "ld.device.mount_state.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  disk_filter = $(if($DiskNumber -ge 0){ [string]$DiskNumber } else { "all" })
  row_count = [int]$rows.Count
  rows = @($rows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_mount_state"
EnsureDir $outDir
$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$outPath = Join-Path $outDir ("mount_state_" + $stamp + ".json")

$json = $receipt | ConvertTo-Json -Depth 80 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_MOUNT_STATE_PATH: " + $outPath)
Write-Output ("DEVICE_MOUNT_STATE_ROWS: " + [string]$rows.Count)
Write-Output $json
Write-Output "LD_DEVICE_MOUNT_STATE_OK"
'@

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
$Inv = Join-Path $RepoRoot "scripts\storage\ld_device_inventory_v1.ps1"
$Mount = Join-Path $RepoRoot "scripts\storage\ld_mount_state_v1.ps1"

$outInv = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Inv -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "INVENTORY_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$outMount = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Mount -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "MOUNT_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$invText = ($outInv -join "`n")
$mountText = ($outMount -join "`n")

if($invText -notmatch "LD_DEVICE_INVENTORY_OK"){ Die "INVENTORY_TOKEN_MISSING" "" }
if($mountText -notmatch "LD_DEVICE_MOUNT_STATE_OK"){ Die "MOUNT_TOKEN_MISSING" "" }

Write-Output $invText
Write-Output $mountText
Write-Output "PASS: device inventory emitted"
Write-Output "PASS: mount state emitted"
Write-Output "SELFTEST_LD_STORAGE03_INVENTORY_MOUNT_OK"
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
  (Join-Path $RepoRoot "scripts\storage\ld_device_inventory_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_mount_state_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_inventory_mount_v1.ps1")
)

foreach($f in @($files)){
  Parse-GateFile $f
}

$schemas = @(
  (Join-Path $RepoRoot "schemas\ld.device.inventory.receipt.v1.json"),
  (Join-Path $RepoRoot "schemas\ld.device.mount_state.receipt.v1.json")
)

foreach($s in @($schemas)){
  if(-not (Test-Path -LiteralPath $s -PathType Leaf)){
    Die "SCHEMA_MISSING" $s
  }

  Write-Output ("SCHEMA_OK: " + $s)
}

$selftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_inventory_mount_v1.ps1"
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $selftest -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "SELFTEST_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$outText = ($out -join "`n")
Write-Output $outText

if($outText -notmatch "SELFTEST_LD_STORAGE03_INVENTORY_MOUNT_OK"){
  Die "SELFTEST_TOKEN_MISSING" ""
}

Write-Output "LEGACY_DOCTOR_STORAGE03_INVENTORY_MOUNT_GREEN"
'@

$SchemaInventory = '{"$schema":"https://json-schema.org/draft/2020-12/schema","title":"Legacy Doctor Device Inventory Receipt v1","type":"object","required":["schema","event_type","ok","repo_root","disk_count","disks","created_utc"],"properties":{"schema":{"const":"ld.device.inventory.receipt.v1"},"event_type":{"const":"ld.device.inventory.receipt.v1"},"ok":{"type":"boolean"},"repo_root":{"type":"string"},"disk_count":{"type":"integer"},"disks":{"type":"array"},"created_utc":{"type":"string"}}}'
$SchemaMount = '{"$schema":"https://json-schema.org/draft/2020-12/schema","title":"Legacy Doctor Device Mount State Receipt v1","type":"object","required":["schema","event_type","ok","repo_root","disk_filter","row_count","rows","created_utc"],"properties":{"schema":{"const":"ld.device.mount_state.receipt.v1"},"event_type":{"const":"ld.device.mount_state.receipt.v1"},"ok":{"type":"boolean"},"repo_root":{"type":"string"},"disk_filter":{"type":"string"},"row_count":{"type":"integer"},"rows":{"type":"array"},"created_utc":{"type":"string"}}}'

$Docs = @'
# LD-STORAGE-03 Device Capability Lane v1

Status: first checkpoint.

This lane is non-destructive.

Current scope:
- device inventory
- partitions
- volumes
- drive-letter mounted state
- no-drive-letter / no-partition recognition where Windows exposes enough metadata
- mount classification receipt
- backup relevance recommendation

This does not yet prove:
- benchmarking
- real raw imaging across all device classes
- snapshot acquisition
- complete SMART/vendor health
- full formatting coverage
- canonical storage library completeness

Next checkpoints:
- health probe v1
- read benchmark v1
- backup readiness v1
- real hardware walkthrough matrix
'@

Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\storage\ld_device_inventory_v1.ps1") $Inventory
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\storage\ld_mount_state_v1.ps1") $Mount
Write-Utf8NoBomLf (Join-Path $RepoRoot "schemas\ld.device.inventory.receipt.v1.json") $SchemaInventory
Write-Utf8NoBomLf (Join-Path $RepoRoot "schemas\ld.device.mount_state.receipt.v1.json") $SchemaMount
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_inventory_mount_v1.ps1") $Selftest
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_storage03_inventory_mount_v1.ps1") $Runner
Write-Utf8NoBomLf (Join-Path $RepoRoot "docs\WBS\LD_STORAGE_03_DEVICE_CAPABILITY_v1.md") $Docs

$toParse = @(
  (Join-Path $RepoRoot "scripts\storage\ld_device_inventory_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_mount_state_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_inventory_mount_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_storage03_inventory_mount_v1.ps1")
)

foreach($p in @($toParse)){
  Parse-GateFile $p
}

Write-Host "LD_STORAGE03_INVENTORY_MOUNT_FILES_READY" -ForegroundColor Green