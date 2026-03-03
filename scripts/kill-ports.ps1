# ===========================================
# scripts\kill-ports.ps1
# Kills listeners on 8787..8792 (best effort)
# ===========================================
$ErrorActionPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

foreach ($p in 8787..8792) {
  $line = netstat -ano 2>$null | Select-String -SimpleMatch (":$p") | Select-String -SimpleMatch "LISTENING" | Select-Object -First 1
  if (-not $line) {
    Write-Host "No listener on port $p"
    continue
  }
  $parts = (($line -replace '\s+', ' ').Trim()) -split ' '
  $pid = $parts[-1]
  if ($pid -match '^\d+$') {
    Write-Host "Killing PID $pid (port $p)"
    taskkill /PID $pid /F | Out-Null
  } else {
    Write-Host "Could not parse PID for port $p"
  }
}
