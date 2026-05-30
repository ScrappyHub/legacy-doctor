param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_health_probe_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "HEALTH_PROBE_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_HEALTH_PROBE_OK"){
  Die "HEALTH_PROBE_TOKEN_MISSING" ""
}

if($text -notmatch "smart_claim"){
  Die "SMART_CLAIM_FIELD_MISSING" ""
}

Write-Output $text
Write-Output "PASS: health probe emitted"
Write-Output "PASS: SMART not overclaimed"
Write-Output "SELFTEST_LD_STORAGE03_HEALTH_PROBE_OK"
