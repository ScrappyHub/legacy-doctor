param(
  [int]$Port = 8787,
  [switch]$AutoPort
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Activate venv if present
$venvActivate = Join-Path $PSScriptRoot ".venv\Scripts\Activate.ps1"
if (Test-Path $venvActivate) { . $venvActivate }

# Ensure src/ is importable
$env:PYTHONPATH = (Join-Path (Get-Location) "src")

function Test-PortFree([int]$p) {
  try {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
    $l.Start()
    $l.Stop()
    return $true
  } catch {
    return $false
  }
}

if ($AutoPort) {
  $p = $Port
  while (-not (Test-PortFree $p)) { $p++ }
  $Port = $p
}

Write-Host "Starting Legacy Doctor on http://127.0.0.1:$Port"
python -m uvicorn legacy_doctor.api.server:app --host 127.0.0.1 --port $Port