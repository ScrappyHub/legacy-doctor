param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Inv = Join-Path $RepoRoot "scripts\storage\ld_device_inventory_v1.ps1"
$Mount = Join-Path $RepoRoot "scripts\storage\ld_mount_state_v1.ps1"

$outInv = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Inv -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "INVENTORY_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$outMount = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Mount -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "MOUNT_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$invText = ($outInv -join "`n")
$mountText = ($outMount -join "`n")

if($invText -notmatch "LD_DEVICE_INVENTORY_OK"){ Die "INVENTORY_TOKEN_MISSING" "" }
if($mountText -notmatch "LD_DEVICE_MOUNT_STATE_OK"){ Die "MOUNT_TOKEN_MISSING" "" }

Write-Output $invText
Write-Output $mountText
Write-Output "PASS: device inventory emitted"
Write-Output "PASS: mount state emitted"
Write-Output "SELFTEST_LD_STORAGE03_INVENTORY_MOUNT_OK"
