param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_backup_execution_preflight_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -DestinationPath $RepoRoot -MaxFilesPerSource 20 -MaxDirsPerSource 10 -MaxSamplesPerSource 5
if($LASTEXITCODE -ne 0){ Die "BACKUP_EXECUTION_PREFLIGHT_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_BACKUP_EXECUTION_PREFLIGHT_OK"){
  Die "BACKUP_EXECUTION_PREFLIGHT_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"performs_copy":false'){
  Die "PERFORMS_COPY_FALSE_MISSING" ""
}

if($text -notmatch '"writes_destination":false'){
  Die "WRITES_DESTINATION_FALSE_MISSING" ""
}

if($text -notmatch '"write_probe_ok":true'){
  Die "WRITE_PROBE_OK_MISSING" ""
}

if($text -notmatch '"manifest_invalid_row_count":0'){
  Die "MANIFEST_INVALID_ROWS_PRESENT" ""
}

if($text -notmatch 'READY_FOR_BOUNDED_COPY|BLOCKED_INSUFFICIENT_SPACE|BLOCKED_SOURCE_EQUALS_DESTINATION|BLOCKED_DESTINATION_WRITE_PROBE_FAILED|BLOCKED_MANIFEST_INVALID'){
  Die "PREFLIGHT_DECISION_MISSING" ""
}

Write-Output $text
Write-Output "PASS: backup execution preflight emitted"
Write-Output "PASS: joined selector, write probe, and manifest verifier"
Write-Output "PASS: no copy performed"
Write-Output "SELFTEST_LD_STORAGE03_BACKUP_EXECUTION_PREFLIGHT_OK"
