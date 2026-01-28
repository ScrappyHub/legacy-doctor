$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".last-port")) { throw "No .last-port found. Start server with: .\run.ps1 -AutoPort" }
$port = Get-Content ".last-port" -Raw

curl.exe "http://127.0.0.1:$port/v1/devices"