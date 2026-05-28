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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PacketLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_packet_v1.ps1"
$PackScript = Join-Path $RepoRoot "scripts\storage\ld_pack_acquisition_v1.ps1"
$BackupScript = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"
$VerifyScript = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"
$ExtractScript = Join-Path $RepoRoot "scripts\storage\ld_extract_image_v1.ps1"

foreach($p in @($PacketLib,$PackScript,$BackupScript,$VerifyScript,$ExtractScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$srcPath = Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin"

$acqOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BackupScript -RepoRoot $RepoRoot -SourcePath $srcPath -Mode raw_image -ChunkSizeBytes 262144 2>&1
$acqJoined = (@(@($acqOut)) -join "`n")
foreach($x in @(@($acqOut))){ [Console]::Out.WriteLine($x) }
Require ($acqJoined -match "LD_BACKUP_DEVICE_OK") "ACQ_FAIL" ""

$backupLedger = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"
$lastBackup = Get-Content -LiteralPath $backupLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
$imagePath = [string]$lastBackup.image_path
$acqManifestPath = [string]$lastBackup.manifest_path

$verOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyScript -RepoRoot $RepoRoot -ImagePath $imagePath -ManifestPath $acqManifestPath 2>&1
$verJoined = (@(@($verOut)) -join "`n")
foreach($x in @(@($verOut))){ [Console]::Out.WriteLine($x) }
Require ($verJoined -match "LD_VERIFY_IMAGE_OK") "VERIFY_FAIL" ""

$verifyLedger = Join-Path $RepoRoot "proofs\receipts\device_verify.ndjson"
$verifyReceiptPath = Join-Path $RepoRoot "proofs\packets\_selftest_verify_receipt.json"
$verifyLastLine = Get-Content -LiteralPath $verifyLedger -Encoding UTF8 | Select-Object -Last 1
[IO.File]::WriteAllText($verifyReceiptPath, ($verifyLastLine + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$extOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ExtractScript -RepoRoot $RepoRoot -ImagePath $imagePath -Mode full_copy 2>&1
$extJoined = (@(@($extOut)) -join "`n")
foreach($x in @(@($extOut))){ [Console]::Out.WriteLine($x) }
Require ($extJoined -match "LD_EXTRACT_IMAGE_OK") "EXTRACT_FAIL" ""

$extractLedger = Join-Path $RepoRoot "proofs\receipts\device_extract.ndjson"
$extractReceiptPath = Join-Path $RepoRoot "proofs\packets\_selftest_extract_receipt.json"
$extractLastLine = Get-Content -LiteralPath $extractLedger -Encoding UTF8 | Select-Object -Last 1
[IO.File]::WriteAllText($extractReceiptPath, ($extractLastLine + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$packOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PackScript -RepoRoot $RepoRoot -ImagePath $imagePath -AcquisitionManifestPath $acqManifestPath -VerifyReceiptPath $verifyReceiptPath -ExtractReceiptPath $extractReceiptPath 2>&1
$packJoined = (@(@($packOut)) -join "`n")
foreach($x in @(@($packOut))){ [Console]::Out.WriteLine($x) }
Require ($packJoined -match "LD_PACKET_ACQUISITION_OK") "PACK_FAIL" ""

$packetRootLine = @(@($packOut) | Where-Object { $_ -like "PACKET_ROOT:*" }) | Select-Object -Last 1
$packetIdLine = @(@($packOut) | Where-Object { $_ -like "PACKET_ID:*" }) | Select-Object -Last 1
Require ($null -ne $packetRootLine) "PACKET_ROOT_MISSING" ""
Require ($null -ne $packetIdLine) "PACKET_ID_MISSING" ""

$packetRoot = $packetRootLine.Substring("PACKET_ROOT: ".Length)
$packetId = $packetIdLine.Substring("PACKET_ID: ".Length)

Require (Test-Path -LiteralPath (Join-Path $packetRoot "manifest.json") -PathType Leaf) "PACKET_MANIFEST_MISSING" ""
Require (Test-Path -LiteralPath (Join-Path $packetRoot "packet_id.txt") -PathType Leaf) "PACKET_ID_FILE_MISSING" ""
Require (Test-Path -LiteralPath (Join-Path $packetRoot "sha256sums.txt") -PathType Leaf) "PACKET_SHA256SUMS_MISSING" ""
Require ((Get-Content -LiteralPath (Join-Path $packetRoot "packet_id.txt") -Raw -Encoding UTF8).Trim() -eq $packetId) "PACKET_ID_FILE_BAD" ""

Write-Host "PASS: packet build" -ForegroundColor Green
Write-Host "PASS: packet id persisted" -ForegroundColor Green
Write-Host "PASS: sha256sums emitted" -ForegroundColor Green
Write-Host "SELFTEST_LD_PACK_ACQUISITION_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"