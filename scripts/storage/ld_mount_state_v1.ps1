param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$DiskNumber = -1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function NormalizeDriveLetter([object]$Value){
  if($null -eq $Value){ return "" }

  $s = [string]$Value
  $s = $s.Replace([string][char]0,"").Trim()

  if([string]::IsNullOrWhiteSpace($s)){ return "" }

  return $s
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

function ClassifyRow([object]$Disk,[object]$Partition,[object[]]$AccessPaths,[object]$Volume){
  if([bool]$Disk.IsOffline){ return "disk_offline" }
  if($null -eq $Partition){ return "no_partition" }

  $dl = (NormalizeDriveLetter $Partition.DriveLetter)

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
    if(-not [string]::IsNullOrWhiteSpace((NormalizeDriveLetter $p.DriveLetter))){
      try {
        $vol = Get-Volume -DriveLetter ((NormalizeDriveLetter $p.DriveLetter)) -ErrorAction Stop
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
      drive_letter = (NormalizeDriveLetter $p.DriveLetter)
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
