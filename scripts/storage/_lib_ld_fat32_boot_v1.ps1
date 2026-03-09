param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDBOOT-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDBOOT-Require([bool]$Condition,[string]$Code,[string]$Detail){
  if(-not $Condition){
    LDBOOT-Die $Code $Detail
  }
}

function LDBOOT-RequirePlan([hashtable]$Plan){
  if($null -eq $Plan){
    LDBOOT-Die "NULL_PLAN" "Plan"
  }

  $required = @(
    "bytes_per_sector",
    "sectors_per_cluster",
    "reserved_sectors",
    "fat_count",
    "fat_size_sectors",
    "partition_size_lba",
    "root_cluster",
    "fsinfo_sector",
    "backup_boot_sector",
    "media_descriptor",
    "volume_serial",
    "volume_label",
    "oem_name"
  )

  foreach($k in $required){
    if(-not $Plan.Contains($k)){
      LDBOOT-Die "PLAN_MISSING_KEY" $k
    }
  }
}

function LDBOOT-AsciiPadded([string]$Text,[int]$Length){
  if($Length -le 0){
    LDBOOT-Die "BAD_ARG" "Length must be > 0"
  }

  $s = ""
  if($null -ne $Text){
    $s = [string]$Text
  }

  $bytes = New-Object byte[] $Length
  for($i = 0; $i -lt $Length; $i++){
    $bytes[$i] = [byte][char]' '
  }

  $max = [Math]::Min($Length,$s.Length)
  for($i = 0; $i -lt $max; $i++){
    $ch = [int][char]$s[$i]
    if($ch -lt 32 -or $ch -gt 126){
      LDBOOT-Die "NON_ASCII_TEXT" ("offset=" + $i)
    }
    $bytes[$i] = [byte]$ch
  }

  return $bytes
}

function LDBOOT-CopyBytes([byte[]]$Buffer,[int]$Offset,[byte[]]$Bytes){
  if($null -eq $Buffer){ LDBOOT-Die "NULL_BUFFER" "Buffer" }
  if($null -eq $Bytes){ LDBOOT-Die "NULL_BYTES" "Bytes" }
  if($Offset -lt 0){ LDBOOT-Die "BAD_OFFSET" ([string]$Offset) }
  if(($Offset + $Bytes.Length) -gt $Buffer.Length){
    LDBOOT-Die "COPY_OOB" ("offset=" + $Offset + " len=" + $Bytes.Length + " buflen=" + $Buffer.Length)
  }

  [Array]::Copy($Bytes,0,$Buffer,$Offset,$Bytes.Length)
}

function LDBOOT-TotalSectors32([hashtable]$Plan){
  $total = [UInt64]$Plan["partition_size_lba"]
  if($total -gt [UInt64][UInt32]::MaxValue){
    LDBOOT-Die "TOTAL_SECTORS_TOO_LARGE" ([string]$total)
  }
  return [UInt32]$total
}

function LDBOOT-BuildBootSector([hashtable]$Plan){
  LDBOOT-RequirePlan $Plan

  if(-not (Get-Command LD-SetU16LE -ErrorAction SilentlyContinue)){
    LDBOOT-Die "MISSING_DEP" "LD-SetU16LE not loaded; dot-source _lib_ld_rawdisk_v1.ps1 first"
  }
  if(-not (Get-Command LD-SetU32LE -ErrorAction SilentlyContinue)){
    LDBOOT-Die "MISSING_DEP" "LD-SetU32LE not loaded; dot-source _lib_ld_rawdisk_v1.ps1 first"
  }

  $bps = [UInt16]$Plan["bytes_per_sector"]
  $spc = [byte]([UInt32]$Plan["sectors_per_cluster"])
  $rsv = [UInt16]$Plan["reserved_sectors"]
  $fatCount = [byte]([UInt16]$Plan["fat_count"])
  $fatSize = [UInt32]$Plan["fat_size_sectors"]
  $rootCluster = [UInt32]$Plan["root_cluster"]
  $fsInfoSector = [UInt16]$Plan["fsinfo_sector"]
  $backupBootSector = [UInt16]$Plan["backup_boot_sector"]
  $mediaDescriptor = [byte]$Plan["media_descriptor"]
  $volumeSerial = [UInt32]$Plan["volume_serial"]
  $label = [string]$Plan["volume_label"]
  $oem = [string]$Plan["oem_name"]
  $totalSectors32 = LDBOOT-TotalSectors32 $Plan

  LDBOOT-Require($bps -eq 512) "UNSUPPORTED_BPS" ([string]$bps)
  LDBOOT-Require(@(1,2,4,8,16,32,64,128) -contains [int]$spc) "BAD_SPC" ([string]$spc)
  LDBOOT-Require($rootCluster -eq 2) "BAD_ROOT_CLUSTER" ([string]$rootCluster)
  LDBOOT-Require($fatCount -eq 2) "BAD_FAT_COUNT" ([string]$fatCount)

  $sector = New-Object byte[] 512

  # Jump + OEM
  $sector[0] = [byte]0xEB
  $sector[1] = [byte]0x58
  $sector[2] = [byte]0x90
  LDBOOT-CopyBytes -Buffer $sector -Offset 3 -Bytes (LDBOOT-AsciiPadded -Text $oem -Length 8)

  # BPB
  LD-SetU16LE -Buffer $sector -Offset 11 -Value $bps
  $sector[13] = $spc
  LD-SetU16LE -Buffer $sector -Offset 14 -Value $rsv
  $sector[16] = $fatCount
  LD-SetU16LE -Buffer $sector -Offset 17 -Value 0      # RootEntCnt
  LD-SetU16LE -Buffer $sector -Offset 19 -Value 0      # TotSec16
  $sector[21] = $mediaDescriptor
  LD-SetU16LE -Buffer $sector -Offset 22 -Value 0      # FATSz16
  LD-SetU16LE -Buffer $sector -Offset 24 -Value 63     # SecPerTrk placeholder
  LD-SetU16LE -Buffer $sector -Offset 26 -Value 255    # NumHeads placeholder
  LD-SetU32LE -Buffer $sector -Offset 28 -Value 2048   # HiddenSectors
  LD-SetU32LE -Buffer $sector -Offset 32 -Value $totalSectors32

  # FAT32 extended BPB
  LD-SetU32LE -Buffer $sector -Offset 36 -Value $fatSize
  LD-SetU16LE -Buffer $sector -Offset 40 -Value 0      # ExtFlags
  LD-SetU16LE -Buffer $sector -Offset 42 -Value 0      # FSVer
  LD-SetU32LE -Buffer $sector -Offset 44 -Value $rootCluster
  LD-SetU16LE -Buffer $sector -Offset 48 -Value $fsInfoSector
  LD-SetU16LE -Buffer $sector -Offset 50 -Value $backupBootSector

  # Reserved 12 bytes 52..63 left zero
  $sector[64] = [byte]0x80                              # Drive number
  $sector[65] = [byte]0x00                              # Reserved
  $sector[66] = [byte]0x29                              # Boot signature
  LD-SetU32LE -Buffer $sector -Offset 67 -Value $volumeSerial
  LDBOOT-CopyBytes -Buffer $sector -Offset 71 -Bytes (LDBOOT-AsciiPadded -Text $label -Length 11)
  LDBOOT-CopyBytes -Buffer $sector -Offset 82 -Bytes (LDBOOT-AsciiPadded -Text "FAT32" -Length 8)

  # Minimal boot code area left zeroed
  LD-SetU16LE -Buffer $sector -Offset 510 -Value 0xAA55

  return $sector
}

function LDBOOT-BuildFsInfoSector([hashtable]$Plan){
  LDBOOT-RequirePlan $Plan

  if(-not (Get-Command LD-SetU16LE -ErrorAction SilentlyContinue)){
    LDBOOT-Die "MISSING_DEP" "LD-SetU16LE not loaded; dot-source _lib_ld_rawdisk_v1.ps1 first"
  }
  if(-not (Get-Command LD-SetU32LE -ErrorAction SilentlyContinue)){
    LDBOOT-Die "MISSING_DEP" "LD-SetU32LE not loaded; dot-source _lib_ld_rawdisk_v1.ps1 first"
  }

  $clusterCount = [UInt64]$Plan["cluster_count"]
  $freeClusters = [UInt32]($clusterCount - 1)   # root cluster allocated
  $nextFree = [UInt32]3

  $sector = New-Object byte[] 512

  LD-SetU32LE -Buffer $sector -Offset 0   -Value 0x41615252
  LD-SetU32LE -Buffer $sector -Offset 484 -Value 0x61417272
  LD-SetU32LE -Buffer $sector -Offset 488 -Value $freeClusters
  LD-SetU32LE -Buffer $sector -Offset 492 -Value $nextFree
  LD-SetU32LE -Buffer $sector -Offset 508 -Value 0xAA550000

  return $sector
}

function LDBOOT-BuildBackupBootSector([hashtable]$Plan){
  return (LDBOOT-BuildBootSector -Plan $Plan)
}

function LDBOOT-BuildFatSector0([hashtable]$Plan){
  LDBOOT-RequirePlan $Plan

  if(-not (Get-Command LD-SetU32LE -ErrorAction SilentlyContinue)){
    LDBOOT-Die "MISSING_DEP" "LD-SetU32LE not loaded; dot-source _lib_ld_rawdisk_v1.ps1 first"
  }

  $mediaDescriptor = [byte]$Plan["media_descriptor"]
  $rootCluster = [UInt32]$Plan["root_cluster"]

  $sector = New-Object byte[] 512

  # FAT32 entry 0: media descriptor + reserved high bits
  $entry0 = [UInt32](0x0FFFFF00 -bor $mediaDescriptor)
  # FAT32 entry 1: reserved
  $entry1 = [UInt32]0x0FFFFFFF
  # FAT32 entry 2/root cluster: end-of-chain
  $entry2 = [UInt32]0x0FFFFFFF

  LD-SetU32LE -Buffer $sector -Offset 0 -Value $entry0
  LD-SetU32LE -Buffer $sector -Offset 4 -Value $entry1

  $rootOffset = [int]($rootCluster * 4)
  LD-SetU32LE -Buffer $sector -Offset $rootOffset -Value $entry2

  return $sector
}

function LDBOOT-BuildRootDirSector0([hashtable]$Plan){
  LDBOOT-RequirePlan $Plan

  $sector = New-Object byte[] 512
  $label = [string]$Plan["volume_label"]
  $labelBytes = LDBOOT-AsciiPadded -Text $label -Length 11

  # Volume label directory entry
  LDBOOT-CopyBytes -Buffer $sector -Offset 0 -Bytes $labelBytes
  $sector[11] = [byte]0x08

  return $sector
}

function LDBOOT-ExportModuleInfo {
  return [ordered]@{
    schema = "ld.fat32.boot.lib.info.v1"
    name = "_lib_ld_fat32_boot_v1.ps1"
    provides = @(
      "LDBOOT-BuildBootSector",
      "LDBOOT-BuildFsInfoSector",
      "LDBOOT-BuildBackupBootSector",
      "LDBOOT-BuildFatSector0",
      "LDBOOT-BuildRootDirSector0",
      "LDBOOT-ExportModuleInfo"
    )
    profile = [ordered]@{
      fat_type = "FAT32"
      bytes_per_sector = 512
      fsinfo_sector = 1
      backup_boot_sector = 6
      root_cluster = 2
      fat_count = 2
    }
  }
}
