param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest

function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    throw ("MISSING_FILE:" + $Path)
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

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
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

function Read-BytesAt([string]$Path,[UInt64]$Offset,[int]$Count){
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RawLib            = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib         = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib           = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$VerifyFile        = Join-Path $RepoRoot "scripts\storage\ld_verify_fat32_layout_v1.ps1"
$ImagefileSelftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_imagefile_v1.ps1"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$VerifyFile,$ImagefileSelftest)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ImagefileSelftest -RepoRoot $RepoRoot 2>&1

foreach($x in @(@($out))){
  [Console]::Out.WriteLine($x)
}

$joined = (@(@($out)) -join "`n")
if($joined -notmatch "FULL_GREEN"){
  Die "IMAGEFILE_SELFTEST_MISSING_FULL_GREEN" $ImagefileSelftest
}
if($joined -notmatch "SELFTEST_LD_FAT32_OWNED_IMAGEFILE_OK"){
  Die "IMAGEFILE_SELFTEST_MISSING_OK" $ImagefileSelftest
}

. $RawLib
. $LayoutLib
. $BootLib

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

# MBR checks
Require ((LD-GetU16LE -Buffer $mbr -Offset 510) -eq 43605) "VERIFY_FAIL_MBR_SIGNATURE" "expected=43605"
Require ($mbr[446 + 4] -eq [byte]$plan.partition_type) "VERIFY_FAIL_PARTITION_TYPE" ("actual=" + $mbr[450] + " expected=" + [byte]$plan.partition_type)
Require ((LD-GetU32LE -Buffer $mbr -Offset 454) -eq [UInt32]$plan.partition_start_lba) "VERIFY_FAIL_PARTITION_START" ("actual=" + (LD-GetU32LE -Buffer $mbr -Offset 454) + " expected=" + [UInt32]$plan.partition_start_lba)
Require ((LD-GetU32LE -Buffer $mbr -Offset 458) -eq [UInt32]$plan.partition_size_lba) "VERIFY_FAIL_PARTITION_SIZE" ("actual=" + (LD-GetU32LE -Buffer $mbr -Offset 458) + " expected=" + [UInt32]$plan.partition_size_lba)
Write-Host "PASS: verify imagefile mbr" -ForegroundColor Green

# Boot checks
Require ((LD-GetU16LE -Buffer $boot -Offset 510) -eq 43605) "VERIFY_FAIL_BOOT_SIGNATURE" "expected=43605"
Require ((LD-GetU16LE -Buffer $boot -Offset 11) -eq [UInt16]$plan.bytes_per_sector) "VERIFY_FAIL_BOOT_BPS" ("actual=" + (LD-GetU16LE -Buffer $boot -Offset 11) + " expected=" + [UInt16]$plan.bytes_per_sector)
Require ($boot[13] -eq [byte]$plan.sectors_per_cluster) "VERIFY_FAIL_BOOT_SPC" ("actual=" + $boot[13] + " expected=" + [byte]$plan.sectors_per_cluster)
Require ((LD-GetU16LE -Buffer $boot -Offset 14) -eq [UInt16]$plan.reserved_sectors) "VERIFY_FAIL_BOOT_RSVD" ("actual=" + (LD-GetU16LE -Buffer $boot -Offset 14) + " expected=" + [UInt16]$plan.reserved_sectors)
Require ($boot[16] -eq [byte]$plan.fat_count) "VERIFY_FAIL_BOOT_FATS" ("actual=" + $boot[16] + " expected=" + [byte]$plan.fat_count)
Require ((LD-GetU32LE -Buffer $boot -Offset 36) -eq [UInt32]$plan.fat_size_sectors) "VERIFY_FAIL_BOOT_FATSZ32" ("actual=" + (LD-GetU32LE -Buffer $boot -Offset 36) + " expected=" + [UInt32]$plan.fat_size_sectors)
Require ((LD-GetU32LE -Buffer $boot -Offset 44) -eq [UInt32]$plan.root_cluster) "VERIFY_FAIL_BOOT_ROOTCLUSTER" ("actual=" + (LD-GetU32LE -Buffer $boot -Offset 44) + " expected=" + [UInt32]$plan.root_cluster)
Require ((LD-GetU16LE -Buffer $boot -Offset 48) -eq [UInt16]$plan.fsinfo_sector) "VERIFY_FAIL_BOOT_FSINFO" ("actual=" + (LD-GetU16LE -Buffer $boot -Offset 48) + " expected=" + [UInt16]$plan.fsinfo_sector)
Require ((LD-GetU16LE -Buffer $boot -Offset 50) -eq [UInt16]$plan.backup_boot_sector) "VERIFY_FAIL_BOOT_BACKUP" ("actual=" + (LD-GetU16LE -Buffer $boot -Offset 50) + " expected=" + [UInt16]$plan.backup_boot_sector)
Write-Host "PASS: verify imagefile boot" -ForegroundColor Green

# FSInfo checks
Require ((LD-GetU32LE -Buffer $fsi -Offset 0) -eq [UInt32]1096897106) "VERIFY_FAIL_FSINFO_LEAD" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 0))
Require ((LD-GetU32LE -Buffer $fsi -Offset 484) -eq [UInt32]1631679090) "VERIFY_FAIL_FSINFO_STRUCT" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 484))
Require ((LD-GetU32LE -Buffer $fsi -Offset 492) -eq [UInt32]3) "VERIFY_FAIL_FSINFO_NEXTFREE" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 492))
Require ((LD-GetU32LE -Buffer $fsi -Offset 508) -eq [UInt32]2857697280) "VERIFY_FAIL_FSINFO_TRAIL" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 508))
Write-Host "PASS: verify imagefile fsinfo" -ForegroundColor Green

# Backup boot must match primary boot
Require ((HexSha256Bytes $boot) -eq (HexSha256Bytes $bb)) "VERIFY_FAIL_BACKUP_BOOT_HASH" "primary vs backup mismatch"
Write-Host "PASS: verify imagefile backup boot" -ForegroundColor Green

# FAT/root structure checks via frozen hashes from known-good generation
Require ((HexSha256Bytes $fat0) -eq "250ff8a61690d4c09c669a626d66db22a1a2d090449cacd861795788674f0753") "VERIFY_FAIL_FAT0_HASH" ("actual=" + (HexSha256Bytes $fat0))
Require ((HexSha256Bytes $root0) -eq "0ed182815558442186ce83f9654856df0e182bf66abf261010ae6ebdb95a84d5") "VERIFY_FAIL_ROOT0_HASH" ("actual=" + (HexSha256Bytes $root0))
Write-Host "PASS: verify imagefile fat/root" -ForegroundColor Green

$hashes = [ordered]@{
  image = (HexSha256File $ImagePath)
  mbr = (HexSha256Bytes $mbr)
  boot = (HexSha256Bytes $boot)
  fsinfo = (HexSha256Bytes $fsi)
  backup_boot = (HexSha256Bytes $bb)
  fat0 = (HexSha256Bytes $fat0)
  root0 = (HexSha256Bytes $root0)
}
$hashesJson = ($hashes | ConvertTo-Json -Depth 20 -Compress)
Write-Host ("VERIFY_IMAGEFILE_HASHES: " + $hashesJson) -ForegroundColor Cyan

Write-Host "SELFTEST_LD_FAT32_OWNED_VERIFY_IMAGEFILE_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
