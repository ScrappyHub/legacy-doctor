param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Parse-Gate([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_GATE_MISSING" $Path
  }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$BackupScript = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"
$VerifyScript = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"

Parse-Gate $BackupScript
Write-Host ("PARSE_OK: " + $BackupScript) -ForegroundColor DarkGray
Parse-Gate $VerifyScript
Write-Host ("PARSE_OK: " + $VerifyScript) -ForegroundColor DarkGray

Write-Host "RUN: backup selftest acquisition" -ForegroundColor Cyan
$backupOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BackupScript -RepoRoot $RepoRoot -SourcePath (Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin") -Mode raw_image -ChunkSizeBytes 262144 2>&1
$backupText = (@(@($backupOut)) -join "`n")
foreach($x in @(@($backupOut))){
  [Console]::Out.WriteLine($x)
}
if($backupText -notmatch "LD_BACKUP_DEVICE_OK"){
  Die "BACKUP_SELFTEST_FAIL" "missing LD_BACKUP_DEVICE_OK"
}

$backupLedger = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"
if(-not (Test-Path -LiteralPath $backupLedger -PathType Leaf)){
  Die "BACKUP_LEDGER_MISSING" $backupLedger
}
$lastBackup = Get-Content -LiteralPath $backupLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
$imagePath = [string]$lastBackup.image_path
$manifestPath = [string]$lastBackup.manifest_path

Write-Host "RUN: verify image (clean)" -ForegroundColor Cyan
$verifyOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyScript -RepoRoot $RepoRoot -ImagePath $imagePath -ManifestPath $manifestPath 2>&1
$verifyText = (@(@($verifyOut)) -join "`n")
foreach($x in @(@($verifyOut))){
  [Console]::Out.WriteLine($x)
}
if($verifyText -notmatch "LD_VERIFY_IMAGE_OK"){
  Die "VERIFY_CLEAN_FAIL" "missing LD_VERIFY_IMAGE_OK"
}

Write-Host "RUN: tamper test" -ForegroundColor Cyan
Add-Content -LiteralPath $imagePath -Value "X"

$negOut = $null
$negText = ""

try {
  $negOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyScript -RepoRoot $RepoRoot -ImagePath $imagePath -ManifestPath $manifestPath 2>&1
  $negText = (@(@($negOut)) -join "`n")
}
catch {
  $negText = $_.Exception.Message
}

if($negOut){
  foreach($x in @(@($negOut))){
    [Console]::Out.WriteLine($x)
  }
}

if($negText -notmatch "LD_VERIFY_FAIL:SHA256_MISMATCH"){
  Die "TAMPER_NEGATIVE_ASSERT_FAIL" $negText
}

Write-Host "PASS: tamper negative captured" -ForegroundColor Green
Write-Host "LD_TIER0_SELFTEST_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
