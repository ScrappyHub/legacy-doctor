param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_backup_dry_run_enumerator_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -MaxFilesPerSource 20 -MaxDirsPerSource 10 -MaxSamplesPerSource 5
if($LASTEXITCODE -ne 0){ Die "BACKUP_DRY_RUN_ENUMERATOR_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_BACKUP_DRY_RUN_ENUMERATOR_(OK|UNAVAILABLE)"){
  Die "BACKUP_DRY_RUN_ENUMERATOR_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"performs_copy":false'){
  Die "PERFORMS_COPY_FALSE_MISSING" ""
}

if($text -notmatch '"reads_file_metadata":true'){
  Die "READS_FILE_METADATA_TRUE_MISSING" ""
}

if($text -match "LD_DEVICE_BACKUP_DRY_RUN_ENUMERATOR_OK" -and $text -notmatch 'ENUMERATED_DRY_RUN_'){
  Die "ENUMERATED_DRY_RUN_STATE_MISSING" ""
}
if($text -match "LD_DEVICE_BACKUP_DRY_RUN_ENUMERATOR_UNAVAILABLE" -and $text -notmatch '"ok":false'){
  Die "ENUMERATOR_FALSE_UNAVAILABLE" ""
}

Write-Output $text
Write-Output "PASS: backup dry-run enumerator emitted"
Write-Output "PASS: metadata-only enumeration, no copy"
Write-Output "PASS: unavailable planning produces no enumeration"
Write-Output "SELFTEST_LD_STORAGE03_BACKUP_DRY_RUN_ENUMERATOR_OK"
