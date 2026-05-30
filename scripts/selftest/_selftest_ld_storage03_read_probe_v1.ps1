param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_read_probe_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -MaxBytes 262144 -MaxFilesScanned 100
if($LASTEXITCODE -ne 0){ Die "READ_PROBE_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_READ_PROBE_OK"){
  Die "READ_PROBE_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"write_test":false'){
  Die "WRITE_TEST_FALSE_MISSING" ""
}

Write-Output $text
Write-Output "PASS: read probe emitted"
Write-Output "PASS: non-destructive flags present"
Write-Output "SELFTEST_LD_STORAGE03_READ_PROBE_OK"
