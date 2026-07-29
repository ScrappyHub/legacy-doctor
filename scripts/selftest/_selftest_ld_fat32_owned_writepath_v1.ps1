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

$RawLib    = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib   = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$VerifyPs1 = Join-Path $RepoRoot "scripts\storage\ld_verify_fat32_layout_v1.ps1"
$FormatPs1 = Join-Path $RepoRoot "scripts\storage\ld_format_fat32_owned_v1.ps1"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$VerifyPs1,$FormatPs1)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

. $RawLib
. $LayoutLib
. $BootLib

# Synthetic plan only: no live writes.
$p = LDFAT-NewPlan `
  -DiskSizeBytes 255869321216 `
  -BytesPerSector 512 `
  -DeviceId "win.disk.v1:test:synthetic" `
  -DiskNumber 99 `
  -Label "SDCARD" `
  -ClusterKiB 0

$mbr = LDFAT-BuildMbrSector $p
$boot = LDBOOT-BuildBootSector $p
$fsi = LDBOOT-BuildFsInfoSector $p
$bb = LDBOOT-BuildBackupBootSector $p
$fat0 = LDBOOT-BuildFatSector0 $p
$root0 = LDBOOT-BuildRootDirSector0 $p

Require ($mbr.Length -eq 512) "MBR_LEN_BAD" ([string]$mbr.Length)
Require ($boot.Length -eq 512) "BOOT_LEN_BAD" ([string]$boot.Length)
Require ($fsi.Length -eq 512) "FSINFO_LEN_BAD" ([string]$fsi.Length)
Require ($bb.Length -eq 512) "BACKUP_BOOT_LEN_BAD" ([string]$bb.Length)
Require ($fat0.Length -eq 512) "FAT0_LEN_BAD" ([string]$fat0.Length)
Require ($root0.Length -eq 512) "ROOT0_LEN_BAD" ([string]$root0.Length)
Write-Host "PASS: sector lengths" -ForegroundColor Green

Require ((LD-GetU16LE -Buffer $mbr -Offset 510) -eq 43605) "MBR_SIG_BAD" ("actual=" + (LD-GetU16LE -Buffer $mbr -Offset 510))
Require ((LD-GetU32LE -Buffer $mbr -Offset 454) -eq 2048) "MBR_START_BAD" ("actual=" + (LD-GetU32LE -Buffer $mbr -Offset 454))
Require ((LD-GetU32LE -Buffer $mbr -Offset 458) -gt 0) "MBR_SIZE_BAD" ("actual=" + (LD-GetU32LE -Buffer $mbr -Offset 458))
Write-Host "PASS: mbr structure" -ForegroundColor Green

Require ((LD-GetU16LE -Buffer $boot -Offset 510) -eq 43605) "BOOT_SIG_BAD" ("actual=" + (LD-GetU16LE -Buffer $boot -Offset 510))
Require ((LD-GetU16LE -Buffer $boot -Offset 11) -eq 512) "BOOT_BPS_BAD" ("actual=" + (LD-GetU16LE -Buffer $boot -Offset 11))
Require ($boot[13] -eq 64) "BOOT_SPC_BAD" ("actual=" + $boot[13])
Require ((LD-GetU16LE -Buffer $boot -Offset 14) -eq 32) "BOOT_RSV_BAD" ("actual=" + (LD-GetU16LE -Buffer $boot -Offset 14))
Require ($boot[16] -eq 2) "BOOT_FATCOUNT_BAD" ("actual=" + $boot[16])
Require ((LD-GetU32LE -Buffer $boot -Offset 44) -eq 2) "BOOT_ROOT_BAD" ("actual=" + (LD-GetU32LE -Buffer $boot -Offset 44))
Write-Host "PASS: boot structure" -ForegroundColor Green

Require ((LD-GetU32LE -Buffer $fsi -Offset 0) -eq 1096897106) "FSI_LEAD_BAD" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 0))
Require ((LD-GetU32LE -Buffer $fsi -Offset 484) -eq 1631679090) "FSI_STRUCT_BAD" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 484))
Require ((LD-GetU32LE -Buffer $fsi -Offset 492) -eq 3) "FSI_NEXT_BAD" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 492))
Require ((LD-GetU32LE -Buffer $fsi -Offset 508) -eq 2857697280) "FSI_TRAIL_BAD" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 508))
Write-Host "PASS: fsinfo structure" -ForegroundColor Green

Require ((LD-GetU32LE -Buffer $fat0 -Offset 0) -eq 268435448) "FAT0_ENTRY0_BAD" ("actual=" + (LD-GetU32LE -Buffer $fat0 -Offset 0))
Require ((LD-GetU32LE -Buffer $fat0 -Offset 4) -eq 268435455) "FAT0_ENTRY1_BAD" ("actual=" + (LD-GetU32LE -Buffer $fat0 -Offset 4))
Require ((LD-GetU32LE -Buffer $fat0 -Offset 8) -eq 268435455) "FAT0_ENTRY2_BAD" ("actual=" + (LD-GetU32LE -Buffer $fat0 -Offset 8))
Write-Host "PASS: fat sector structure" -ForegroundColor Green

$labelBytes = New-Object byte[] 11
[Array]::Copy($root0,0,$labelBytes,0,11)
$labelText = [System.Text.Encoding]::ASCII.GetString($labelBytes)
Require ($labelText -eq "SDCARD     ") "ROOT_LABEL_BAD" ("actual=[" + $labelText + "]")
Require ($root0[11] -eq 8) "ROOT_ATTR_BAD" ("actual=" + $root0[11])
Write-Host "PASS: root dir structure" -ForegroundColor Green

$hashes = [ordered]@{
  mbr = LD-Sha256Hex $mbr
  boot = LD-Sha256Hex $boot
  fsinfo = LD-Sha256Hex $fsi
  backup_boot = LD-Sha256Hex $bb
  fat0 = LD-Sha256Hex $fat0
  root0 = LD-Sha256Hex $root0
}

$hashesJson = ($hashes | ConvertTo-Json -Depth 20 -Compress)
Write-Host ("WRITEPATH_HASHES: " + $hashesJson) -ForegroundColor Cyan

Write-Host "SELFTEST_LD_FAT32_OWNED_WRITEPATH_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"