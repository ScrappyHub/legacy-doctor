param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die($c,$d){ throw ($c + ":" + $d) }

function Read($p){
  if(-not (Test-Path $p)){ Die "MISSING" $p }
  [IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false))
}

function Write($p,$t){
  $dir = Split-Path -Parent $p
  if($dir -and -not (Test-Path $dir)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $t -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($p,$t,[Text.UTF8Encoding]::new($false))
}

function Parse($p){
  [ScriptBlock]::Create((Get-Content -Raw $p)) | Out-Null
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_verify_image_v1.ps1"

$text = Read $Target

# Find the throw
$pattern = 'VERIFY_LEDGER_APPEND_FAIL'

if(-not $text.Contains($pattern)){
  Die "RUNNER_PATTERN_NOT_FOUND" $pattern
}

# Replace with real error propagation
$text = $text -replace 'VERIFY_LEDGER_APPEND_FAIL','VERIFY_LEDGER_APPEND_FAIL:" + $_'

# Also fix the catch block to include $_.Exception.Message if needed
$text = $text -replace 'catch\s*\{','catch { throw ("VERIFY_LEDGER_APPEND_FAIL:" + $_.Exception.Message) } #'

Write $Target $text
Parse $Target

Write-Host "PATCH_OK: VERIFY_IMAGE_RUNNER_ERROR_FIXED" -ForegroundColor Green