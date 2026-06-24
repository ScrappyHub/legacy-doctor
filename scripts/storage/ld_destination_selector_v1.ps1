param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DestinationPath = ""
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

function First-JsonObjectFromOutput([object[]]$Output,[string]$Schema){
  foreach($line in @($Output)){
    $s = [string]$line
    if($s.StartsWith("{") -and $s.Contains(('"schema":"' + $Schema + '"'))){
      return ($s | ConvertFrom-Json)
    }
  }

  Die "JSON_SCHEMA_OUTPUT_MISSING" $Schema
}

function NormalizeDriveLetter([object]$Value){
  if($null -eq $Value){ return "" }
  $s = [string]$Value
  $s = $s.Replace([string][char]0,"").Trim()
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  return $s.ToUpperInvariant()
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

function Add-Unique([object[]]$Items,[string]$Value){
  $out = @($Items)
  if(-not ($out -contains $Value)){ $out += $Value }
  return @($out)
}

function Get-PathDrive([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return "" }

  try {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if([string]::IsNullOrWhiteSpace($root)){ return "" }
    if($root.Length -ge 1 -and $root.Substring(1,1) -eq ":"){
      return $root.Substring(0,1).ToUpperInvariant()
    }
  } catch {
    return ""
  }

  return ""
}

function Get-VolumeByDrive([string]$DriveLetter){
  $dl = NormalizeDriveLetter $DriveLetter
  if([string]::IsNullOrWhiteSpace($dl)){ return $null }

  try {
    foreach($v in @(Get-Volume -ErrorAction Stop)){
      if((NormalizeDriveLetter $v.DriveLetter) -eq $dl){
        return $v
      }
    }
  } catch {
    return $null
  }

  return $null
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if([string]::IsNullOrWhiteSpace($DestinationPath)){
  $DestinationPath = $RepoRoot
}

$DestinationPathInput = $DestinationPath
$DestinationExists = Test-Path -LiteralPath $DestinationPath -PathType Container

$DestinationResolved = ""
if($DestinationExists){
  $DestinationResolved = (Resolve-Path -LiteralPath $DestinationPath).Path
} else {
  try {
    $DestinationResolved = [IO.Path]::GetFullPath($DestinationPath)
  } catch {
    $DestinationResolved = $DestinationPath
  }
}

$DestDrive = Get-PathDrive $DestinationResolved
$DestVol = Get-VolumeByDrive $DestDrive

$DestSize = [UInt64]0
$DestFree = [UInt64]0
$DestFs = ""
$DestLabel = ""

if($null -ne $DestVol){
  $DestSize = SafeU64 $DestVol.Size
  $DestFree = SafeU64 $DestVol.SizeRemaining
  $DestFs = SafeStr $DestVol.FileSystem
  $DestLabel = SafeStr $DestVol.FileSystemLabel
}

$PlanScript = Join-Path $RepoRoot "scripts\storage\ld_file_backup_plan_v1.ps1"
if(-not (Test-Path -LiteralPath $PlanScript -PathType Leaf)){
  Die "FILE_BACKUP_PLAN_SCRIPT_MISSING" $PlanScript
}

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PlanScript -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  Die "FILE_BACKUP_PLAN_EXIT_NONZERO" ([string]$LASTEXITCODE)
}

$plan = First-JsonObjectFromOutput -Output $out -Schema "ld.device.file_backup_plan.receipt.v1"

$rows = @()

foreach($p in @($plan.plan_rows)){
  $actions = @()
  $reasons = @()

  $sourceDrive = Get-PathDrive (SafeStr $p.source_drive)
  $requiredBytes = SafeU64 $p.required_bytes_estimate

  if(-not $DestinationExists){
    $actions = Add-Unique $actions "DESTINATION_MISSING"
    $reasons += "destination path does not exist"
  }

  if([string]::IsNullOrWhiteSpace($DestDrive)){
    $actions = Add-Unique $actions "DESTINATION_DRIVE_UNKNOWN"
    $reasons += "destination drive could not be determined"
  }

  if(-not [string]::IsNullOrWhiteSpace($sourceDrive) -and $sourceDrive -eq $DestDrive){
    $actions = Add-Unique $actions "SOURCE_EQUALS_DESTINATION"
    $reasons += "destination drive matches source drive"
  }

  if(SafeBool $p.system_disk_warning -and $sourceDrive -eq $DestDrive){
    $actions = Add-Unique $actions "DESTINATION_IS_SYSTEM_SOURCE"
    $reasons += "destination is on the same drive as system source"
  }

  if($DestFree -lt $requiredBytes){
    $actions = Add-Unique $actions "INSUFFICIENT_SPACE"
    $reasons += ("free bytes " + [string]$DestFree + " less than required estimate " + [string]$requiredBytes)
  }

  if($DestinationExists -and -not [string]::IsNullOrWhiteSpace($DestDrive) -and $sourceDrive -ne $DestDrive -and $DestFree -ge $requiredBytes){
    $actions = Add-Unique $actions "READY_DESTINATION"
    $reasons += "destination exists, is not the source drive, and has enough estimated free space"
  }

  if(@($actions).Count -eq 0){
    $actions = Add-Unique $actions "DESTINATION_REVIEW"
    $reasons += "destination requires operator review"
  }

  $rows += ,([ordered]@{
    source_drive = SafeStr $p.source_drive
    source_volume_label = SafeStr $p.source_volume_label
    source_disk_number = [int]$p.source_disk_number
    source_partition_number = [int]$p.source_partition_number
    source_bus_type = SafeStr $p.source_bus_type
    system_disk_warning = SafeBool $p.system_disk_warning
    required_bytes_estimate = $requiredBytes
    destination_path_input = $DestinationPathInput
    destination_path_resolved = $DestinationResolved
    destination_drive = $DestDrive
    destination_exists = [bool]$DestinationExists
    destination_file_system = $DestFs
    destination_label = $DestLabel
    destination_size_bytes = $DestSize
    destination_free_bytes = $DestFree
    selector_actions = @($actions)
    reasons = @($reasons)
  })
}

$selectorCounts = [ordered]@{}
foreach($r in @($rows)){
  foreach($a in @($r.selector_actions)){
    if(-not $selectorCounts.Contains($a)){ $selectorCounts[$a] = 0 }
    $selectorCounts[$a] = [int]$selectorCounts[$a] + 1
  }
}

$receipt = [ordered]@{
  schema = "ld.device.destination_selector.receipt.v1"
  event_type = "ld.device.destination_selector.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "destination_selector_dry_run"
  destructive = $false
  write_test = $false
  performs_copy = $false
  destination_path_input = $DestinationPathInput
  destination_path_resolved = $DestinationResolved
  destination_exists = [bool]$DestinationExists
  destination_drive = $DestDrive
  destination_free_bytes = $DestFree
  plan_row_count = [int]$plan.planned_count
  row_count = [int]$rows.Count
  selector_counts = $selectorCounts
  rows = @($rows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_destination_selector"
EnsureDir $outDir
$outPath = Join-Path $outDir ("destination_selector_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_DESTINATION_SELECTOR_PATH: " + $outPath)
Write-Output ("DEVICE_DESTINATION_SELECTOR_ROWS: " + [string]$rows.Count)
Write-Output $json
Write-Output "LD_DEVICE_DESTINATION_SELECTOR_OK"
