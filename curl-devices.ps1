param(
  [int[]]$Ports = @(8787,8788,8789,8790,8791,8792)
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

foreach ($p in $Ports) {
  try {
    $r = curl.exe -s "http://127.0.0.1:$p/v1/health"
    if ($LASTEXITCODE -eq 0 -and $r -match '"status"\s*:\s*"ok"') {
      Write-Host "Server found on port $p"
      curl.exe "http://127.0.0.1:$p/v1/devices"
      exit 0
    }
  } catch { }
}

throw "No server found on ports: $($Ports -join ', '). Start it in the Server Window with: .\run.ps1 -AutoPort"