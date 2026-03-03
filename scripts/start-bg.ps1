param(
  [Parameter(Mandatory=$true)][string]$AppSpec,
  [int]$Port = 8787,
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Import root (src if present, else repo)
$src = Join-Path $repoRoot "src"
$importRoot = if (Test-Path -LiteralPath $src) { $src } else { $repoRoot }

# Logs (per-run)
$logDir = Join-Path $env:LOCALAPPDATA "LegacyDoctor\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$runLog = Join-Path $logDir ("server_" + $ts + ".log")

# Stable pointer to latest log
$latestPath = Join-Path $logDir "server_latest_path.txt"
Set-Content -LiteralPath $latestPath -Encoding UTF8 -Value $runLog

# Create log immediately so tailers never race
New-Item -ItemType File -Force -Path $runLog | Out-Null

# Python
$venvPy = Join-Path $repoRoot ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $venvPy)) { throw "Missing venv python: $venvPy" }
if ([string]::IsNullOrWhiteSpace($AppSpec)) { throw "AppSpec empty" }

# Runner script (executed INSIDE the new server window)
$runner = Join-Path $env:TEMP ("legacydoctor_server_runner_" + $ts + ".ps1")

@"
`$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

Set-Location -LiteralPath '$repoRoot'
`$env:PYTHONPATH = '$importRoot'

Write-Host 'LegacyDoctor SERVER' -ForegroundColor Green
Write-Host ('PORT: {0}' -f $Port) -ForegroundColor DarkGray
Write-Host ('APP : {0}' -f '$AppSpec') -ForegroundColor DarkGray
Write-Host ('LOG : {0}' -f '$runLog') -ForegroundColor DarkGray
Write-Host ('URL : http://127.0.0.1:{0}' -f $Port) -ForegroundColor DarkGray
Write-Host ''

# IMPORTANT: keep uvicorn INFO (often on stderr) but don't turn it into PS errors.
& '$venvPy' -m uvicorn '$AppSpec' --host 127.0.0.1 --port $Port 2>&1 |
  ForEach-Object { [string]`$_ } |
  Tee-Object -FilePath '$runLog' -Append

Write-Host ''
Write-Host ('Server exited. Log: {0}' -f '$runLog') -ForegroundColor Yellow
Read-Host 'Press Enter to close'
"@ | Set-Content -LiteralPath $runner -Encoding UTF8

# ONE new window: server
Start-Process -FilePath "powershell.exe" -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-NoExit",
  "-File", $runner
) -WindowStyle Normal | Out-Null

if (-not $Quiet) {
  Write-Host ("Started server window  port={0}  app={1}" -f $Port, $AppSpec) -ForegroundColor Green
  Write-Host ("log={0}" -f $runLog) -ForegroundColor DarkGray
  Write-Host ("latest={0}" -f $latestPath) -ForegroundColor DarkGray
}
