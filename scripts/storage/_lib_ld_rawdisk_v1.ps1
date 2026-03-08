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
    LD-Die "ADMIN_REQUIRED" "raw disk operations require elevation"
  }
}

function LD-GetDiskPath([int]$DiskNumber){
  if($DiskNumber -lt 0){
    LD-Die "BAD_DISK_NUMBER" ([string]$DiskNumber)
  }
  return ("\\.\PhysicalDrive" + $DiskNumber)
}

function LD-GetDiskFacts([int]$DiskNumber){
  $d = Get-Disk -Number $DiskNumber -ErrorAction Stop

  $logical = 512
  $physical = 512

  try {
    if($d.LogicalSectorSize){ $logical = [int]$d.LogicalSectorSize }
  } catch { }

  try {
    if($d.PhysicalSectorSize){ $physical = [int]$d.PhysicalSectorSize }
  } catch { }

  $bus = ""
  $uniq = ""

  try {
    if($d.BusType){ $bus = [string]$d.BusType }
  } catch { }

  try {
    if($d.UniqueId){ $uniq = [string]$d.UniqueId }
  } catch { }

  return [ordered]@{
    schema = "ld.rawdisk.facts.v1"
    disk_number = [int]$d.Number
    path = (LD-GetDiskPath -DiskNumber $d.Number)
    friendly_name = [string]$d.FriendlyName
    serial_number = [string]$d.SerialNumber
    unique_id = $uniq
    size_bytes = [UInt64]$d.Size
    partition_style = [string]$d.PartitionStyle
    bus_type = $bus
    is_boot = [bool]$d.IsBoot
    is_system = [bool]$d.IsSystem
    logical_sector_size = [int]$logical
    physical_sector_size = [int]$physical
  }
}

function LD-OpenRawDiskRead([int]$DiskNumber){
  LD-RequireAdmin
  $path = LD-GetDiskPath -DiskNumber $DiskNumber
  return New-Object System.IO.FileStream(
    $path,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite
  )
}

function LD-OpenRawDiskReadWrite([int]$DiskNumber){
  LD-RequireAdmin
  $path = LD-GetDiskPath -DiskNumber $DiskNumber
  return New-Object System.IO.FileStream(
    $path,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::ReadWrite
  )
}

function LD-ReadBytes([System.IO.FileStream]$Stream,[UInt64]$Offset,[int]$Count){
  if($null -eq $Stream){ LD-Die "NULL_STREAM" "LD-ReadBytes" }
  if($Count -lt 0){ LD-Die "BAD_COUNT" ([string]$Count) }

  [void]$Stream.Seek([Int64]$Offset,[System.IO.SeekOrigin]::Begin)

  $buf = New-Object byte[] $Count
  $read = 0

  while($read -lt $Count){
    $n = $Stream.Read($buf,$read,$Count - $read)
    if($n -le 0){
      LD-Die "SHORT_READ" ("requested=" + $Count + " read=" + $read)
    }
    $read += $n
  }

  return $buf
}

function LD-WriteBytes([System.IO.FileStream]$Stream,[UInt64]$Offset,[byte[]]$Bytes){
  if($null -eq $Stream){ LD-Die "NULL_STREAM" "LD-WriteBytes" }
  if($null -eq $Bytes){ LD-Die "NULL_BYTES" "LD-WriteBytes" }

  [void]$Stream.Seek([Int64]$Offset,[System.IO.SeekOrigin]::Begin)
  $Stream.Write($Bytes,0,$Bytes.Length)
  $Stream.Flush()
}

function LD-ReadSector([int]$DiskNumber,[UInt64]$Lba,[int]$BytesPerSector){
  $fs = LD-OpenRawDiskRead -DiskNumber $DiskNumber
  try {
    return LD-ReadBytes -Stream $fs -Offset ($Lba * [UInt64]$BytesPerSector) -Count $BytesPerSector
  } finally {
    $fs.Dispose()
  }
}

function LD-WriteSector([int]$DiskNumber,[UInt64]$Lba,[byte[]]$Bytes,[int]$BytesPerSector){
  if($null -eq $Bytes){ LD-Die "NULL_BYTES" "LD-WriteSector" }
  if($Bytes.Length -ne $BytesPerSector){
    LD-Die "WRITE_SECTOR_SIZE_MISMATCH" ("len=" + $Bytes.Length + " bps=" + $BytesPerSector)
  }

  $fs = LD-OpenRawDiskReadWrite -DiskNumber $DiskNumber
  try {
    LD-WriteBytes -Stream $fs -Offset ($Lba * [UInt64]$BytesPerSector) -Bytes $Bytes
  } finally {
    $fs.Dispose()
  }
}

function LD-ReadSectors([int]$DiskNumber,[UInt64]$Lba,[UInt64]$SectorCount,[int]$BytesPerSector){
  $total = $SectorCount * [UInt64]$BytesPerSector
  if($total -gt [UInt64][int]::MaxValue){
    LD-Die "READ_TOO_LARGE" ([string]$total)
  }

  $fs = LD-OpenRawDiskRead -DiskNumber $DiskNumber
  try {
    return LD-ReadBytes -Stream $fs -Offset ($Lba * [UInt64]$BytesPerSector) -Count ([int]$total)
  } finally {
    $fs.Dispose()
  }
}

function LD-WriteSectors([int]$DiskNumber,[UInt64]$Lba,[byte[]]$Bytes,[int]$BytesPerSector){
  if($null -eq $Bytes){ LD-Die "NULL_BYTES" "LD-WriteSectors" }
  if($BytesPerSector -le 0){ LD-Die "BAD_BPS" ([string]$BytesPerSector) }
  if(($Bytes.Length % $BytesPerSector) -ne 0){
    LD-Die "WRITE_SECTORS_SIZE_MISMATCH" ("len=" + $Bytes.Length + " bps=" + $BytesPerSector)
  }

  $fs = LD-OpenRawDiskReadWrite -DiskNumber $DiskNumber
  try {
    LD-WriteBytes -Stream $fs -Offset ($Lba * [UInt64]$BytesPerSector) -Bytes $Bytes
  } finally {
    $fs.Dispose()
  }
}

function LD-SetU16LE([byte[]]$Buffer,[int]$Offset,[UInt16]$Value){
  if($null -eq $Buffer){ LD-Die "LD_SET_U16LE_NULL_BUFFER" "" }
  if($Offset -lt 0){ LD-Die "LD_SET_U16LE_BAD_OFFSET" ([string]$Offset) }
  if(($Offset + 1) -ge $Buffer.Length){
    LD-Die "LD_SET_U16LE_OOB" ("offset=" + $Offset + " len=" + $Buffer.Length)
  }

  $Buffer[$Offset]     = [byte]($Value % 256)
  $Buffer[$Offset + 1] = [byte]([math]::Floor($Value / 256))
}

function LD-SetU32LE([byte[]]$Buffer,[int]$Offset,[UInt32]$Value){
  if($null -eq $Buffer){ LD-Die "LD_SET_U32LE_NULL_BUFFER" "" }
  if($Offset -lt 0){ LD-Die "LD_SET_U32LE_BAD_OFFSET" ([string]$Offset) }
  if(($Offset + 3) -ge $Buffer.Length){
    LD-Die "LD_SET_U32LE_OOB" ("offset=" + $Offset + " len=" + $Buffer.Length)
  }

  $Buffer[$Offset]     = [byte]($Value % 256)
  $Buffer[$Offset + 1] = [byte]([math]::Floor(($Value / 256) % 256))
  $Buffer[$Offset + 2] = [byte]([math]::Floor(($Value / 65536) % 256))
  $Buffer[$Offset + 3] = [byte]([math]::Floor(($Value / 16777216) % 256))
}

function LD-GetU16LE([byte[]]$Buffer,[int]$Offset){
  if($null -eq $Buffer){ LD-Die "LD_GET_U16LE_NULL_BUFFER" "" }
  if($Offset -lt 0){ LD-Die "LD_GET_U16LE_BAD_OFFSET" ([string]$Offset) }
  if(($Offset + 1) -ge $Buffer.Length){
    LD-Die "LD_GET_U16LE_OOB" ("offset=" + $Offset + " len=" + $Buffer.Length)
  }

  $b0 = [UInt16]$Buffer[$Offset]
  $b1 = [UInt16]$Buffer[$Offset + 1]

  return [UInt16]($b0 + ($b1 * 256))
}

function LD-GetU32LE([byte[]]$Buffer,[int]$Offset){
  if($null -eq $Buffer){ LD-Die "LD_GET_U32LE_NULL_BUFFER" "" }
  if($Offset -lt 0){ LD-Die "LD_GET_U32LE_BAD_OFFSET" ([string]$Offset) }
  if(($Offset + 3) -ge $Buffer.Length){
    LD-Die "LD_GET_U32LE_OOB" ("offset=" + $Offset + " len=" + $Buffer.Length)
  }

  $b0 = [UInt32]$Buffer[$Offset]
  $b1 = [UInt32]$Buffer[$Offset + 1]
  $b2 = [UInt32]$Buffer[$Offset + 2]
  $b3 = [UInt32]$Buffer[$Offset + 3]

  return [UInt32]($b0 + ($b1 * 256) + ($b2 * 65536) + ($b3 * 16777216))
}

function LD-AssertMbrSignature([byte[]]$Buffer){
  $sig = LD-GetU16LE -Buffer $Buffer -Offset 510
  if($sig -ne 0xAA55){
    LD-Die "MBR_SIGNATURE_BAD" ("actual=" + $sig + " expected=43605")
  }
}

function LD-BytesToHex([byte[]]$Bytes){
  if($null -eq $Bytes){ return "" }
  $sb = New-Object System.Text.StringBuilder
  foreach($b in $Bytes){
    [void]$sb.AppendFormat("{0:x2}", $b)
  }
  return $sb.ToString()
}

function LD-Sha256Hex([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = [byte[]]@() }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }

  return (LD-BytesToHex -Bytes $hash)
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
      "LD-BytesToHex",
      "LD-Sha256Hex",
      "LD-ExportModuleInfo"
    )
  }
}
