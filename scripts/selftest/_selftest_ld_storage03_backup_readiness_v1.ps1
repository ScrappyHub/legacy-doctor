param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_backup_readiness_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "BACKUP_READINESS_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_BACKUP_READINESS_OK"){
  Die "BACKUP_READINESS_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"write_test":false'){
  Die "WRITE_TEST_FALSE_MISSING" ""
}

if($text -notmatch 'READY_FILE_BACKUP'){
  Die "READY_FILE_BACKUP_MISSING" ""
}

if($text -notmatch 'READY_RAW_IMAGE_'){
  Die "RAW_IMAGE_RECOMMENDATION_MISSING" ""
}

Write-Output $text
Write-Output "PASS: backup readiness emitted"
Write-Output "PASS: non-destructive flags present"
Write-Output "PASS: operator recommendations present"
Write-Output "SELFTEST_LD_STORAGE03_BACKUP_READINESS_OK"
