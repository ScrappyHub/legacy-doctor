param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_destination_selector_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -DestinationPath $RepoRoot
if($LASTEXITCODE -ne 0){ Die "DESTINATION_SELECTOR_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_DESTINATION_SELECTOR_OK"){
  Die "DESTINATION_SELECTOR_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"performs_copy":false'){
  Die "PERFORMS_COPY_FALSE_MISSING" ""
}

if($text -notmatch 'SOURCE_EQUALS_DESTINATION|INSUFFICIENT_SPACE|READY_DESTINATION|DESTINATION_REVIEW'){
  Die "DESTINATION_DECISION_MISSING" ""
}

Write-Output $text
Write-Output "PASS: destination selector emitted"
Write-Output "PASS: dry-run only, no copy"
Write-Output "SELFTEST_LD_STORAGE03_DESTINATION_SELECTOR_OK"
