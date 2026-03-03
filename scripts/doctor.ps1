param(
  [ValidateSet("audit","inventory-only")][string]$Workflow = "audit",
  [string[]]$Targets = @("C:\"),
  [int]$Tail = 60
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest





# --- ENTRYPOINT CONTRACT: use-run-ps1 (warning only) ---
# Canonical execution is scripts\run.ps1 (it runs gate once, then runs doctor).
# Running doctor.ps1 directly bypasses the deterministic entrypoint.
try {
  if ($env:LEGACYDOCTOR_ENTRYPOINT -ne "run.ps1") {
    Write-Host "WARNING: Do not run scripts\doctor.ps1 directly. Use scripts\run.ps1." -ForegroundColor Yellow
  }
} catch {}


$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# 1) init run
$runDir = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-init.ps1") -Workflow $Workflow -Targets $Targets -NoSealOnInit
if (-not $runDir) { throw "run-init did not return a run dir." }

# 2) inventory
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "engine-inventory.ps1") -RunDir $runDir -Targets $Targets | Out-Null

if ($Workflow -eq "inventory-only") {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "engine-verify.ps1") -RunDir $runDir | Out-Null
  Write-Host ("DONE  runDir={0}" -f $runDir) -ForegroundColor Green
  Write-Host ("TIP   tail: Get-Content -LiteralPath '{0}' -Tail {1}" -f (Join-Path $runDir "audit.v1.jsonl"), $Tail) -ForegroundColor DarkGray
  exit 0
}

# 3) acquire (placeholder for now)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "engine-acquire.ps1") -RunDir $runDir -Targets $Targets | Out-Null

# 4) package (placeholder for now)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "engine-package.ps1") -RunDir $runDir | Out-Null

# 5) verify/seal
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "engine-verify.ps1") -RunDir $runDir | Out-Null

Write-Host ("DONE  runDir={0}" -f $runDir) -ForegroundColor Green
Write-Host ("FILES manifest/entitlements/audit/sha256sums sealed") -ForegroundColor DarkGray
Write-Host ("AUDIT  {0}" -f (Join-Path $runDir "audit.v1.jsonl")) -ForegroundColor DarkGray
Write-Host ("HASHES {0}" -f (Join-Path $runDir "sha256sums.txt")) -ForegroundColor DarkGray







