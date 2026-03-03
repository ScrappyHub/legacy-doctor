# ===========================================
# start-bg.ps1 (HUMAN ENTRYPOINT)
# Idempotent + supports -Quiet for automation.
# IMPORTANT: this script must NEVER print when -Quiet is set.
# ===========================================

param(
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Find-ListeningPort {
  foreach ($p in 8787..8792) {
    $line = netstat -ano |
      Select-String -SimpleMatch (":$p") |
      Select-String -SimpleMatch "LISTENING" |
      Select-Object -First 1
    if ($line) { return $p }
  }
  return $null
}

$existing = Find-ListeningPort
if ($existing) {
  if (-not $Quiet) {
    Write-Host "Legacy Doctor already running on port $existing" -ForegroundColor Green
  }
  return
}

# -----------------------------
# SPAWN NEW SERVER WINDOW HERE
# -----------------------------
# Replace the Start-Process below with your ACTUAL server launch command if different.

$cmd = @(
  '-NoProfile',
  '-ExecutionPolicy','Bypass',
  '-Command',
  'cd /d C:\dev\legacy-doctor; if (Test-Path .\.venv\Scripts\Activate.ps1) { . .\.venv\Scripts\Activate.ps1 }; python -m uvicorn legacy_doctor.api.main:app --host 127.0.0.1 --port 8787'
)

Start-Process powershell.exe -ArgumentList $cmd -WindowStyle Normal | Out-Null

if (-not $Quiet) {
  Write-Host "Started Legacy Doctor in a new Server Window on port 8787" -ForegroundColor Green
}

return
