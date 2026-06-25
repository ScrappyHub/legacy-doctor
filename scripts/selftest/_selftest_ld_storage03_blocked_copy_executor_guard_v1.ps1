param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_blocked_copy_executor_guard_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -DestinationPath $RepoRoot -MaxFiles 20 -MaxBytes 1048576 -MaxFilesPerSource 20 -MaxDirsPerSource 10 -MaxSamplesPerSource 5
if($LASTEXITCODE -ne 0){ Die "BLOCKED_COPY_EXECUTOR_GUARD_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_BLOCKED_COPY_EXECUTOR_GUARD_OK"){
  Die "BLOCKED_COPY_EXECUTOR_GUARD_TOKEN_MISSING" ""
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

if($text -notmatch '"would_invoke_future_executor":false'){
  Die "WOULD_INVOKE_FALSE_MISSING" ""
}

if($text -notmatch "EXECUTOR_GUARD_BLOCKED_CONTRACT_NOT_ALLOWED"){
  Die "CONTRACT_NOT_ALLOWED_GUARD_MISSING" ""
}

if($text -notmatch "EXECUTOR_GUARD_BLOCKED_REPO_ROOT_DESTINATION"){
  Die "REPO_ROOT_GUARD_MISSING" ""
}

Write-Output $text
Write-Output "PASS: blocked copy executor guard emitted"
Write-Output "PASS: future executor invocation blocked"
Write-Output "PASS: no copy performed"
Write-Output "SELFTEST_LD_STORAGE03_BLOCKED_COPY_EXECUTOR_GUARD_OK"
