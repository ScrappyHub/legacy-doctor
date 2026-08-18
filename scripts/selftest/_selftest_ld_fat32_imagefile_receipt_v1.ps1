param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Require([bool]$Condition,[string]$Code,[string]$Detail){
  if(-not $Condition){ Die $Code $Detail }
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die "PARSE_GATE_MISSING" $Path }
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  if(@($errors).Count -gt 0){ Die "PARSE_GATE_FAIL" ($Path + ":" + $errors[0].Message) }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ReceiptsLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1"
$SchemaPath = Join-Path $RepoRoot "schemas\ld.fat32.imagefile.receipt.v1.json"

Parse-GateFile $ReceiptsLib
if(-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)){ Die "MISSING_SCHEMA" $SchemaPath }
try { $null = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop }
catch { Die "SCHEMA_JSON_INVALID" $_.Exception.Message }

. $ReceiptsLib

# This is a small deterministic file fixture, not a device image operation.
$fixtureDir = Join-Path $RepoRoot "proofs\selftest\receipt_fixture"
if(-not (Test-Path -LiteralPath $fixtureDir -PathType Container)){
  New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null
}
$fixturePath = Join-Path $fixtureDir "deterministic_fixture.bin"
$fixtureBytes = New-Object byte[] 4096
for($i=0; $i -lt $fixtureBytes.Length; $i++){ $fixtureBytes[$i] = [byte]($i % 251) }
[IO.File]::WriteAllBytes($fixturePath,$fixtureBytes)

$sector = New-Object byte[] 512
[Array]::Copy($fixtureBytes,0,$sector,0,$sector.Length)
$fixtureHash = LDREC-HexSha256Bytes $fixtureBytes
$sectorHash = LDREC-HexSha256Bytes $sector

$receipt = [ordered]@{
  schema = "ld.fat32.imagefile.receipt.v1"
  event_type = "ld.fat32.imagefile.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  image_path = $fixturePath
  image_sha256 = $fixtureHash
  plan_sha256 = (LDREC-HexSha256TextLf "receipt-fixture-plan-v1")
  disk_size_bytes = [UInt64]$fixtureBytes.Length
  bytes_per_sector = 512
  device_id = "fixture:not-a-device"
  disk_number = 0
  partition_start_lba = 1
  partition_size_lba = 7
  sectors_per_cluster = 1
  reserved_sectors = 1
  fat_count = 2
  fat_size_sectors = 1
  root_cluster = 2
  label = "FIXTURE"
  sector_hashes = [ordered]@{
    mbr = $sectorHash
    boot = $sectorHash
    fsinfo = $sectorHash
    backup_boot = $sectorHash
    fat0 = $sectorHash
    root0 = $sectorHash
  }
}

$expectedReceiptHash = LDREC-HexSha256TextLf (LDREC-ToCanonJson $receipt)
$actualReceiptHash = LDREC-AppendReceipt -RepoRoot $RepoRoot -Receipt $receipt
Require ($actualReceiptHash -eq $expectedReceiptHash) "RECEIPT_HASH_MISMATCH" $actualReceiptHash

$receiptPath = LDREC-ReceiptPath $RepoRoot
$lastLine = Get-Content -LiteralPath $receiptPath -Encoding UTF8 | Select-Object -Last 1
$last = $lastLine | ConvertFrom-Json
Require ($last.receipt_hash -eq $expectedReceiptHash) "STORED_RECEIPT_HASH_MISMATCH" ([string]$last.receipt_hash)
Require ($last.image_sha256 -eq $fixtureHash) "FIXTURE_HASH_MISMATCH" ([string]$last.image_sha256)
Require (-not ([string]$last.device_id).StartsWith("win.disk.v1:")) "FIXTURE_MISREPRESENTED_AS_DEVICE" ([string]$last.device_id)

Write-Output "PASS: deterministic receipt fixture emitted and recomputed"
Write-Output "PASS: fixture is explicitly not a device image"
Write-Output "SELFTEST_LD_FAT32_IMAGEFILE_RECEIPT_OK"
Write-Output "FULL_GREEN"
