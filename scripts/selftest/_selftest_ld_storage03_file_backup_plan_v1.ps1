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
