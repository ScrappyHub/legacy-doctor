param(
  [string[]]$DoctorArgs = @()
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Deterministic repo root: the directory this script is IN (safe because this is a FILE)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$gate   = Join-Path $repoRoot "scripts\gate-ps51.ps1"
$doctor = Join-Path $repoRoot "scripts\doctor.ps1"

if (-not (Test-Path -LiteralPath $gate))   { throw "Missing gate: $gate" }
if (-not (Test-Path -LiteralPath $doctor)) { throw "Missing doctor: $doctor" }

Write-Host ("ENTRYPOINT: repoRoot={0}" -f $repoRoot) -ForegroundColor DarkGray

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate | Out-Host
if ($LASTEXITCODE -ne 0) { throw ("PS5.1 gate failed (exit={0})." -f $LASTEXITCODE) }
# --- LEGACYDOCTOR_ENTRYPOINT FLAG (scoped; do not remove) ---
$__prev = $env:LEGACYDOCTOR_ENTRYPOINT
try {
  $env:LEGACYDOCTOR_ENTRYPOINT = "run.ps1"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $doctor @DoctorArgs | Out-Host
}
finally {
  if ($null -eq $__prev) { Remove-Item Env:\LEGACYDOCTOR_ENTRYPOINT -ErrorAction SilentlyContinue }
  else { $env:LEGACYDOCTOR_ENTRYPOINT = $__prev }
}
if ($LASTEXITCODE -ne 0) { throw ("doctor.ps1 failed (exit={0})." -f $LASTEXITCODE) }


