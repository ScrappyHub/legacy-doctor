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

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }
  return [IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false)))
}

function Read-BytesAt([string]$Path,[UInt64]$Offset,[int]$Count){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }

  $fs = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try {
    [void]$fs.Seek([Int64]$Offset,[IO.SeekOrigin]::Begin)
    $buf = New-Object byte[] $Count
    $read = $fs.Read($buf,0,$buf.Length)
    if($read -ne $Count){
      Die "READ_SHORT" ($Path + ": offset=" + $Offset + " read=" + $read + " expected=" + $Count)
    }
    return $buf
  } finally {
    $fs.Dispose()
  }
}

function HexSha256Bytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = [byte[]]@() }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [IO.File]::OpenRead($Path)
    try {
      $hash = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RawLib              = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib           = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib             = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$ReceiptsLib         = Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1"
$VerifyImageSelftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_verify_imagefile_v1.ps1"
$SchemaPath          = Join-Path $RepoRoot "schemas\ld.fat32.imagefile.receipt.v1.json"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$ReceiptsLib,$VerifyImageSelftest)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

# JSON schema is not PowerShell; require existence only.
if(-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)){
  Die "MISSING_SCHEMA" $SchemaPath
}
Write-Host ("SCHEMA_OK: " + $SchemaPath) -ForegroundColor DarkGray

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyImageSelftest -RepoRoot $RepoRoot 2>&1

foreach($x in @(@($out))){
  [Console]::Out.WriteLine($x)
}

$joined = (@(@($out)) -join "`n")
if($joined -notmatch "FULL_GREEN"){
  Die "VERIFY_IMAGEFILE_SELFTEST_MISSING_FULL_GREEN" $VerifyImageSelftest
}
if($joined -notmatch "SELFTEST_LD_FAT32_OWNED_VERIFY_IMAGEFILE_OK"){
  Die "VERIFY_IMAGEFILE_SELFTEST_MISSING_OK" $VerifyImageSelftest
}

. $RawLib
. $LayoutLib
. $BootLib
. $ReceiptsLib

$ImagePath = Join-Path $RepoRoot "proofs\receipts\fat32_owned_imagefile\fat32_owned_test.img"
if(-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)){
  Die "MISSING_IMAGEFILE" $ImagePath
}

$DiskSizeBytes = [UInt64]4294967296
$BytesPerSector = 512

$plan = LDFAT-NewPlan `
  -DiskSizeBytes $DiskSizeBytes `
  -BytesPerSector $BytesPerSector `
  -DeviceId "win.disk.v1:test:imagefile" `
  -DiskNumber 777 `
  -Label "SDCARD" `
  -ClusterKiB 0

$mbr = Read-BytesAt -Path $ImagePath -Offset 0 -Count 512
$boot = Read-BytesAt -Path $ImagePath -Offset ([UInt64]$plan.partition_start_lba * [UInt64]$plan.bytes_per_sector) -Count 512
$fsi = Read-BytesAt -Path $ImagePath -Offset (([UInt64]$plan.partition_start_lba + [UInt64]$plan.fsinfo_sector) * [UInt64]$plan.bytes_per_sector) -Count 512
$bb = Read-BytesAt -Path $ImagePath -Offset (([UInt64]$plan.partition_start_lba + [UInt64]$plan.backup_boot_sector) * [UInt64]$plan.bytes_per_sector) -Count 512
$fat0 = Read-BytesAt -Path $ImagePath -Offset ([UInt64]$plan.fat1_start_lba * [UInt64]$plan.bytes_per_sector) -Count 512
$root0 = Read-BytesAt -Path $ImagePath -Offset ([UInt64]$plan.root_dir_first_lba * [UInt64]$plan.bytes_per_sector) -Count 512

$receipt = [ordered]@{
  schema = "ld.fat32.imagefile.receipt.v1"
  event_type = "ld.fat32.imagefile.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  image_path = $ImagePath
  image_sha256 = (HexSha256File $ImagePath)
  plan_sha256 = (LDREC-HexSha256TextLf (LDREC-ToCanonJson $plan))
  disk_size_bytes = [UInt64]$plan.disk_size_bytes
  bytes_per_sector = [UInt16]$plan.bytes_per_sector
  device_id = [string]$plan.device_id
  disk_number = [int]$plan.disk_number
  partition_start_lba = [UInt64]$plan.partition_start_lba
  partition_size_lba = [UInt64]$plan.partition_size_lba
  sectors_per_cluster = [UInt32]$plan.sectors_per_cluster
  reserved_sectors = [UInt16]$plan.reserved_sectors
  fat_count = [UInt16]$plan.fat_count
  fat_size_sectors = [UInt32]$plan.fat_size_sectors
  root_cluster = [UInt32]$plan.root_cluster
  label = [string]$plan.volume_label
  sector_hashes = [ordered]@{
    mbr = (LDREC-HexSha256Bytes $mbr)
    boot = (LDREC-HexSha256Bytes $boot)
    fsinfo = (LDREC-HexSha256Bytes $fsi)
    backup_boot = (LDREC-HexSha256Bytes $bb)
    fat0 = (LDREC-HexSha256Bytes $fat0)
    root0 = (LDREC-HexSha256Bytes $root0)
  }
}

$receiptPath = LDREC-ReceiptPath $RepoRoot
$beforeCount = 0
if(Test-Path -LiteralPath $receiptPath -PathType Leaf){
  $beforeCount = @((Get-Content -LiteralPath $receiptPath -Encoding UTF8)).Count
}

$receiptHash = LDREC-AppendReceipt -RepoRoot $RepoRoot -Receipt $receipt

Require (Test-Path -LiteralPath $receiptPath -PathType Leaf) "RECEIPT_PATH_MISSING" $receiptPath

$lines = @(Get-Content -LiteralPath $receiptPath -Encoding UTF8)
$afterCount = $lines.Count
Require ($afterCount -ge ($beforeCount + 1)) "RECEIPT_APPEND_FAIL" ("before=" + $beforeCount + " after=" + $afterCount)

$last = $lines[-1] | ConvertFrom-Json
Require ($last.schema -eq "ld.fat32.imagefile.receipt.v1") "RECEIPT_SCHEMA_BAD" ([string]$last.schema)
Require ($last.event_type -eq "ld.fat32.imagefile.receipt.v1") "RECEIPT_EVENT_BAD" ([string]$last.event_type)
Require ($last.ok -eq $true) "RECEIPT_OK_BAD" ([string]$last.ok)
Require ($last.receipt_hash -eq $receiptHash) "RECEIPT_HASH_BAD" ("actual=" + [string]$last.receipt_hash + " expected=" + $receiptHash)
Require ($last.image_sha256 -eq (HexSha256File $ImagePath)) "RECEIPT_IMAGE_HASH_BAD" ([string]$last.image_sha256)
Require ($last.plan_sha256 -eq (LDREC-HexSha256TextLf (LDREC-ToCanonJson $plan))) "RECEIPT_PLAN_HASH_BAD" ([string]$last.plan_sha256)
Require ($last.sector_hashes.mbr -eq (LDREC-HexSha256Bytes $mbr)) "RECEIPT_MBR_HASH_BAD" ([string]$last.sector_hashes.mbr)
Require ($last.sector_hashes.boot -eq (LDREC-HexSha256Bytes $boot)) "RECEIPT_BOOT_HASH_BAD" ([string]$last.sector_hashes.boot)
Require ($last.sector_hashes.fsinfo -eq (LDREC-HexSha256Bytes $fsi)) "RECEIPT_FSINFO_HASH_BAD" ([string]$last.sector_hashes.fsinfo)
Require ($last.sector_hashes.backup_boot -eq (LDREC-HexSha256Bytes $bb)) "RECEIPT_BACKUP_HASH_BAD" ([string]$last.sector_hashes.backup_boot)
Require ($last.sector_hashes.fat0 -eq (LDREC-HexSha256Bytes $fat0)) "RECEIPT_FAT0_HASH_BAD" ([string]$last.sector_hashes.fat0)
Require ($last.sector_hashes.root0 -eq (LDREC-HexSha256Bytes $root0)) "RECEIPT_ROOT0_HASH_BAD" ([string]$last.sector_hashes.root0)

Write-Host ("RECEIPT_PATH: " + $receiptPath) -ForegroundColor Green
Write-Host ("RECEIPT_HASH: " + $receiptHash) -ForegroundColor Green
Write-Host "SELFTEST_LD_FAT32_IMAGEFILE_RECEIPT_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
