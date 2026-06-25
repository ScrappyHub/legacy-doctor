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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$contractScript = Join-Path $RepoRoot "scripts\storage\ld_backup_run_contract_v1.ps1"
if(-not (Test-Path -LiteralPath $contractScript -PathType Leaf)){
  Die "BACKUP_RUN_CONTRACT_SCRIPT_MISSING" $contractScript
}

$args = @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",$contractScript,
  "-RepoRoot",$RepoRoot,
  "-MaxFiles",[string]$MaxFiles,
  "-MaxBytes",[string]$MaxBytes,
  "-MaxFilesPerSource",[string]$MaxFilesPerSource,
  "-MaxDirsPerSource",[string]$MaxDirsPerSource,
  "-MaxSamplesPerSource",[string]$MaxSamplesPerSource
)

if(-not [string]::IsNullOrWhiteSpace($DestinationPath)){
  $args += @("-DestinationPath",$DestinationPath)
}

if($AllowSystemDisk.IsPresent){
  $args += "-AllowSystemDisk"
}

if($Execute.IsPresent){
  $args += "-Execute"
}

$out = & powershell.exe @args
if($LASTEXITCODE -ne 0){
  Die "BACKUP_RUN_CONTRACT_EXIT_NONZERO" ([string]$LASTEXITCODE)
}

$contract = First-JsonObjectFromOutput -Output $out -Schema "ld.device.backup_run_contract.receipt.v1"

$guardActions = @()
$reasons = @()

if(-not (SafeBool $contract.execution_allowed_now)){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_BLOCKED_CONTRACT_NOT_ALLOWED"
  $reasons = Add-Unique $reasons "backup run contract did not allow execution"
}

if(-not (SafeBool $contract.explicit_destination_present)){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_BLOCKED_DESTINATION_REQUIRED"
  $reasons = Add-Unique $reasons "explicit destination path is required"
}

if(SafeBool $contract.repo_root_destination_blocked){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_BLOCKED_REPO_ROOT_DESTINATION"
  $reasons = Add-Unique $reasons "repo root destination is blocked"
}

if(-not (SafeBool $contract.preflight_ready)){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_BLOCKED_PREFLIGHT_NOT_READY"
  $reasons = Add-Unique $reasons "preflight is not ready"
}

if((SafeInt $contract.max_files) -le 0){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_BLOCKED_MAX_FILES_REQUIRED"
  $reasons = Add-Unique $reasons "MaxFiles cap is required"
}

if([Int64]$contract.max_bytes -le 0){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_BLOCKED_MAX_BYTES_REQUIRED"
  $reasons = Add-Unique $reasons "MaxBytes cap is required"
}

if(-not (SafeBool $contract.execute_requested)){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_BLOCKED_EXECUTE_REQUIRED"
  $reasons = Add-Unique $reasons "Execute flag is required"
}

if((SafeInt $contract.preflight_manifest_warning_row_count) -gt 0 -and -not (SafeBool $contract.allow_system_disk)){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_BLOCKED_SYSTEM_DISK_CONFIRMATION_REQUIRED"
  $reasons = Add-Unique $reasons "system disk rows require explicit confirmation"
}

if(@($guardActions).Count -eq 0){
  $guardActions = Add-Unique $guardActions "EXECUTOR_GUARD_WOULD_ALLOW_FUTURE_COPY_EXECUTOR"
  $reasons = Add-Unique $reasons "all executor guard gates passed, but this lane still performs no copy"
}

$wouldInvokeFutureExecutor = (@($guardActions).Count -eq 1 -and $guardActions[0] -eq "EXECUTOR_GUARD_WOULD_ALLOW_FUTURE_COPY_EXECUTOR")

$actionCounts = [ordered]@{}
foreach($a in @($guardActions)){
  if(-not $actionCounts.Contains($a)){ $actionCounts[$a] = 0 }
  $actionCounts[$a] = [int]$actionCounts[$a] + 1
}

$receipt = [ordered]@{
  schema = "ld.device.blocked_copy_executor_guard.receipt.v1"
  event_type = "ld.device.blocked_copy_executor_guard.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "blocked_copy_executor_guard"
  destructive = $false
  write_test = $false
  performs_copy = $false
  writes_destination = $false
  hashes_file_contents = $false
  would_invoke_future_executor = [bool]$wouldInvokeFutureExecutor
  contract_schema = "ld.device.backup_run_contract.receipt.v1"
  contract_execution_allowed_now = [bool]$contract.execution_allowed_now
  contract_would_allow_future_bounded_copy = [bool]$contract.would_allow_future_bounded_copy
  contract_destination_path = SafeStr $contract.destination_path
  contract_repo_root_destination_blocked = [bool]$contract.repo_root_destination_blocked
  contract_preflight_ready = [bool]$contract.preflight_ready
  contract_execute_requested = [bool]$contract.execute_requested
  contract_max_files = [int]$contract.max_files
  contract_max_bytes = [Int64]$contract.max_bytes
  contract_allow_system_disk = [bool]$contract.allow_system_disk
  contract_actions = @($contract.contract_actions)
  guard_actions = @($guardActions)
  action_counts = $actionCounts
  reasons = @($reasons)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_blocked_copy_executor_guard"
EnsureDir $outDir
$outPath = Join-Path $outDir ("blocked_copy_executor_guard_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_BLOCKED_COPY_EXECUTOR_GUARD_PATH: " + $outPath)
Write-Output ("DEVICE_BLOCKED_COPY_EXECUTOR_GUARD_WOULD_INVOKE: " + [string]$wouldInvokeFutureExecutor)
Write-Output $json
Write-Output "LD_DEVICE_BLOCKED_COPY_EXECUTOR_GUARD_OK"
