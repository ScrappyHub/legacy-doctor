param(
  [Parameter(Mandatory=$true)][string]$AppSpec
)

$ErrorActionPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

function Find-ListeningPort {
  foreach ($p in 8787..8792) {
    $line = netstat -ano 2>$null |
      Select-String -SimpleMatch (":$p") |
      Select-String -SimpleMatch "LISTENING" |
      Select-Object -First 1
    if ($line) { return $p }
  }
  return $null
}

$existing = Find-ListeningPort
if ($existing) { Write-Output $existing; exit 0 }

$here = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path (Join-Path $here "..")).Path
$startBg = Join-Path $repoRoot "scripts\start-bg.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startBg -AppSpec $AppSpec -Port 8787 -Quiet | Out-Null

$deadline = (Get-Date).AddSeconds(25)
do {
  Start-Sleep -Milliseconds 250
  $started = Find-ListeningPort
  if ($started) { Write-Output $started; exit 0 }
} while ((Get-Date) -lt $deadline)

Write-Error "Server did not start on ports 8787-8792. Check logs under $env:LOCALAPPDATA\LegacyDoctor\logs"
exit 1
