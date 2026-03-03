param(
  [int]$Tail = 80
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$latestPath = Join-Path $env:LOCALAPPDATA "LegacyDoctor\logs\server_latest_path.txt"
if (-not (Test-Path -LiteralPath $latestPath)) { throw "No latest log pointer yet: $latestPath" }

$runLog = (Get-Content -LiteralPath $latestPath | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($runLog)) { throw "Latest log pointer is empty: $latestPath" }
if (-not (Test-Path -LiteralPath $runLog)) { throw "Log missing: $runLog" }

Write-Host ("TAIL SNAPSHOT  lines={0}  file={1}" -f $Tail, $runLog) -ForegroundColor Green
Get-Content -LiteralPath $runLog -Tail $Tail
