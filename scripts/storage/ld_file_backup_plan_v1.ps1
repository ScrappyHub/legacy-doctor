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

function First-JsonObjectFromOutput([object[]]$Output,[string]$Schema){
  foreach($line in @($Output)){
    $s = [string]$line
    if($s.StartsWith("{") -and $s.Contains(('"schema":"' + $Schema + '"'))){
      return ($s | ConvertFrom-Json)
    }
  }

  Die "JSON_SCHEMA_OUTPUT_MISSING" $Schema
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

function NormalizeDriveLetter([object]$Value){
  if($null -eq $Value){ return "" }
  $s = [string]$Value
  $s = $s.Replace([string][char]0,"").Trim()
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  return $s
}

function HasAction([object]$Row,[string]$Action){
  foreach($a in @($Row.recommended_actions)){
    if(([string]$a) -eq $Action){ return $true }
  }

  return $false
}

function Get-VolumeByDrive([string]$DriveLetter){
  $dl = NormalizeDriveLetter $DriveLetter
  if([string]::IsNullOrWhiteSpace($dl)){ return $null }

  try {
    $vols = @(Get-Volume -ErrorAction Stop)
    foreach($v in @($vols)){
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
$ReadinessScript = Join-Path $RepoRoot "scripts\storage\ld_backup_readiness_v1.ps1"

if(-not (Test-Path -LiteralPath $ReadinessScript -PathType Leaf)){
  Die "BACKUP_READINESS_SCRIPT_MISSING" $ReadinessScript
}

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ReadinessScript -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  Die "BACKUP_READINESS_EXIT_NONZERO" ([string]$LASTEXITCODE)
}

$readiness = First-JsonObjectFromOutput -Output $out -Schema "ld.device.backup_readiness.receipt.v1"

$planRows = @()
$skippedRows = @()

foreach($r in @($readiness.rows)){
  $drive = NormalizeDriveLetter $r.drive_letter
  $isReadyFile = HasAction -Row $r -Action "READY_FILE_BACKUP"
  $isSystemSkip = HasAction -Row $r -Action "SKIP_SYSTEM_DISK_BY_DEFAULT"

  if($isReadyFile -and -not [string]::IsNullOrWhiteSpace($drive)){
    $vol = Get-VolumeByDrive -DriveLetter $drive
    $sizeBytes = [UInt64]0
    $remainingBytes = [UInt64]0
    $usedEstimateBytes = [UInt64]0

    if($null -ne $vol){
      $sizeBytes = SafeU64 $vol.Size
      $remainingBytes = SafeU64 $vol.SizeRemaining
      if($sizeBytes -ge $remainingBytes){
        $usedEstimateBytes = [UInt64]($sizeBytes - $remainingBytes)
      }
    }

    $planRows += ,([ordered]@{
      plan_state = "PLANNED_DRY_RUN_ONLY"
      backup_mode = "file_backup"
      source_drive = ($drive + ":\")
      source_volume_label = SafeStr $r.volume_label
      source_file_system = SafeStr $r.file_system
      source_disk_number = [int]$r.disk_number
      source_partition_number = [int]$r.partition_number
      source_bus_type = SafeStr $r.bus_type
      system_disk_warning = [bool]$isSystemSkip
      required_bytes_estimate = $usedEstimateBytes
      estimate_basis = "volume_size_minus_free_space"
      include_rules = @("source_drive_recursive")
      exclude_rules = @(
        "System Volume Information",
        '$Recycle.Bin',
        "pagefile.sys",
        "hiberfil.sys",
        "swapfile.sys"
      )
      destination_required = $true
      destination_path = ""
      destructive = $false
      writes_files = $false
      reasons = @($r.reasons)
    })
  } else {
    $skippedRows += ,([ordered]@{
      disk_number = [int]$r.disk_number
      partition_number = $r.partition_number
      drive_letter = $drive
      mount_state = SafeStr $r.mount_state
      skip_reason = $(if($isReadyFile){ "NO_DRIVE_LETTER" } else { "NOT_READY_FILE_BACKUP" })
      recommended_actions = @($r.recommended_actions)
    })
  }
}

$receipt = [ordered]@{
  schema = "ld.device.file_backup_plan.receipt.v1"
  event_type = "ld.device.file_backup_plan.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "file_backup_plan_dry_run"
  destructive = $false
  write_test = $false
  performs_copy = $false
  requires_destination = $true
  readiness_row_count = [int]$readiness.row_count
  planned_count = [int]$planRows.Count
  skipped_count = [int]$skippedRows.Count
  plan_rows = @($planRows)
  skipped_rows = @($skippedRows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_file_backup_plan"
EnsureDir $outDir
$outPath = Join-Path $outDir ("file_backup_plan_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_FILE_BACKUP_PLAN_PATH: " + $outPath)
Write-Output ("DEVICE_FILE_BACKUP_PLAN_COUNT: " + [string]$planRows.Count)
Write-Output $json
Write-Output "LD_DEVICE_FILE_BACKUP_PLAN_OK"
