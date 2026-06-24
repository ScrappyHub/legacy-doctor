param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }

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

function Is-Admin(){
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function First-JsonObjectFromOutput([object[]]$Output,[string]$Schema){
  foreach($line in @($Output)){
    $s = [string]$line
    if($s.StartsWith("{") -and $s.Contains(('"schema":"' + $Schema + '"'))){
      return ($s | ConvertFrom-Json)
    }
  }
  Die "JSON_SCHEMA_OUTPUT_MISSING" $Schema
}

function Run-ReceiptScript([string]$ScriptPath,[string]$Schema){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die "SCRIPT_MISSING" $ScriptPath }

  $out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath -RepoRoot $RepoRoot
  if($LASTEXITCODE -ne 0){ Die "SCRIPT_EXIT_NONZERO" ($ScriptPath + ":" + [string]$LASTEXITCODE) }

  return (First-JsonObjectFromOutput -Output $out -Schema $Schema)
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

function FindReadRow([object]$ReadReceipt,[string]$DriveLetter){
  $dl = NormalizeDriveLetter $DriveLetter
  if([string]::IsNullOrWhiteSpace($dl)){ return $null }

  foreach($r in @($ReadReceipt.rows)){
    if((NormalizeDriveLetter $r.drive_letter) -eq $dl){ return $r }
  }

  return $null
}

function FindHealthDisk([object]$HealthReceipt,[int]$DiskNumber){
  foreach($d in @($HealthReceipt.disks)){
    if([int]$d.disk_number -eq $DiskNumber){ return $d }
  }

  return $null
}

function Add-Unique([object[]]$Items,[string]$Value){
  $out = @($Items)
  if(-not ($out -contains $Value)){ $out += $Value }
  return @($out)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$inventory = Run-ReceiptScript -ScriptPath (Join-Path $RepoRoot "scripts\storage\ld_device_inventory_v1.ps1") -Schema "ld.device.inventory.receipt.v1"
$mount = Run-ReceiptScript -ScriptPath (Join-Path $RepoRoot "scripts\storage\ld_mount_state_v1.ps1") -Schema "ld.device.mount_state.receipt.v1"
$health = Run-ReceiptScript -ScriptPath (Join-Path $RepoRoot "scripts\storage\ld_health_probe_v1.ps1") -Schema "ld.device.health_probe.receipt.v1"
$read = Run-ReceiptScript -ScriptPath (Join-Path $RepoRoot "scripts\storage\ld_read_probe_v1.ps1") -Schema "ld.device.read_probe.receipt.v1"

$admin = Is-Admin
$rows = @()

foreach($m in @($mount.rows)){
  $dn = [int]$m.disk_number
  $drive = NormalizeDriveLetter $m.drive_letter
  $mountState = SafeStr $m.mount_state
  $h = FindHealthDisk -HealthReceipt $health -DiskNumber $dn
  $rr = FindReadRow -ReadReceipt $read -DriveLetter $drive

  $actions = @()
  $reasons = @()

  if(SafeBool $m.disk_is_offline){
    $actions = Add-Unique $actions "OFFLINE_NEEDS_OPERATOR_ACTION"
    $reasons += "disk is offline"
  } else {
    if($null -ne $h){
      if((SafeBool $h.is_boot) -or (SafeBool $h.is_system)){
        $actions = Add-Unique $actions "SKIP_SYSTEM_DISK_BY_DEFAULT"
        $reasons += "boot/system disk is skipped by default"
      }

      if((SafeStr $h.health_summary) -ne "WINDOWS_HEALTH_OK"){
        $actions = Add-Unique $actions "READABLE_BUT_HEALTH_REVIEW"
        $reasons += ("health summary is " + (SafeStr $h.health_summary))
      }
    }

    if($mountState -eq "drive_letter_mounted"){
      if($null -ne $rr -and (SafeBool $rr.read_ok)){
        $actions = Add-Unique $actions "READY_FILE_BACKUP"
        $reasons += ("drive " + $drive + ": read probe succeeded")
      } else {
        $actions = Add-Unique $actions "NO_READABLE_VOLUME"
        $reasons += ("drive " + $drive + ": read probe missing or failed")
      }

      if($admin){ $actions = Add-Unique $actions "READY_RAW_IMAGE_ADMIN_PRESENT" }
      else { $actions = Add-Unique $actions "READY_RAW_IMAGE_NEEDS_ADMIN" }
      $reasons += "raw image requires explicit elevated workflow"
    } elseif($mountState -eq "mounted_without_drive_letter") {
      $actions = Add-Unique $actions "NON_LETTERED_VOLUME_RAW_CANDIDATE"
      if($admin){ $actions = Add-Unique $actions "READY_RAW_IMAGE_ADMIN_PRESENT" }
      else { $actions = Add-Unique $actions "READY_RAW_IMAGE_NEEDS_ADMIN" }
      $reasons += "volume has access path but no drive letter"
    } elseif($mountState -eq "partition_without_mount") {
      $actions = Add-Unique $actions "RAW_PARTITION_CANDIDATE_NO_MOUNT"
      if($admin){ $actions = Add-Unique $actions "READY_RAW_IMAGE_ADMIN_PRESENT" }
      else { $actions = Add-Unique $actions "READY_RAW_IMAGE_NEEDS_ADMIN" }
      $reasons += "partition exists without a mount"
    } elseif($mountState -match "raw|unformatted") {
      $actions = Add-Unique $actions "RAW_VOLUME_DETECTED_IMAGE_BEFORE_FORMAT"
      if($admin){ $actions = Add-Unique $actions "READY_RAW_IMAGE_ADMIN_PRESENT" }
      else { $actions = Add-Unique $actions "READY_RAW_IMAGE_NEEDS_ADMIN" }
      $reasons += "raw/unformatted volume should be imaged before format"
    } else {
      $actions = Add-Unique $actions "BACKUP_READINESS_REVIEW"
      $reasons += ("unhandled mount state: " + $mountState)
    }
  }

  $rows += ,([ordered]@{
    disk_number = $dn
    partition_number = $m.partition_number
    bus_type = SafeStr $m.bus_type
    drive_letter = $drive
    access_paths = @($m.access_paths)
    file_system = SafeStr $m.file_system
    volume_label = SafeStr $m.volume_label
    mount_state = $mountState
    disk_health_status = SafeStr $m.disk_health_status
    disk_operational_status = SafeStr $m.disk_operational_status
    health_summary = $(if($null -ne $h){ SafeStr $h.health_summary } else { "UNKNOWN" })
    read_probe_state = $(if($null -ne $rr){ SafeStr $rr.probe_state } else { "NO_READ_ROW" })
    read_ok = $(if($null -ne $rr){ SafeBool $rr.read_ok } else { $false })
    recommended_actions = @($actions)
    reasons = @($reasons)
  })
}

$actionCounts = [ordered]@{}
foreach($r in @($rows)){
  foreach($a in @($r.recommended_actions)){
    if(-not $actionCounts.Contains($a)){ $actionCounts[$a] = 0 }
    $actionCounts[$a] = [int]$actionCounts[$a] + 1
  }
}

$receipt = [ordered]@{
  schema = "ld.device.backup_readiness.receipt.v1"
  event_type = "ld.device.backup_readiness.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "operator_backup_readiness"
  destructive = $false
  write_test = $false
  admin_present = $admin
  inventory_disk_count = [int]$inventory.disk_count
  mount_row_count = [int]$mount.row_count
  health_disk_count = [int]$health.disk_count
  read_volume_count = [int]$read.volume_count
  read_ok_count = [int]$read.read_ok_count
  row_count = [int]$rows.Count
  action_counts = $actionCounts
  rows = @($rows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_backup_readiness"
EnsureDir $outDir
$outPath = Join-Path $outDir ("backup_readiness_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_BACKUP_READINESS_PATH: " + $outPath)
Write-Output ("DEVICE_BACKUP_READINESS_ROWS: " + [string]$rows.Count)
Write-Output $json
Write-Output "LD_DEVICE_BACKUP_READINESS_OK"
