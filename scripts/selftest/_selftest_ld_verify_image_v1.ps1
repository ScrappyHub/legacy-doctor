param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Require([bool]$Condition,[string]$Code,[string]$Detail){
  if(-not $Condition){
    Die $Code $Detail
  }
}

function Parse-GateFile([string]$Path){
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

function Copy-File([string]$From,[string]$To){
  $dir = Split-Path -Parent $To
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  Copy-Item -LiteralPath $From -Destination $To -Force
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$VerifyLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_verify_v1.ps1"
$VerifyScript = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"
$BackupScript = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"
$SchemaPath = Join-Path $RepoRoot "schemas\ld.device.verify.receipt.v1.json"
$VerifyLedger = Join-Path $RepoRoot "proofs\receipts\device_verify.ndjson"
$NegDir = Join-Path $RepoRoot "proofs\verify_negatives"

foreach($p in @($VerifyLib,$VerifyScript,$BackupScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

Require (Test-Path -LiteralPath $SchemaPath -PathType Leaf) "MISSING_SCHEMA" $SchemaPath
Write-Host ("SCHEMA_OK: " + $SchemaPath) -ForegroundColor DarkGray

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

# Build fresh acquisition artifact to verify
$acqOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BackupScript -RepoRoot $RepoRoot -SourcePath (Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin") -Mode raw_image -ChunkSizeBytes 262144 2>&1
$acqJoined = (@(@($acqOut)) -join "`n")
foreach($x in @(@($acqOut))){
  [Console]::Out.WriteLine($x)
}
Require ($acqJoined -match "LD_BACKUP_DEVICE_OK") "ACQUIRE_SETUP_FAIL" ""

$backupLedger = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"
$lastBackup = Get-Content -LiteralPath $backupLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
$imagePath = [string]$lastBackup.image_path
$manifestPath = [string]$lastBackup.manifest_path

# Positive verify
$beforeVerifyCount = 0
if(Test-Path -LiteralPath $VerifyLedger -PathType Leaf){
  $beforeVerifyCount = @((Get-Content -LiteralPath $VerifyLedger -Encoding UTF8)).Count
}

$verifyOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyScript -RepoRoot $RepoRoot -ImagePath $imagePath -ManifestPath $manifestPath 2>&1
$verifyJoined = (@(@($verifyOut)) -join "`n")
foreach($x in @(@($verifyOut))){
  [Console]::Out.WriteLine($x)
}
Require ($verifyJoined -match "LD_VERIFY_IMAGE_OK") "VERIFY_POSITIVE_FAIL" ""

$afterVerifyCount = @((Get-Content -LiteralPath $VerifyLedger -Encoding UTF8)).Count
Require ($afterVerifyCount -ge ($beforeVerifyCount + 1)) "VERIFY_LEDGER_APPEND_FAIL" ""

$lastVerify = Get-Content -LiteralPath $VerifyLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
Require ($lastVerify.verification_result -eq "VERIFY_OK") "VERIFY_RESULT_BAD" ([string]$lastVerify.verification_result)

# Negative: corrupt image byte and expect hash failure
if(-not (Test-Path -LiteralPath $NegDir -PathType Container)){
  New-Item -ItemType Directory -Force -Path $NegDir | Out-Null
}
$badImage = Join-Path $NegDir "corrupt_image.img"
$badManifest = Join-Path $NegDir "corrupt_image.manifest.json"
Copy-File -From $imagePath -To $badImage
Copy-File -From $manifestPath -To $badManifest

$fs = [IO.File]::Open($badImage,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
  [void]$fs.Seek(100,[IO.SeekOrigin]::Begin)
  $b = $fs.ReadByte()
  if($b -lt 0){ Die "NEGATIVE_IMAGE_EMPTY" $badImage }
  [void]$fs.Seek(100,[IO.SeekOrigin]::Begin)
  $fs.WriteByte([byte](($b -bxor 0xFF) -band 0xFF))
  $fs.Flush()
}
finally {
  $fs.Dispose()
}

$negOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyScript -RepoRoot $RepoRoot -ImagePath $badImage -ManifestPath $badManifest 2>&1
$negJoined = (@(@($negOut)) -join "`n")
foreach($x in @(@($negOut))){
  [Console]::Out.WriteLine($x)
}

Require ($negJoined -match "LD_VERIFY_IMAGE_FAIL:VERIFY_FAIL_CHUNK_HASH" -or $negJoined -match "LD_VERIFY_IMAGE_FAIL:VERIFY_FAIL_IMAGE_HASH") "NEGATIVE_VERIFY_DID_NOT_FAIL_CORRECTLY" ""

Write-Host "PASS: verify positive manifest/image match" -ForegroundColor Green
Write-Host "PASS: verify negative corruption detection" -ForegroundColor Green
Write-Host "SELFTEST_LD_VERIFY_IMAGE_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"