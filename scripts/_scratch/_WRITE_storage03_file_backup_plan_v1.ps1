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
  if($null -eq $Text){ Die "TEXT_MISSING" $Path }

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
    Die "PARSE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ":" + $e.Message)
  }

  Write-Host ("PARSE_OK: " + $Path) -ForegroundColor Green
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PlanScript = @'
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
'@

$Schema = '{"$schema":"https://json-schema.org/draft/2020-12/schema","title":"Legacy Doctor Device File Backup Plan Receipt v1","type":"object","required":["schema","event_type","ok","repo_root","mode","destructive","write_test","performs_copy","requires_destination","readiness_row_count","planned_count","skipped_count","plan_rows","skipped_rows","created_utc"],"properties":{"schema":{"const":"ld.device.file_backup_plan.receipt.v1"},"event_type":{"const":"ld.device.file_backup_plan.receipt.v1"},"ok":{"type":"boolean"},"repo_root":{"type":"string"},"mode":{"const":"file_backup_plan_dry_run"},"destructive":{"const":false},"write_test":{"const":false},"performs_copy":{"const":false},"requires_destination":{"const":true},"readiness_row_count":{"type":"integer"},"planned_count":{"type":"integer"},"skipped_count":{"type":"integer"},"plan_rows":{"type":"array"},"skipped_rows":{"type":"array"},"created_utc":{"type":"string"}}}'

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
$Probe = Join-Path $RepoRoot "scripts\storage\ld_file_backup_plan_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "FILE_BACKUP_PLAN_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_FILE_BACKUP_PLAN_OK"){
  Die "FILE_BACKUP_PLAN_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"performs_copy":false'){
  Die "PERFORMS_COPY_FALSE_MISSING" ""
}

if($text -notmatch '"requires_destination":true'){
  Die "REQUIRES_DESTINATION_TRUE_MISSING" ""
}

if($text -notmatch "PLANNED_DRY_RUN_ONLY"){
  Die "DRY_RUN_PLAN_MISSING" ""
}

Write-Output $text
Write-Output "PASS: file backup plan emitted"
Write-Output "PASS: dry-run only, no copy"
Write-Output "SELFTEST_LD_STORAGE03_FILE_BACKUP_PLAN_OK"
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
  (Join-Path $RepoRoot "scripts\storage\ld_file_backup_plan_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_file_backup_plan_v1.ps1")
)

foreach($f in @($files)){
  Parse-GateFile $f
}

$schema = Join-Path $RepoRoot "schemas\ld.device.file_backup_plan.receipt.v1.json"
if(-not (Test-Path -LiteralPath $schema -PathType Leaf)){
  Die "SCHEMA_MISSING" $schema
}

Write-Output ("SCHEMA_OK: " + $schema)

$selftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_file_backup_plan_v1.ps1"
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $selftest -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "SELFTEST_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$outText = ($out -join "`n")
Write-Output $outText

if($outText -notmatch "SELFTEST_LD_STORAGE03_FILE_BACKUP_PLAN_OK"){
  Die "SELFTEST_TOKEN_MISSING" ""
}

Write-Output "LEGACY_DOCTOR_STORAGE03_FILE_BACKUP_PLAN_GREEN"
'@

$Docs = @'
# LD-STORAGE-03F File Backup Plan v1

Status: first checkpoint.

This lane is dry-run only.

It consumes backup readiness output and emits a file-backup plan for volumes that are marked READY_FILE_BACKUP.

It does not:
- copy files
- write destination data
- image disks
- format disks
- mount disks
- modify source volumes

It emits:
- source volume
- estimated required bytes
- include rules
- exclude rules
- destination requirement
- system disk warning
- skipped rows

Next checkpoints:
- destination selector v1
- file backup dry-run enumerator v1
- copy executor with receipts later
'@

Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\storage\ld_file_backup_plan_v1.ps1") $PlanScript
Write-Utf8NoBomLf (Join-Path $RepoRoot "schemas\ld.device.file_backup_plan.receipt.v1.json") $Schema
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_file_backup_plan_v1.ps1") $Selftest
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_storage03_file_backup_plan_v1.ps1") $Runner
Write-Utf8NoBomLf (Join-Path $RepoRoot "docs\WBS\LD_STORAGE_03F_FILE_BACKUP_PLAN_v1.md") $Docs

$toParse = @(
  (Join-Path $RepoRoot "scripts\storage\ld_file_backup_plan_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_file_backup_plan_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_storage03_file_backup_plan_v1.ps1")
)

foreach($p in @($toParse)){
  Parse-GateFile $p
}

Write-Host "LD_STORAGE03_FILE_BACKUP_PLAN_FILES_READY" -ForegroundColor Green