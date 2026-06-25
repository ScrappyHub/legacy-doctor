param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DestinationPath = "",
  [int]$MaxFiles = 0,
  [Int64]$MaxBytes = 0,
  [switch]$AllowSystemDisk,
  [switch]$Execute,
  [int]$MaxFilesPerSource = 20,
  [int]$MaxDirsPerSource = 10,
  [int]$MaxSamplesPerSource = 5
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

function SafeInt([object]$Value){
  if($null -eq $Value){ return 0 }
  return [int]$Value
}

function Add-Unique([object[]]$Items,[string]$Value){
  $out = @($Items)
  if(-not ($out -contains $Value)){ $out += $Value }
  return @($out)
}

function SamePath([string]$A,[string]$B){
  if([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)){ return $false }

  try {
    $af = [IO.Path]::GetFullPath($A).TrimEnd("\")
    $bf = [IO.Path]::GetFullPath($B).TrimEnd("\")
    return $af.Equals($bf,[StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$explicitDestination = (-not [string]::IsNullOrWhiteSpace($DestinationPath))
$destinationForPreflight = $DestinationPath
if(-not $explicitDestination){
  $destinationForPreflight = $RepoRoot
}

$preflightScript = Join-Path $RepoRoot "scripts\storage\ld_backup_execution_preflight_v1.ps1"
if(-not (Test-Path -LiteralPath $preflightScript -PathType Leaf)){
  Die "BACKUP_EXECUTION_PREFLIGHT_SCRIPT_MISSING" $preflightScript
}

$preflightOut = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflightScript -RepoRoot $RepoRoot -DestinationPath $destinationForPreflight -MaxFilesPerSource $MaxFilesPerSource -MaxDirsPerSource $MaxDirsPerSource -MaxSamplesPerSource $MaxSamplesPerSource
if($LASTEXITCODE -ne 0){
  Die "BACKUP_EXECUTION_PREFLIGHT_EXIT_NONZERO" ([string]$LASTEXITCODE)
}

$preflight = First-JsonObjectFromOutput -Output $preflightOut -Schema "ld.device.backup_execution_preflight.receipt.v1"

$contractActions = @()
$reasons = @()

if(-not $explicitDestination){
  $contractActions = Add-Unique $contractActions "CONTRACT_BLOCKED_DESTINATION_REQUIRED"
  $reasons = Add-Unique $reasons "destination path must be explicit"
}

if(SamePath -A $RepoRoot -B $destinationForPreflight){
  $contractActions = Add-Unique $contractActions "CONTRACT_BLOCKED_REPO_ROOT_DESTINATION"
  $reasons = Add-Unique $reasons "repo root cannot be used as backup destination"
}

if(-not (SafeBool $preflight.preflight_ready)){
  $contractActions = Add-Unique $contractActions "CONTRACT_BLOCKED_PREFLIGHT_NOT_READY"
  $reasons = Add-Unique $reasons "backup execution preflight is not ready"
}

if((SafeInt $preflight.manifest_warning_row_count) -gt 0 -and -not $AllowSystemDisk.IsPresent){
  $contractActions = Add-Unique $contractActions "CONTRACT_BLOCKED_SYSTEM_DISK_CONFIRMATION_REQUIRED"
  $reasons = Add-Unique $reasons "system disk rows require explicit confirmation"
}

if($MaxFiles -le 0){
  $contractActions = Add-Unique $contractActions "CONTRACT_BLOCKED_MAX_FILES_REQUIRED"
  $reasons = Add-Unique $reasons "bounded copy requires MaxFiles greater than zero"
}

if($MaxBytes -le 0){
  $contractActions = Add-Unique $contractActions "CONTRACT_BLOCKED_MAX_BYTES_REQUIRED"
  $reasons = Add-Unique $reasons "bounded copy requires MaxBytes greater than zero"
}

if(-not $Execute.IsPresent){
  $contractActions = Add-Unique $contractActions "CONTRACT_DRY_RUN_ONLY"
  $reasons = Add-Unique $reasons "execution flag not present; contract remains dry-run only"
}

$wouldAllowFutureBoundedCopy = (
  $explicitDestination -and
  (-not (SamePath -A $RepoRoot -B $destinationForPreflight)) -and
  (SafeBool $preflight.preflight_ready) -and
  (($MaxFiles -gt 0) -and ($MaxBytes -gt 0)) -and
  (((SafeInt $preflight.manifest_warning_row_count) -eq 0) -or $AllowSystemDisk.IsPresent)
)

$executionAllowedNow = ($wouldAllowFutureBoundedCopy -and $Execute.IsPresent)

if($wouldAllowFutureBoundedCopy -and -not $Execute.IsPresent){
  $contractActions = Add-Unique $contractActions "CONTRACT_READY_REQUIRES_EXECUTE_FLAG"
  $reasons = Add-Unique $reasons "contract would allow future bounded copy only when explicit Execute is present"
}

if($executionAllowedNow){
  $contractActions = Add-Unique $contractActions "CONTRACT_READY_FOR_FUTURE_BOUNDED_COPY_EXECUTOR"
  $reasons = Add-Unique $reasons "all contract gates passed, but this lane still performs no copy"
}

$actionCounts = [ordered]@{}
foreach($a in @($contractActions)){
  if(-not $actionCounts.Contains($a)){ $actionCounts[$a] = 0 }
  $actionCounts[$a] = [int]$actionCounts[$a] + 1
}

$receipt = [ordered]@{
  schema = "ld.device.backup_run_contract.receipt.v1"
  event_type = "ld.device.backup_run_contract.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "backup_run_contract"
  destructive = $false
  write_test = $false
  performs_copy = $false
  writes_destination = $false
  hashes_file_contents = $false
  execution_allowed_now = [bool]$executionAllowedNow
  would_allow_future_bounded_copy = [bool]$wouldAllowFutureBoundedCopy
  explicit_destination_required = $true
  explicit_destination_present = [bool]$explicitDestination
  destination_path = SafeStr $destinationForPreflight
  repo_root_destination_blocked = [bool](SamePath -A $RepoRoot -B $destinationForPreflight)
  max_files = [int]$MaxFiles
  max_bytes = [Int64]$MaxBytes
  max_files_required = $true
  max_bytes_required = $true
  allow_system_disk = [bool]$AllowSystemDisk.IsPresent
  execute_requested = [bool]$Execute.IsPresent
  dry_run_default = [bool](-not $Execute.IsPresent)
  preflight_schema = "ld.device.backup_execution_preflight.receipt.v1"
  preflight_ready = [bool]$preflight.preflight_ready
  preflight_actions = @($preflight.preflight_actions)
  preflight_write_probe_ok = [bool]$preflight.write_probe_ok
  preflight_manifest_invalid_row_count = [int]$preflight.manifest_invalid_row_count
  preflight_manifest_warning_row_count = [int]$preflight.manifest_warning_row_count
  contract_actions = @($contractActions)
  action_counts = $actionCounts
  reasons = @($reasons)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_backup_run_contract"
EnsureDir $outDir
$outPath = Join-Path $outDir ("backup_run_contract_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_BACKUP_RUN_CONTRACT_PATH: " + $outPath)
Write-Output ("DEVICE_BACKUP_RUN_CONTRACT_EXECUTION_ALLOWED: " + [string]$executionAllowedNow)
Write-Output $json
Write-Output "LD_DEVICE_BACKUP_RUN_CONTRACT_OK"
