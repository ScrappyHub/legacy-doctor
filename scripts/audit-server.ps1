param(
  [int]$Port = 8787,
  [string]$AppSpec = "legacy_doctor.api.server:app",
  [int]$TimeoutSeconds = 25,
  [int]$Tail = 80
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$logDir = Join-Path $env:LOCALAPPDATA "LegacyDoctor\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$auditOut = Join-Path $logDir ("audit_" + $ts + ".txt")

function Write-Audit([string]$s) {
  $s | Tee-Object -FilePath $auditOut -Append | Out-Host
}

Write-Audit ("AUDIT START  ts={0}  repo={1}" -f $ts, $repoRoot)
Write-Audit ("PORT={0}  APPSPEC={1}  TIMEOUT={2}s  TAIL={3}" -f $Port, $AppSpec, $TimeoutSeconds, $Tail)
Write-Audit ("USER={0}  MACHINE={1}" -f $env:USERNAME, $env:COMPUTERNAME)
Write-Audit ""

# 1) Ensure health (starts server window if needed)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "ensure-health.ps1") -AppSpec $AppSpec -Port $Port -TimeoutSeconds $TimeoutSeconds |
  ForEach-Object { Write-Audit $_ }

Write-Audit ""

# 2) Who is listening (PID + cmdline + parent)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "where-server.ps1") -Port $Port |
  ForEach-Object { Write-Audit $_ }

Write-Audit ""

# 3) Snapshot logs (bounded, no -Wait)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "tail-log.ps1") -Tail $Tail |
  ForEach-Object { Write-Audit $_ }

Write-Audit ""
Write-Audit ("AUDIT OUT: {0}" -f $auditOut)
