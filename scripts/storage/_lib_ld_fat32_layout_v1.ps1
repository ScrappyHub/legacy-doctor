param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDFAT-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDFAT-Require([bool]$Condition,[string]$Code,[string]$Detail){
  if(-not $Condition){
    LDFAT-Die $Code $Detail
  }
}

function LDFAT-RequirePositiveInt([string]$Name,[int]$Value){
  if($Value -le 0){
    LDFAT-Die "BAD_ARG" ($Name + " must be > 0")
  }
}

function LDFAT-RequirePositiveUInt64([string]$Name,[UInt64]$Value){
  if($Value -eq 0){
    LDFAT-Die "BAD_ARG" ($Name + " must be > 0")
  }
}

function LDFAT-UpperAsciiLabel([string]$Label){
  $x = ""
  if(-not [string]::IsNullOrWhiteSpace($Label)){
    $x = [string]$Label
  } else {
    $x = "SDCARD"
  }

  $x = $x.ToUpperInvariant()
  $x = ($x -replace '[^A-Z0-9_\-]','')

  if([string]::IsNullOrWhiteSpace($x)){
    $x = "SDCARD"
  }

  if($x.Length -gt 11){
    $x = $x.Substring(0,11)
  }

  return $x
}

function LDFAT-UInt32FromSha256Prefix([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes($Text)

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }

  return [UInt32](
    $h[0] -bor
    ($h[1] -shl 8) -bor
    ($h[2] -shl 16) -bor
    ($h[3] -shl 24)
  )
}

function LDFAT-AlignUp([UInt64]$Value,[UInt64]$Alignment){
  if($Alignment -eq 0){
    LDFAT-Die "BAD_ARG" "Alignment must be > 0"
  }

  $r = $Value % $Alignment
  if($r -eq 0){
    return $Value
  }

  return ($Value + ($Alignment - $r))
}

function LDFAT-ChooseSectorsPerCluster(
  [UInt64]$PartitionSizeBytes,
  [int]$BytesPerSector,
  [int]$ClusterKiB
){
  LDFAT-RequirePositiveUInt64 "PartitionSizeBytes" $PartitionSizeBytes
  LDFAT-RequirePositiveInt "BytesPerSector" $BytesPerSector

  if($ClusterKiB -gt 0){
    $clusterBytes = ([UInt64]$ClusterKiB) * ([UInt64]1024)

    if(($clusterBytes % [UInt64]$BytesPerSector) -ne 0){
      LDFAT-Die "BAD_CLUSTER_SIZE" ("ClusterKiB=" + $ClusterKiB + " not aligned to sector size " + $BytesPerSector)
    }

    $spc = [int]($clusterBytes / [UInt64]$BytesPerSector)

    if(@(1,2,4,8,16,32,64,128) -notcontains $spc){
      LDFAT-Die "BAD_CLUSTER_SIZE" ("unsupported sectors/cluster=" + $spc)
    }

    return $spc
  }

  $giB = [double]$PartitionSizeBytes / 1GB

  if($giB -le 32.0){
    $clusterBytes = [UInt64](32KB)
  } elseif($giB -le 512.0){
    $clusterBytes = [UInt64](32KB)
  } else {
    LDFAT-Die "PARTITION_TOO_LARGE" ("Tier-0 profile currently supports up to 512GiB; got " + [string]$giB + " GiB")
  }

  if(($clusterBytes % [UInt64]$BytesPerSector) -ne 0){
    LDFAT-Die "BAD_CLUSTER_SIZE" ("clusterBytes=" + $clusterBytes + " not aligned to sector size " + $BytesPerSector)
  }

  $spc2 = [int]($clusterBytes / [UInt64]$BytesPerSector)

  if(@(1,2,4,8,16,32,64,128) -notcontains $spc2){
    LDFAT-Die "BAD_CLUSTER_SIZE" ("unsupported sectors/cluster=" + $spc2)
  }

  return $spc2
}

function LDFAT-ComputeFatSizeSectors(
  [UInt64]$PartitionSectors,
  [UInt32]$ReservedSectors,
  [UInt32]$SectorsPerCluster,
  [UInt32]$FatCount
){
  LDFAT-Require($PartitionSectors -gt 0) "BAD_ARG" "PartitionSectors must be > 0"
  LDFAT-Require($ReservedSectors -gt 0) "BAD_ARG" "ReservedSectors must be > 0"
  LDFAT-Require($SectorsPerCluster -gt 0) "BAD_ARG" "SectorsPerCluster must be > 0"
  LDFAT-Require($FatCount -gt 0) "BAD_ARG" "FatCount must be > 0"

  $fatSz = [UInt64]1

  for($i = 0; $i -lt 32; $i++){
    $dataSectors = $PartitionSectors - [UInt64]$ReservedSectors - (([UInt64]$FatCount) * $fatSz)
    LDFAT-Require($dataSectors -gt 0) "LAYOUT_INVALID" "data sectors <= 0"

    $clusterCount = [UInt64][Math]::Floor([double]$dataSectors / [double]$SectorsPerCluster)
    $fatBytes = ($clusterCount + [UInt64]2) * [UInt64]4
    $newFatSz = [UInt64][Math]::Ceiling([double]$fatBytes / 512.0)

    if($newFatSz -eq $fatSz){
      return $fatSz
    }

    $fatSz = $newFatSz
  }

  return $fatSz
}

function LDFAT-ComputeClusterCount(
  [UInt64]$PartitionSectors,
  [UInt32]$ReservedSectors,
  [UInt32]$FatCount,
  [UInt32]$FatSizeSectors,
  [UInt32]$SectorsPerCluster
){
  $dataSectors = $PartitionSectors - [UInt64]$ReservedSectors - (([UInt64]$FatCount) * ([UInt64]$FatSizeSectors))
  LDFAT-Require($dataSectors -gt 0) "LAYOUT_INVALID" "data sectors <= 0"

  return [UInt64][Math]::Floor([double]$dataSectors / [double]$SectorsPerCluster)
}

function LDFAT-NewPlan(
  [UInt64]$DiskSizeBytes,
  [int]$BytesPerSector,
  [string]$DeviceId,
  [int]$DiskNumber,
  [string]$Label,
  [int]$ClusterKiB
){
  LDFAT-RequirePositiveUInt64 "DiskSizeBytes" $DiskSizeBytes
  LDFAT-RequirePositiveInt "BytesPerSector" $BytesPerSector
  LDFAT-Require($BytesPerSector -eq 512) "UNSUPPORTED_BPS" ("Tier-0 currently locks bytes/sector=512; got " + $BytesPerSector)

  $partitionStyle    = "MBR"
  $partitionTypeHex  = "0x0C"
  $partitionType     = 12
  $partitionStartLba = [UInt64]2048
  $fatCount          = [UInt32]2
  $reservedSectors   = [UInt32]32
  $rootCluster       = [UInt32]2
  $fsInfoSector      = [UInt16]1
  $backupBootSector  = [UInt16]6
  $mediaDescriptor   = [byte]0xF8
  $oemName           = "MSWIN4.1"
  $volumeLabel       = LDFAT-UpperAsciiLabel $Label

  $diskSectors = [UInt64][Math]::Floor([double]$DiskSizeBytes / [double]$BytesPerSector)
  LDFAT-Require($diskSectors -gt $partitionStartLba) "DISK_TOO_SMALL" ("disk sectors=" + $diskSectors)

  $partitionSectors = $diskSectors - $partitionStartLba
  LDFAT-Require($partitionSectors -gt 65536) "DISK_TOO_SMALL" "partition sectors too small for FAT32 profile"

  $partitionSizeBytes = $partitionSectors * [UInt64]$BytesPerSector

  $sectorsPerCluster = [UInt32](LDFAT-ChooseSectorsPerCluster `
    -PartitionSizeBytes $partitionSizeBytes `
    -BytesPerSector $BytesPerSector `
    -ClusterKiB $ClusterKiB)

  $clusterSizeBytes = [UInt64]$sectorsPerCluster * [UInt64]$BytesPerSector

  $fatSizeSectors = [UInt32](LDFAT-ComputeFatSizeSectors `
    -PartitionSectors $partitionSectors `
    -ReservedSectors $reservedSectors `
    -SectorsPerCluster $sectorsPerCluster `
    -FatCount $fatCount)

  $clusterCount = LDFAT-ComputeClusterCount `
    -PartitionSectors $partitionSectors `
    -ReservedSectors $reservedSectors `
    -FatCount $fatCount `
    -FatSizeSectors $fatSizeSectors `
    -SectorsPerCluster $sectorsPerCluster

  LDFAT-Require($clusterCount -ge 65525) "NOT_FAT32_GEOMETRY" ("cluster_count=" + $clusterCount)

  $dataStartLba = $partitionStartLba + [UInt64]$reservedSectors + (([UInt64]$fatCount) * ([UInt64]$fatSizeSectors))
  $rootDirFirstLba = $dataStartLba

  $serialSeed = ("fat32|disk_number=" + $DiskNumber + "|device_id=" + $DeviceId + "|partition_start_lba=" + $partitionStartLba + "|partition_size_lba=" + $partitionSectors + "|label=" + $volumeLabel)
  $volumeSerial = LDFAT-UInt32FromSha256Prefix $serialSeed

  return [ordered]@{
    schema = "ld.fat32.plan.v1"

    disk_number = [int]$DiskNumber
    device_id = [string]$DeviceId
    disk_size_bytes = [UInt64]$DiskSizeBytes
    bytes_per_sector = [UInt16]$BytesPerSector

    partition_style = $partitionStyle
    partition_type_hex = $partitionTypeHex
    partition_type = [byte]$partitionType
    partition_start_lba = [UInt64]$partitionStartLba
    partition_size_lba = [UInt64]$partitionSectors
    partition_size_bytes = [UInt64]$partitionSizeBytes

    fat_type = "FAT32"
    sectors_per_cluster = [UInt32]$sectorsPerCluster
    cluster_size_bytes = [UInt64]$clusterSizeBytes
    reserved_sectors = [UInt16]$reservedSectors
    fat_count = [UInt16]$fatCount
    fat_size_sectors = [UInt32]$fatSizeSectors
    cluster_count = [UInt64]$clusterCount
    root_cluster = [UInt32]$rootCluster
    fsinfo_sector = [UInt16]$fsInfoSector
    backup_boot_sector = [UInt16]$backupBootSector
    media_descriptor = [byte]$mediaDescriptor
    oem_name = $oemName
    volume_label = $volumeLabel
    volume_serial = [UInt32]$volumeSerial

    fat1_start_lba = [UInt64]($partitionStartLba + [UInt64]$reservedSectors)
    fat2_start_lba = [UInt64]($partitionStartLba + [UInt64]$reservedSectors + [UInt64]$fatSizeSectors)
    data_start_lba = [UInt64]$dataStartLba
    root_dir_first_lba = [UInt64]$rootDirFirstLba

    ok = $true
  }
}

function LDFAT-PlanSummary([hashtable]$Plan){
  if($null -eq $Plan){
    LDFAT-Die "NULL_PLAN" "Plan"
  }

  return [pscustomobject]@{
    DiskNumber        = [int]$Plan["disk_number"]
    DeviceId          = [string]$Plan["device_id"]
    PartitionStyle    = [string]$Plan["partition_style"]
    PartitionType     = [string]$Plan["partition_type_hex"]
    StartLba          = [UInt64]$Plan["partition_start_lba"]
    SizeLba           = [UInt64]$Plan["partition_size_lba"]
    BytesPerSector    = [UInt16]$Plan["bytes_per_sector"]
    SectorsPerCluster = [UInt32]$Plan["sectors_per_cluster"]
    ClusterSizeBytes  = [UInt64]$Plan["cluster_size_bytes"]
    ReservedSectors   = [UInt16]$Plan["reserved_sectors"]
    FatCount          = [UInt16]$Plan["fat_count"]
    FatSizeSectors    = [UInt32]$Plan["fat_size_sectors"]
    ClusterCount      = [UInt64]$Plan["cluster_count"]
    RootCluster       = [UInt32]$Plan["root_cluster"]
    Label             = [string]$Plan["volume_label"]
    VolumeSerial      = ("0x" + ([UInt32]$Plan["volume_serial"]).ToString("X8"))
  }
}

function LDFAT-BuildMbrSector([hashtable]$Plan){
  if($null -eq $Plan){
    LDFAT-Die "NULL_PLAN" "Plan"
  }

  if(-not (Get-Command LD-SetU32LE -ErrorAction SilentlyContinue)){
    LDFAT-Die "MISSING_DEP" "LD-SetU32LE not loaded; dot-source _lib_ld_rawdisk_v1.ps1 first"
  }
  if(-not (Get-Command LD-SetU16LE -ErrorAction SilentlyContinue)){
    LDFAT-Die "MISSING_DEP" "LD-SetU16LE not loaded; dot-source _lib_ld_rawdisk_v1.ps1 first"
  }

  $sector = New-Object byte[] 512

  $entryOffset = 446
  $startOffset = 454
  $sizeOffset  = 458
  $sigOffset   = 510

  $partitionType = [byte]([int]$Plan["partition_type"])
  $start64 = [UInt64]$Plan["partition_start_lba"]
  $size64  = [UInt64]$Plan["partition_size_lba"]

  if($start64 -gt [UInt64][UInt32]::MaxValue){
    LDFAT-Die "MBR_START_TOO_LARGE" ([string]$start64)
  }
  if($size64 -gt [UInt64][UInt32]::MaxValue){
    LDFAT-Die "MBR_SIZE_TOO_LARGE" ([string]$size64)
  }

  $start32 = [UInt32]$start64
  $size32  = [UInt32]$size64

  $sector[$entryOffset + 0] = [byte]0x00
  $sector[$entryOffset + 1] = [byte]0x00
  $sector[$entryOffset + 2] = [byte]0x02
  $sector[$entryOffset + 3] = [byte]0x00
  $sector[$entryOffset + 4] = $partitionType
  $sector[$entryOffset + 5] = [byte]0xFE
  $sector[$entryOffset + 6] = [byte]0xFF
  $sector[$entryOffset + 7] = [byte]0xFF

  LD-SetU32LE -Buffer $sector -Offset $startOffset -Value $start32
  LD-SetU32LE -Buffer $sector -Offset $sizeOffset  -Value $size32
  LD-SetU16LE -Buffer $sector -Offset $sigOffset   -Value 0xAA55

  return $sector
}

function LDFAT-ExportModuleInfo {
  return [ordered]@{
    schema = "ld.fat32.layout.lib.info.v1"
    name = "_lib_ld_fat32_layout_v1.ps1"
    provides = @(
      "LDFAT-UpperAsciiLabel",
      "LDFAT-ChooseSectorsPerCluster",
      "LDFAT-NewPlan",
      "LDFAT-PlanSummary",
      "LDFAT-BuildMbrSector",
      "LDFAT-ExportModuleInfo"
    )
    profile = [ordered]@{
      fat_type = "FAT32"
      bytes_per_sector = 512
      partition_style = "MBR"
      partition_type_hex = "0x0C"
      partition_start_lba = 2048
      fat_count = 2
      reserved_sectors = 32
      root_cluster = 2
      fsinfo_sector = 1
      backup_boot_sector = 6
    }
  }
}
