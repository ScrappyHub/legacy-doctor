param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$doctorPath = Join-Path $RepoRoot "scripts\doctor.ps1"
if (-not (Test-Path -LiteralPath $doctorPath)) { throw "Missing: $doctorPath" }

$raw = Get-Content -Raw -LiteralPath $doctorPath

# A) Remove any marker-led block (old insertion style)
$raw2 = [regex]::Replace(
  $raw,
  '(?s)# --- PS5\.1 COMPAT GATE \(must run before anything else\) ---.*?(?:\r?\n){2,}',
  '',
  1
)

# B) Remove strict block variant (vars + invoke + exitcode) — SINGLE-QUOTED so $ never expands
$raw3 = [regex]::Replace(
  $raw2,
  '(?s)\s*\$gateExe\s*=\s*"powershell\.exe"\s*\r?\n\s*\$gateScript\s*=\s*Join-Path\s+\$PSScriptRoot\s+"gate-ps51\.ps1"\s*\r?\n\s*\r?\n\s*&\s*\$gateExe\b.*?\r?\n\s*if\s*\(\s*\$LASTEXITCODE\s*-ne\s*0\s*\)\s*\{\s*throw\s*\(.*?\)\s*\}\s*\r?\n\s*\r?\n',
  "`r`n",
  1
)

# C) Remove any orphaned leftovers (safety net)
$raw4 = $raw3
$raw4 = [regex]::Replace($raw4, '(?m)^\s*\$gateExe\s*=.*\r?\n', '', 0)
$raw4 = [regex]::Replace($raw4, '(?m)^\s*\$gateScript\s*=.*gate-ps51\.ps1.*\r?\n', '', 0)
$raw4 = [regex]::Replace($raw4, '(?m)^\s*&\s*\$gateExe\b.*\r?\n', '', 0)
$raw4 = [regex]::Replace($raw4, '(?m)^\s*&\s*\$gateScript\b.*\r?\n', '', 0)
$raw4 = [regex]::Replace($raw4, '(?m)^\s*if\s*\(\s*\$LASTEXITCODE\s*-ne\s*0\s*\)\s*\{\s*throw\s*\(.*gate.*\)\s*\}\s*\r?\n', '', 0)

if ($raw4 -eq $raw) {
  Write-Host "doctor.ps1: no gate code found (no changes)." -ForegroundColor DarkGray
  exit 0
}

Set-Content -LiteralPath $doctorPath -Encoding UTF8 -Value $raw4
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $doctorPath)) | Out-Null
Write-Host ("PATCHED OK: {0}" -f $doctorPath) -ForegroundColor Green
