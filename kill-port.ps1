param([int]$Port = 8787)

$ErrorActionPreference = "Stop"
$line = (netstat -ano | findstr ":$Port" | Select-Object -First 1)
if (-not $line) { Write-Host "No listener found on port $Port"; exit 0 }

$pid = ($line -split "\s+")[-1]
Write-Host "Killing PID $pid on port $Port"
Stop-Process -Id $pid -Force