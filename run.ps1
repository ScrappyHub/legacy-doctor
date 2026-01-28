param(
  [int]$Port = 8787
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Activate venv if present
$venvActivate = Join-Path $PSScriptRoot ".venv\Scripts\Activate.ps1"
if (Test-Path $venvActivate) {
  . $venvActivate
}

# Ensure src/ is importable
$env:PYTHONPATH = (Join-Path (Get-Location) "src")

python -m uvicorn legacy_doctor.api.server:app --host 127.0.0.1 --port $Port