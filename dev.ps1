$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$venvActivate = Join-Path $PSScriptRoot ".venv\Scripts\Activate.ps1"
if (-not (Test-Path $venvActivate)) {
  throw "Missing venv. Run: python -m venv .venv"
}

. $venvActivate
$env:PYTHONPATH = (Join-Path (Get-Location) "src")

Write-Host "Dev shell ready:"
Write-Host "  python --version"
Write-Host "  python -m uvicorn legacy_doctor.api.server:app --host 127.0.0.1 --port 8787"