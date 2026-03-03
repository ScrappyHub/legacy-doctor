param(
  [string]$AppSpec = "legacy_doctor.api.server:app",
  [int]$Port = 8787,
  [int]$TimeoutSeconds = 25
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Test-ListeningPort([int]$p) {
  try {
    $c = Test-NetConnection 127.0.0.1 -Port $p -WarningAction SilentlyContinue
    return [bool]$c.TcpTestSucceeded
  } catch { return $false }
}

function Get-LatestLogPath {
  $latestPath = Join-Path $env:LOCALAPPDATA "LegacyDoctor\logs\server_latest_path.txt"
  if (-not (Test-Path -LiteralPath $latestPath)) { return "<unknown>" }
  $v = (Get-Content -LiteralPath $latestPath -ErrorAction SilentlyContinue | Select-Object -First 1)
  if (-not $v) { return "<unknown>" }
  return $v.Trim()
}

# Start server if needed (start-bg returns immediately)
if (-not (Test-ListeningPort $Port)) {
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "start-bg.ps1") -AppSpec $AppSpec -Port $Port -Quiet | Out-Null
}

# Wait for TCP
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
  if (Test-ListeningPort $Port) { break }
  Start-Sleep -Milliseconds 200
} while ((Get-Date) -lt $deadline)

if (-not (Test-ListeningPort $Port)) {
  $log = Get-LatestLogPath
  throw "Server not listening on $Port after $TimeoutSeconds sec. Check: $log"
}

# Wait for /v1/health ok=true
$healthDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
$healthOk = $false
do {
  try {
    $r = curl.exe -s "http://127.0.0.1:$Port/v1/health"
    if ($r -match '"ok"\s*:\s*true') { $healthOk = $true; break }
  } catch {}
  Start-Sleep -Milliseconds 250
} while ((Get-Date) -lt $healthDeadline)

$log = Get-LatestLogPath
if (-not $healthOk) {
  throw "Server listening on $Port but /v1/health did not return ok=true within $TimeoutSeconds sec. Check: $log"
}

Write-Host ("OK  port={0}  health={1}  log={2}" -f $Port, "http://127.0.0.1:$Port/v1/health", $log) -ForegroundColor Green
