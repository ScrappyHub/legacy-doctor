param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Fail([string]$msg) { Write-Host $msg -ForegroundColor Red; exit 1 }
function Ok([string]$msg)   { Write-Host $msg -ForegroundColor Green }
function Warn([string]$msg) { Write-Host $msg -ForegroundColor Yellow }

function Require-File([string]$p) { if (-not (Test-Path -LiteralPath $p)) { Fail ("Missing required file: {0}" -f $p) } }

$runPath     = Join-Path $RepoRoot "scripts\run.ps1"
$gatePath    = Join-Path $RepoRoot "scripts\gate-ps51.ps1"
$doctorPath  = Join-Path $RepoRoot "scripts\doctor.ps1"
$pkgPath     = Join-Path $RepoRoot "scripts\engine-package.ps1"
$entryMdPath = Join-Path $RepoRoot "scripts\_entrypoints.md"

Require-File $runPath
Require-File $gatePath
Require-File $doctorPath
Require-File $pkgPath

try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $runPath))    | Out-Null } catch { Fail ("Parse failed: run.ps1`r`n{0}" -f $_.Exception.Message) }
try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $gatePath))   | Out-Null } catch { Fail ("Parse failed: gate-ps51.ps1`r`n{0}" -f $_.Exception.Message) }
try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $doctorPath)) | Out-Null } catch { Fail ("Parse failed: doctor.ps1`r`n{0}" -f $_.Exception.Message) }
try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $pkgPath))    | Out-Null } catch { Fail ("Parse failed: engine-package.ps1`r`n{0}" -f $_.Exception.Message) }

Ok "PARSE OK: run.ps1 / gate-ps51.ps1 / doctor.ps1 / engine-package.ps1"

# Invariant: doctor.ps1 must not contain gate remnants
$doctorRaw = Get-Content -Raw -LiteralPath $doctorPath
if ($doctorRaw -match 'gate-ps51\.ps1' -or $doctorRaw -match '\`$gateExe' -or $doctorRaw -match '\`$gateScript') {
  Fail "doctor.ps1 contains gate leftovers (gate-ps51.ps1 or `$gateExe/`$gateScript). Gate must run only via run.ps1."
}
Ok "INVARIANT OK: doctor.ps1 has no gate leftovers."

# Invariant: run.ps1 references gate + doctor
$runRaw = Get-Content -Raw -LiteralPath $runPath
if ($runRaw -notmatch 'gate-ps51\.ps1') { Fail "run.ps1 does not reference gate-ps51.ps1 (required)." }
if ($runRaw -notmatch 'doctor\.ps1')    { Fail "run.ps1 does not reference doctor.ps1 (required)." }
Ok "INVARIANT OK: run.ps1 references gate + doctor."

if (Test-Path -LiteralPath $entryMdPath) { Ok "DOC OK: scripts\_entrypoints.md exists." } else { Warn "DOC WARN: scripts\_entrypoints.md missing." }

Write-Host "SELFCHECK OK." -ForegroundColor Green
