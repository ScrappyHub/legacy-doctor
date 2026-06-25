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
  (Join-Path $RepoRoot "scripts\storage\ld_copy_manifest_dry_run_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_copy_manifest_dry_run_v1.ps1")
)

foreach($f in @($files)){
  Parse-GateFile $f
}

$schema = Join-Path $RepoRoot "schemas\ld.device.copy_manifest_dry_run.receipt.v1.json"
if(-not (Test-Path -LiteralPath $schema -PathType Leaf)){
  Die "SCHEMA_MISSING" $schema
}

Write-Output ("SCHEMA_OK: " + $schema)

$selftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_copy_manifest_dry_run_v1.ps1"
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $selftest -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "SELFTEST_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$outText = ($out -join "`n")
Write-Output $outText

if($outText -notmatch "SELFTEST_LD_STORAGE03_COPY_MANIFEST_DRY_RUN_OK"){
  Die "SELFTEST_TOKEN_MISSING" ""
}

Write-Output "LEGACY_DOCTOR_STORAGE03_COPY_MANIFEST_DRY_RUN_GREEN"
