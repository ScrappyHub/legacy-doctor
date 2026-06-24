param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_destination_write_probe_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -DestinationPath $RepoRoot
if($LASTEXITCODE -ne 0){ Die "DESTINATION_WRITE_PROBE_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_DESTINATION_WRITE_PROBE_OK"){
  Die "DESTINATION_WRITE_PROBE_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"write_test":true'){
  Die "WRITE_TEST_TRUE_MISSING" ""
}

if($text -notmatch '"performs_copy":false'){
  Die "PERFORMS_COPY_FALSE_MISSING" ""
}

if($text -notmatch '"temp_hash_ok":true'){
  Die "TEMP_HASH_OK_MISSING" ""
}

if($text -notmatch '"temp_deleted":true'){
  Die "TEMP_DELETED_TRUE_MISSING" ""
}

if($text -notmatch '"write_probe_ok":true'){
  Die "WRITE_PROBE_OK_MISSING" ""
}

Write-Output $text
Write-Output "PASS: destination write probe emitted"
Write-Output "PASS: temp file hash verified"
Write-Output "PASS: temp file cleanup verified"
Write-Output "SELFTEST_LD_STORAGE03_DESTINATION_WRITE_PROBE_OK"
