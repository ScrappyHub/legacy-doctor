param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DestinationPath = "",
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

function Run-ReceiptScript([string]$ScriptPath,[string]$Schema,[string[]]$ExtraArgs){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    Die "SCRIPT_MISSING" $ScriptPath
  }

  $args = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$ScriptPath,
    "-RepoRoot",$RepoRoot
  )

  foreach($a in @($ExtraArgs)){ $args += $a }

  $out = & powershell.exe @args
  if($LASTEXITCODE -ne 0){
    Die "SCRIPT_EXIT_NONZERO" ($ScriptPath + ":" + [string]$LASTEXITCODE)
  }

  return (First-JsonObjectFromOutput -Output $out -Schema $Schema)
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

function RowHasAction([object]$Row,[string]$Action){
  foreach($a in @($Row.selector_actions)){
    if(([string]$a) -eq $Action){ return $true }
  }
  return $false
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if([string]::IsNullOrWhiteSpace($DestinationPath)){
  $DestinationPath = $RepoRoot
}

$selectorScript = Join-Path $RepoRoot "scripts\storage\ld_destination_selector_v1.ps1"
$writeProbeScript = Join-Path $RepoRoot "scripts\storage\ld_destination_write_probe_v1.ps1"
$manifestVerifyScript = Join-Path $RepoRoot "scripts\storage\ld_copy_manifest_verify_v1.ps1"

$selector = Run-ReceiptScript `
  -ScriptPath $selectorScript `
  -Schema "ld.device.destination_selector.receipt.v1" `
  -ExtraArgs @("-DestinationPath",$DestinationPath)

$writeProbe = Run-ReceiptScript `
  -ScriptPath $writeProbeScript `
  -Schema "ld.device.destination_write_probe.receipt.v1" `
  -ExtraArgs @("-DestinationPath",$DestinationPath)

$manifestVerify = Run-ReceiptScript `
  -ScriptPath $manifestVerifyScript `
  -Schema "ld.device.copy_manifest_verify.receipt.v1" `
  -ExtraArgs @(
    "-DestinationRoot",$DestinationPath,
    "-MaxFilesPerSource",[string]$MaxFilesPerSource,
    "-MaxDirsPerSource",[string]$MaxDirsPerSource,
    "-MaxSamplesPerSource",[string]$MaxSamplesPerSource
  )

$actions = @()
$reasons = @()

foreach($r in @($selector.rows)){
  if(RowHasAction -Row $r -Action "INSUFFICIENT_SPACE"){
    $actions = Add-Unique $actions "BLOCKED_INSUFFICIENT_SPACE"
    $reasons = Add-Unique $reasons "destination selector reported insufficient space"
  }

  if(RowHasAction -Row $r -Action "SOURCE_EQUALS_DESTINATION"){
    $actions = Add-Unique $actions "BLOCKED_SOURCE_EQUALS_DESTINATION"
    $reasons = Add-Unique $reasons "destination selector reported source equals destination"
  }

  if(RowHasAction -Row $r -Action "DESTINATION_MISSING"){
    $actions = Add-Unique $actions "BLOCKED_DESTINATION_MISSING"
    $reasons = Add-Unique $reasons "destination selector reported missing destination"
  }

  if(RowHasAction -Row $r -Action "DESTINATION_DRIVE_UNKNOWN"){
    $actions = Add-Unique $actions "BLOCKED_DESTINATION_DRIVE_UNKNOWN"
    $reasons = Add-Unique $reasons "destination drive could not be resolved"
  }

  if(SafeBool $r.system_disk_warning){
    $actions = Add-Unique $actions "SYSTEM_DISK_COPY_REQUIRES_EXPLICIT_CONFIRMATION"
    $reasons = Add-Unique $reasons "manifest contains system disk rows"
  }
}

if(-not (SafeBool $writeProbe.write_probe_ok)){
  $actions = Add-Unique $actions "BLOCKED_DESTINATION_WRITE_PROBE_FAILED"
  $reasons = Add-Unique $reasons "destination write probe failed"
}

if((SafeInt $manifestVerify.invalid_row_count) -gt 0 -or -not (SafeBool $manifestVerify.ok)){
  $actions = Add-Unique $actions "BLOCKED_MANIFEST_INVALID"
  $reasons = Add-Unique $reasons "copy manifest verifier reported invalid rows"
}

if(@($actions).Count -eq 0){
  $actions = Add-Unique $actions "READY_FOR_BOUNDED_COPY"
  $reasons = Add-Unique $reasons "selector, write probe, and manifest verifier are all acceptable"
}

$ready = (@($actions).Count -eq 1 -and $actions[0] -eq "READY_FOR_BOUNDED_COPY")

$actionCounts = [ordered]@{}
foreach($a in @($actions)){
  if(-not $actionCounts.Contains($a)){ $actionCounts[$a] = 0 }
  $actionCounts[$a] = [int]$actionCounts[$a] + 1
}

$receipt = [ordered]@{
  schema = "ld.device.backup_execution_preflight.receipt.v1"
  event_type = "ld.device.backup_execution_preflight.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "backup_execution_preflight"
  destructive = $false
  write_test = $true
  performs_copy = $false
  writes_destination = $false
  preflight_ready = [bool]$ready
  destination_path = $DestinationPath
  selector_schema = "ld.device.destination_selector.receipt.v1"
  selector_row_count = [int]$selector.row_count
  selector_counts = $selector.selector_counts
  write_probe_schema = "ld.device.destination_write_probe.receipt.v1"
  write_probe_ok = [bool]$writeProbe.write_probe_ok
  write_probe_temp_deleted = [bool]$writeProbe.temp_deleted
  manifest_verify_schema = "ld.device.copy_manifest_verify.receipt.v1"
  manifest_invalid_row_count = [int]$manifestVerify.invalid_row_count
  manifest_valid_row_count = [int]$manifestVerify.valid_row_count
  manifest_warning_row_count = [int]$manifestVerify.warning_row_count
  manifest_skipped_row_count = [int]$manifestVerify.skipped_row_count
  preflight_actions = @($actions)
  action_counts = $actionCounts
  reasons = @($reasons)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_backup_execution_preflight"
EnsureDir $outDir
$outPath = Join-Path $outDir ("backup_execution_preflight_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_BACKUP_EXECUTION_PREFLIGHT_PATH: " + $outPath)
Write-Output ("DEVICE_BACKUP_EXECUTION_PREFLIGHT_READY: " + [string]$ready)
Write-Output $json
Write-Output "LD_DEVICE_BACKUP_EXECUTION_PREFLIGHT_OK"
