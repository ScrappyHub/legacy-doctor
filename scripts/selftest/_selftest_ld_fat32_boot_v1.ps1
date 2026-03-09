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

function Require([bool]$Condition,[string]$Code,[string]$Detail){
  if(-not $Condition){
    Die $Code $Detail
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RawLib    = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib   = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"

Parse-GateFile $RawLib
Write-Host ("PARSE_OK: " + $RawLib) -ForegroundColor DarkGray

Parse-GateFile $LayoutLib
Write-Host ("PARSE_OK: " + $LayoutLib) -ForegroundColor DarkGray

Parse-GateFile $BootLib
Write-Host ("PARSE_OK: " + $BootLib) -ForegroundColor DarkGray

. $RawLib
. $LayoutLib
. $BootLib

$rawInfo = LD-ExportModuleInfo
$layoutInfo = LDFAT-ExportModuleInfo
$bootInfo = LDBOOT-ExportModuleInfo

Require ($rawInfo.schema -eq "ld.rawdisk.lib.info.v1") "RAW_INFO_SCHEMA_BAD" ([string]$rawInfo.schema)
Require ($layoutInfo.schema -eq "ld.fat32.layout.lib.info.v1") "LAYOUT_INFO_SCHEMA_BAD" ([string]$layoutInfo.schema)
Require ($bootInfo.schema -eq "ld.fat32.boot.lib.info.v1") "BOOT_INFO_SCHEMA_BAD" ([string]$bootInfo.schema)
Write-Host "PASS: module export schemas" -ForegroundColor Green

$p = LDFAT-NewPlan `
  -DiskSizeBytes 255869321216 `
  -BytesPerSector 512 `
  -DeviceId "win.disk.v1:test:synthetic" `
  -DiskNumber 99 `
  -Label "SDCARD" `
  -ClusterKiB 0

$bs = LDBOOT-BuildBootSector $p

Require ((LD-GetU16LE -Buffer $bs -Offset 510) -eq 43605) "BOOT_SIG_BAD" ("actual=" + (LD-GetU16LE -Buffer $bs -Offset 510))
Require ((LD-GetU16LE -Buffer $bs -Offset 11) -eq 512) "BOOT_BPS_BAD" ("actual=" + (LD-GetU16LE -Buffer $bs -Offset 11))
Require ($bs[13] -eq 64) "BOOT_SPC_BAD" ("actual=" + $bs[13])
Require ((LD-GetU16LE -Buffer $bs -Offset 14) -eq 32) "BOOT_RSV_BAD" ("actual=" + (LD-GetU16LE -Buffer $bs -Offset 14))
Require ($bs[16] -eq 2) "BOOT_FATCOUNT_BAD" ("actual=" + $bs[16])
Require ((LD-GetU32LE -Buffer $bs -Offset 44) -eq 2) "BOOT_ROOT_BAD" ("actual=" + (LD-GetU32LE -Buffer $bs -Offset 44))
Require ((LD-GetU16LE -Buffer $bs -Offset 48) -eq 1) "BOOT_FSINFO_BAD" ("actual=" + (LD-GetU16LE -Buffer $bs -Offset 48))
Require ((LD-GetU16LE -Buffer $bs -Offset 50) -eq 6) "BOOT_BACKUP_BAD" ("actual=" + (LD-GetU16LE -Buffer $bs -Offset 50))
Write-Host "PASS: boot sector fields" -ForegroundColor Green

$fi = LDBOOT-BuildFsInfoSector $p

Require ((LD-GetU32LE -Buffer $fi -Offset 0) -eq 1096897106) "FSINFO_LEAD_BAD" ("actual=" + (LD-GetU32LE -Buffer $fi -Offset 0))
Require ((LD-GetU32LE -Buffer $fi -Offset 484) -eq 1631679090) "FSINFO_STRUCT_BAD" ("actual=" + (LD-GetU32LE -Buffer $fi -Offset 484))
Require ((LD-GetU32LE -Buffer $fi -Offset 492) -eq 3) "FSINFO_NEXT_BAD" ("actual=" + (LD-GetU32LE -Buffer $fi -Offset 492))
Require ((LD-GetU32LE -Buffer $fi -Offset 508) -eq 2857697280) "FSINFO_TRAIL_BAD" ("actual=" + (LD-GetU32LE -Buffer $fi -Offset 508))
Write-Host "PASS: fsinfo sector fields" -ForegroundColor Green

$bb = LDBOOT-BuildBackupBootSector $p
Require ((LD-GetU16LE -Buffer $bb -Offset 510) -eq 43605) "BACKUP_BOOT_SIG_BAD" ("actual=" + (LD-GetU16LE -Buffer $bb -Offset 510))
Require ((LD-GetU16LE -Buffer $bb -Offset 11) -eq 512) "BACKUP_BOOT_BPS_BAD" ("actual=" + (LD-GetU16LE -Buffer $bb -Offset 11))
Write-Host "PASS: backup boot sector fields" -ForegroundColor Green

$fat0 = LDBOOT-BuildFatSector0 $p
Require ((LD-GetU32LE -Buffer $fat0 -Offset 0) -eq 268435448) "FAT0_ENTRY0_BAD" ("actual=" + (LD-GetU32LE -Buffer $fat0 -Offset 0))
Require ((LD-GetU32LE -Buffer $fat0 -Offset 4) -eq 268435455) "FAT0_ENTRY1_BAD" ("actual=" + (LD-GetU32LE -Buffer $fat0 -Offset 4))
Require ((LD-GetU32LE -Buffer $fat0 -Offset 8) -eq 268435455) "FAT0_ROOT_BAD" ("actual=" + (LD-GetU32LE -Buffer $fat0 -Offset 8))
Write-Host "PASS: FAT sector 0 fields" -ForegroundColor Green

$root0 = LDBOOT-BuildRootDirSector0 $p
Require ($root0[11] -eq 8) "ROOTDIR_ATTR_BAD" ("actual=" + $root0[11])
$labelBytes = New-Object byte[] 11
[Array]::Copy($root0,0,$labelBytes,0,11)
$labelText = [System.Text.Encoding]::ASCII.GetString($labelBytes)
Require ($labelText -eq "SDCARD     ") "ROOTDIR_LABEL_BAD" ("actual=[" + $labelText + "]")
Write-Host "PASS: root dir sector fields" -ForegroundColor Green

$planHash = LD-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes(($p | ConvertTo-Json -Depth 50 -Compress)))
Write-Host ("BOOT_PLAN_HASH: " + $planHash) -ForegroundColor Cyan

Write-Host "SELFTEST_LD_FAT32_BOOT_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
