param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_backup_run_contract_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -DestinationPath $RepoRoot -MaxFiles 20 -MaxBytes 1048576 -MaxFilesPerSource 20 -MaxDirsPerSource 10 -MaxSamplesPerSource 5
if($LASTEXITCODE -ne 0){ Die "BACKUP_RUN_CONTRACT_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_BACKUP_RUN_CONTRACT_OK"){
  Die "BACKUP_RUN_CONTRACT_TOKEN_MISSING" ""
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

if($text -notmatch '"explicit_destination_present":true'){
  Die "EXPLICIT_DESTINATION_PRESENT_MISSING" ""
}

if($text -notmatch '"repo_root_destination_blocked":true'){
  Die "REPO_ROOT_DESTINATION_BLOCK_MISSING" ""
}

if($text -notmatch "CONTRACT_BLOCKED_REPO_ROOT_DESTINATION"){
  Die "CONTRACT_REPO_ROOT_BLOCK_ACTION_MISSING" ""
}

if($text -notmatch '"execution_allowed_now":false'){
  Die "EXECUTION_ALLOWED_FALSE_MISSING" ""
}

Write-Output $text
Write-Output "PASS: backup run contract emitted"
Write-Output "PASS: repo-root destination blocked"
Write-Output "PASS: no copy performed"
Write-Output "SELFTEST_LD_STORAGE03_BACKUP_RUN_CONTRACT_OK"
