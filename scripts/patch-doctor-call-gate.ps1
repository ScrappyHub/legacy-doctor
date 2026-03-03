param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$doctorPath = Join-Path $RepoRoot "scripts\doctor.ps1"
if (-not (Test-Path -LiteralPath $doctorPath)) { throw "Missing: $doctorPath" }

$doctorRaw = Get-Content -Raw -LiteralPath $doctorPath

$insertion = @"
# --- PS5.1 COMPAT GATE (must run before anything else) ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path `$PSScriptRoot "gate-ps51.ps1") | Out-Host

"@

if ($doctorRaw -match "gate-ps51\.ps1") {
  Write-Host "doctor.ps1 already calls gate-ps51.ps1 (no patch needed)." -ForegroundColor DarkGray
  exit 0
}

if ($doctorRaw -match "(?m)^\s*Set-StrictMode\s+-Version\s+Latest\s*$") {
  $doctorPatched = [regex]::Replace(
    $doctorRaw,
    "(?m)^\s*Set-StrictMode\s+-Version\s+Latest\s*$",
    { param($m) $m.Value + "`r`n`r`n" + $insertion },
    1
  )
}
elseif ($doctorRaw -match "(?s)^\s*param\s*\((.*?)\)\s*") {
  $doctorPatched = [regex]::Replace(
    $doctorRaw,
    "(?s)^\s*param\s*\((.*?)\)\s*",
    { param($m) $m.Value + "`r`n" + $insertion },
    1
  )
}
else {
  $doctorPatched = $insertion + $doctorRaw
}

Set-Content -LiteralPath $doctorPath -Encoding UTF8 -Value $doctorPatched
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $doctorPath)) | Out-Null
Write-Host ("PATCHED OK: {0}" -f $doctorPath) -ForegroundColor Green
