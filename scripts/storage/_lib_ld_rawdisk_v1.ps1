param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LD-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LD-RequireAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    LD-Die "ADMIN_REQUIRED" "raw disk access requires elevated PowerShell"
  }
}

function LD-RequirePositiveInt([string]$Name,[int]$Value){
  if($Value -lt 0){
    LD-Die "BAD_ARG" ($Name + " must be >= 0")
  }
}

function LD-RequirePositiveLong([string]$Name,[Int64]$Value){
  if($Value -lt 0){
    LD-Die "BAD_ARG" ($Name + " must be >= 0")
  }
}

function LD-RequireMultipleOf([string]$Name,[Int64]$Value,[Int64]$Multiple){
  if($Multiple -le 0){
    LD-Die "BAD_ARG" ("invalid multiple for " + $Name)
  }
  if(($Value % $Multiple) -ne 0){
    LD-Die "BAD_ALIGNMENT" ($Name + "=" + $Value + " not multiple of " + $Multiple)
  }
}

function LD-NewByteArray([int]$Length){
  if($Length -lt 0){
    LD-Die "BAD_ARG" ("Length must be >= 0")
  }
  return (New-Object byte[] $Length)
}

function LD-AsciiBytes([string]$Text,[int]$Length){
  if($Length -lt 0){
    LD-Die "BAD_ARG" "Length must be >= 0"
  }
  $buf = New-Object byte[] $Length
  $enc = [System.Text.Encoding]::ASCII
  $src = $enc.GetBytes($Text)
  $n = [Math]::Min($src.Length,$Length)
  if($n -gt 0){
    [Array]::Copy($src,0,$buf,0,$n)
  }
  return $buf
}

function LD-Utf8Bytes([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  return $enc.GetBytes($Text)
}

function LD-BytesToHex([byte[]]$Bytes){
  if($null -eq $Bytes){
    return ""
  }
  $sb = New-Object System.Text.StringBuilder
  foreach($b in $Bytes){
    [void]$sb.AppendFormat("{0:x2}", $b)
  }
  return $sb.ToString()
}

function LD-Sha256Hex([byte[]]$Bytes){
  if($null -eq $Bytes){
    $Bytes = New-Object byte[] 0
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }
  return (LD-BytesToHex $hash)
}

function LD-SetU16LE([byte[]]$Buffer,[int]$Offset,[UInt16]$Value){
  if($null -eq $Buffer){ LD-Die "NULL_BUFFER" "Buffer" }
  if($Offset -lt 0 -or ($Offset + 2) -gt $Buffer.Length){
    LD-Die "OFFSET_OOB" ("Offset=" + $Offset + " len=" + $Buffer.Length)
  }
  $Buffer[$Offset + 0] = [byte]($Value -band 0xFF)
  $Buffer[$Offset + 1] = [byte](($Value -shr 8) -band 0xFF)
}

function LD-SetU32LE([byte[]]$Buffer,[int]$Offset,[UInt32]$Value){
  if($null -eq $Buffer){ LD-Die "NULL_BUFFER" "Buffer" }
  if($Offset -lt 0 -or ($Offset + 4) -gt $Buffer.Length){
    LD-Die "OFFSET_OOB" ("Offset=" + $Offset + " len=" + $Buffer.Length)
  }
  $Buffer[$Offset + 0] = [byte]($Value -band 0xFF)
  $Buffer[$Offset + 1] = [byte](($Value -shr 8) -band 0xFF)
  $Buffer[$Offset + 2] = [byte](($Value -shr 16) -band 0xFF)
  $Buffer[$Offset + 3] = [byte](($Value -shr 24) -band 0xFF)
}

function LD-SetBytes([byte[]]$Buffer,[int]$Offset,[byte[]]$Data){
  if($null -eq $Buffer){ LD-Die "NULL_BUFFER" "Buffer" }
  if($null -eq $Data){ LD-Die "NULL_DATA" "Data" }
  if($Offset -lt 0 -or ($Offset + $Data.Length) -gt $Buffer.Length){
    LD-Die "OFFSET_OOB" ("Offset=" + $Offset + " dataLen=" + $Data.Length + " bufLen=" + $Buffer.Length)
  }
  [Array]::Copy($Data,0,$Buffer,$Offset,$Data.Length)
}

function LD-GetU16LE([byte[]]$Buffer,[int]$Offset){
  if($null -eq $Buffer){ LD-Die "NULL_BUFFER" "Buffer" }
  if($Offset -lt 0 -or ($Offset + 2) -gt $Buffer.Length){
    LD-Die "OFFSET_OOB" ("Offset=" + $Offset + " len=" + $Buffer.Length)
  }
  return [UInt16]($Buffer[$Offset] -bor ($Buffer[$Offset + 1] -shl 8))
}

function LD-GetU32LE([byte[]]$Buffer,[int]$Offset){
  if($null -eq $Buffer){ LD-Die "NULL_BUFFER" "Buffer" }
  if($Offset -lt 0 -or ($Offset + 4) -gt $Buffer.Length){
    LD-Die "OFFSET_OOB" ("Offset=" + $Offset + " len=" + $Buffer.Length)
  }
  return [UInt32](
    $Buffer[$Offset + 0] -bor
    ($Buffer[$Offset + 1] -shl 8) -bor
    ($Buffer[$Offset + 2] -shl 16) -bor
    ($Buffer[$Offset + 3] -shl 24)
  )
}

function LD-GetDiskPath([int]$DiskNumber){
  LD-RequirePositiveInt "DiskNumber" $DiskNumber
  return ("\\.\PhysicalDrive" + $DiskNumber)
}

function LD-OpenRawDiskRead([int]$DiskNumber){
  LD-RequireAdmin
  $path = LD-GetDiskPath $DiskNumber
  try {
    return (New-Object System.IO.FileStream(
      $path,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::ReadWrite
    ))
  } catch {
    LD-Die "RAW_OPEN_READ_FAIL" ($path + " :: " + $_.Exception.Message)
  }
}

function LD-OpenRawDiskReadWrite([int]$DiskNumber){
  LD-RequireAdmin
  $path = LD-GetDiskPath $DiskNumber
  try {
    return (New-Object System.IO.FileStream(
      $path,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::ReadWrite
    ))
  } catch {
    LD-Die "RAW_OPEN_RW_FAIL" ($path + " :: " + $_.Exception.Message)
  }
}

function LD-CloseStream($Stream){
  if($null -ne $Stream){
    try { $Stream.Dispose() } catch { }
  }
}

function LD-GetDiskSectorSize([int]$DiskNumber){
  LD-RequirePositiveInt "DiskNumber" $DiskNumber
  try {
    $d = Get-Disk -Number $DiskNumber -ErrorAction Stop
    $bps = 512
    try {
      if($d.LogicalSectorSize -gt 0){
        $bps = [int]$d.LogicalSectorSize
      }
    } catch {
      $bps = 512
    }
    return $bps
  } catch {
    LD-Die "DISK_LOOKUP_FAIL" ("DiskNumber=" + $DiskNumber + " :: " + $_.Exception.Message)
  }
}

function LD-ReadBytes([System.IO.FileStream]$Stream,[Int64]$Offset,[int]$Count){
  if($null -eq $Stream){ LD-Die "NULL_STREAM" "Stream" }
  LD-RequirePositiveLong "Offset" $Offset
  if($Count -lt 0){ LD-Die "BAD_ARG" "Count must be >= 0" }

  $buf = New-Object byte[] $Count
  try {
    [void]$Stream.Seek($Offset,[System.IO.SeekOrigin]::Begin)
    $read = 0
    while($read -lt $Count){
      $n = $Stream.Read($buf,$read,$Count - $read)
      if($n -le 0){
        LD-Die "SHORT_READ" ("expected=" + $Count + " actual=" + $read + " offset=" + $Offset)
      }
      $read += $n
    }
    return $buf
  } catch {
    if($_.Exception.Message -like "SHORT_READ*"){ throw }
    LD-Die "READ_FAIL" ("offset=" + $Offset + " count=" + $Count + " :: " + $_.Exception.Message)
  }
}

function LD-WriteBytes([System.IO.FileStream]$Stream,[Int64]$Offset,[byte[]]$Bytes){
  if($null -eq $Stream){ LD-Die "NULL_STREAM" "Stream" }
  if($null -eq $Bytes){ LD-Die "NULL_BYTES" "Bytes" }
  LD-RequirePositiveLong "Offset" $Offset
  try {
    [void]$Stream.Seek($Offset,[System.IO.SeekOrigin]::Begin)
    $Stream.Write($Bytes,0,$Bytes.Length)
    $Stream.Flush()
  } catch {
    LD-Die "WRITE_FAIL" ("offset=" + $Offset + " count=" + $Bytes.Length + " :: " + $_.Exception.Message)
  }
}

function LD-ReadSectors([int]$DiskNumber,[UInt64]$Lba,[UInt32]$SectorCount,[int]$BytesPerSector){
  LD-RequirePositiveInt "DiskNumber" $DiskNumber
  if($SectorCount -le 0){ LD-Die "BAD_ARG" "SectorCount must be > 0" }
  if($BytesPerSector -le 0){ LD-Die "BAD_ARG" "BytesPerSector must be > 0" }

  $offset = [Int64]($Lba * [UInt64]$BytesPerSector)
  $count  = [int]([UInt64]$SectorCount * [UInt64]$BytesPerSector)

  $fs = $null
  try {
    $fs = LD-OpenRawDiskRead $DiskNumber
    return (LD-ReadBytes $fs $offset $count)
  } finally {
    LD-CloseStream $fs
  }
}

function LD-WriteSectors([int]$DiskNumber,[UInt64]$Lba,[byte[]]$Bytes,[int]$BytesPerSector){
  LD-RequirePositiveInt "DiskNumber" $DiskNumber
  if($BytesPerSector -le 0){ LD-Die "BAD_ARG" "BytesPerSector must be > 0" }
  if($null -eq $Bytes){ LD-Die "NULL_BYTES" "Bytes" }
  LD-RequireMultipleOf "Bytes.Length" ([Int64]$Bytes.Length) ([Int64]$BytesPerSector)

  $offset = [Int64]($Lba * [UInt64]$BytesPerSector)

  $fs = $null
  try {
    $fs = LD-OpenRawDiskReadWrite $DiskNumber
    LD-WriteBytes $fs $offset $Bytes
  } finally {
    LD-CloseStream $fs
  }
}

function LD-ReadSector([int]$DiskNumber,[UInt64]$Lba,[int]$BytesPerSector){
  return (LD-ReadSectors -DiskNumber $DiskNumber -Lba $Lba -SectorCount 1 -BytesPerSector $BytesPerSector)
}

function LD-WriteSector([int]$DiskNumber,[UInt64]$Lba,[byte[]]$Bytes,[int]$BytesPerSector){
  if($Bytes.Length -ne $BytesPerSector){
    LD-Die "BAD_SECTOR_BUFFER" ("expected=" + $BytesPerSector + " actual=" + $Bytes.Length)
  }
  LD-WriteSectors -DiskNumber $DiskNumber -Lba $Lba -Bytes $Bytes -BytesPerSector $BytesPerSector
}

function LD-GetDiskFacts([int]$DiskNumber){
  LD-RequirePositiveInt "DiskNumber" $DiskNumber
  try {
    $d = Get-Disk -Number $DiskNumber -ErrorAction Stop
    $logical = 512
    $physical = 512
    try { if($d.LogicalSectorSize -gt 0){ $logical = [int]$d.LogicalSectorSize } } catch { $logical = 512 }
    try { if($d.PhysicalSectorSize -gt 0){ $physical = [int]$d.PhysicalSectorSize } } catch { $physical = $logical }

    return [ordered]@{
      disk_number = [int]$d.Number
      friendly_name = [string]$d.FriendlyName
      serial_number = [string]$d.SerialNumber
      bus_type = [string]$d.BusType
      partition_style = [string]$d.PartitionStyle
      size_bytes = [UInt64]$d.Size
      logical_sector_size = [int]$logical
      physical_sector_size = [int]$physical
      is_boot = [bool]$d.IsBoot
      is_system = [bool]$d.IsSystem
      is_removable = [bool]$d.IsRemovable
      operational_status = [string](@($d.OperationalStatus) -join ",")
      health_status = [string]$d.HealthStatus
      path = (LD-GetDiskPath $DiskNumber)
    }
  } catch {
    LD-Die "DISK_FACTS_FAIL" ("DiskNumber=" + $DiskNumber + " :: " + $_.Exception.Message)
  }
}

function LD-NewZeroSectors([UInt32]$SectorCount,[int]$BytesPerSector){
  if($SectorCount -le 0){ LD-Die "BAD_ARG" "SectorCount must be > 0" }
  if($BytesPerSector -le 0){ LD-Die "BAD_ARG" "BytesPerSector must be > 0" }
  $len = [int]([UInt64]$SectorCount * [UInt64]$BytesPerSector)
  return (New-Object byte[] $len)
}

function LD-ReadMbrSector([int]$DiskNumber,[int]$BytesPerSector){
  return (LD-ReadSector -DiskNumber $DiskNumber -Lba 0 -BytesPerSector $BytesPerSector)
}

function LD-WriteMbrSector([int]$DiskNumber,[byte[]]$Sector,[int]$BytesPerSector){
  if($Sector.Length -ne $BytesPerSector){
    LD-Die "BAD_SECTOR_BUFFER" ("expected=" + $BytesPerSector + " actual=" + $Sector.Length)
  }
  LD-WriteSector -DiskNumber $DiskNumber -Lba 0 -Bytes $Sector -BytesPerSector $BytesPerSector
}

function LD-AssertMbrSignature([byte[]]$Sector){
  if($null -eq $Sector){ LD-Die "NULL_SECTOR" "Sector" }
  if($Sector.Length -lt 512){ LD-Die "SHORT_SECTOR" ("len=" + $Sector.Length) }
  $sig = LD-GetU16LE -Buffer $Sector -Offset 510
  if($sig -ne 0xAA55){
    LD-Die "MBR_SIGNATURE_BAD" ("sig=0x" + $sig.ToString("X4"))
  }
}

function LD-ExportModuleInfo {
  return [ordered]@{
    schema = "ld.rawdisk.lib.info.v1"
    name = "_lib_ld_rawdisk_v1.ps1"
    provides = @(
      "LD-RequireAdmin",
      "LD-GetDiskPath",
      "LD-GetDiskFacts",
      "LD-OpenRawDiskRead",
      "LD-OpenRawDiskReadWrite",
      "LD-ReadBytes",
      "LD-WriteBytes",
      "LD-ReadSector",
      "LD-WriteSector",
      "LD-ReadSectors",
      "LD-WriteSectors",
      "LD-SetU16LE",
      "LD-SetU32LE",
      "LD-GetU16LE",
      "LD-GetU32LE",
      "LD-AssertMbrSignature",
      "LD-Sha256Hex"
    )
  }
}
