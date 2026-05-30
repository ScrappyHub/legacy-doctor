param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_MISSING" $Path
  }

  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ":" + $e.Message)
  }

  Write-Output ("PARSE_OK: " + $Path)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$files = @(
  (Join-Path $RepoRoot "scripts\storage\ld_device_inventory_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_mount_state_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_inventory_mount_v1.ps1")
)

foreach($f in @($files)){
  Parse-GateFile $f
}

$schemas = @(
  (Join-Path $RepoRoot "schemas\ld.device.inventory.receipt.v1.json"),
  (Join-Path $RepoRoot "schemas\ld.device.mount_state.receipt.v1.json")
)

foreach($s in @($schemas)){
  if(-not (Test-Path -LiteralPath $s -PathType Leaf)){
    Die "SCHEMA_MISSING" $s
  }

  Write-Output ("SCHEMA_OK: " + $s)
}

$selftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_inventory_mount_v1.ps1"
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $selftest -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "SELFTEST_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$outText = ($out -join "`n")
Write-Output $outText

if($outText -notmatch "SELFTEST_LD_STORAGE03_INVENTORY_MOUNT_OK"){
  Die "SELFTEST_TOKEN_MISSING" ""
}

Write-Output "LEGACY_DOCTOR_STORAGE03_INVENTORY_MOUNT_GREEN"
