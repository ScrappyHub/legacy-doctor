param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$doctorPath = Join-Path $RepoRoot "scripts\doctor.ps1"
if (-not (Test-Path -LiteralPath $doctorPath)) { throw "Missing: $doctorPath" }

$raw = Get-Content -Raw -LiteralPath $doctorPath

# Remove the entire inserted gate block (your strict version)
$pattern = "(?s)# --- PS5\.1 COMPAT GATE \(must run before anything else\) ---.*?\r?\n\r?\n"
$patched = [regex]::Replace($raw, $pattern, "", 1)

if ($patched -eq $raw) {
  Write-Host "doctor.ps1: no gate block found (no changes)." -ForegroundColor DarkGray
  exit 0
}

Set-Content -LiteralPath $doctorPath -Encoding UTF8 -Value $patched
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $doctorPath)) | Out-Null
Write-Host ("PATCHED OK: {0}" -f $doctorPath) -ForegroundColor Green
