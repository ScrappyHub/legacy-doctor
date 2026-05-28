param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][ValidateSet("list","format","inspect")][string]$Cmd,
  [int]$DiskNumber = -1,
  [string]$Fs = "fat32",
  [string]$Label = "SDCARD",
  [string]$IUnderstand = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ Die "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,(Utf8NoBom))
}

function Append-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($Path,$t,(Utf8NoBom))
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

function HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  return (HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($t)))
}

function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_FILE: " + $Path)
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

function Canon([object]$Value){
  if($null -eq $Value){ return $null }

  if(
    $Value -is [string] -or
    $Value -is [int] -or
    $Value -is [long] -or
    $Value -is [double] -or
    $Value -is [decimal] -or
    $Value -is [bool] -or
    $Value -is [byte] -or
    $Value -is [UInt16] -or
    $Value -is [UInt32] -or
    $Value -is [UInt64]
  ){
    return $Value
  }

  if($Value -is [datetime]){
    return $Value.ToUniversalTime().ToString("o")
  }

  if($Value -is [System.Collections.IDictionary]){
    $keys = @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $o = [ordered]@{}
    foreach($k in $keys){
      $o[$k] = Canon $Value[$k]
    }
    return $o
  }

  if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
    $arr = @()
    foreach($x in $Value){
      $arr += ,(Canon $x)
    }
    return $arr
  }

  return ([string]$Value)
}

function ToCanonJson([object]$Value){
  return ((Canon $Value) | ConvertTo-Json -Depth 30 -Compress)
}

function IsAdmin(){
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-CanOpenRawDevice([string]$DevicePath){
  try {
    $fs = New-Object System.IO.FileStream(
      $DevicePath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::ReadWrite
    )
    try {
      if($fs.Length -lt 0){ }
    } finally {
      $fs.Dispose()
    }
  } catch {
    Die ("RAW_DEVICE_OPEN_FAILED: " + $DevicePath + " :: " + $_.Exception.Message)
  }
}

function Read-BytesAt([string]$Path,[UInt64]$Offset,[int]$Count){
  $fs = New-Object System.IO.FileStream(
    $Path,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite
  )
  try {
    [void]$fs.Seek([Int64]$Offset,[IO.SeekOrigin]::Begin)
    $buf = New-Object byte[] $Count
    $read = $fs.Read($buf,0,$buf.Length)
    if($read -ne $Count){
      Die ("READ_SHORT: " + $Path + " offset=" + $Offset + " read=" + $read + " expected=" + $Count)
    }
    return $buf
  } finally {
    $fs.Dispose()
  }
}

function Write-BytesAt([string]$Path,[UInt64]$Offset,[byte[]]$Bytes){
  $fs = New-Object System.IO.FileStream(
    $Path,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::ReadWrite
  )
  try {
    [void]$fs.Seek([Int64]$Offset,[IO.SeekOrigin]::Begin)
    $fs.Write($Bytes,0,$Bytes.Length)
    $fs.Flush()
  } finally {
    $fs.Dispose()
  }
}

function Get-U16LE([byte[]]$Buffer,[int]$Offset){
  return [UInt16](
    ([UInt16]$Buffer[$Offset + 0]) -bor
    (([UInt16]$Buffer[$Offset + 1]) -shl 8)
  )
}

function Get-U32LE([byte[]]$Buffer,[int]$Offset){
  return [UInt32](
    ([UInt32]$Buffer[$Offset + 0]) -bor
    (([UInt32]$Buffer[$Offset + 1]) -shl 8) -bor
    (([UInt32]$Buffer[$Offset + 2]) -shl 16) -bor
    (([UInt32]$Buffer[$Offset + 3]) -shl 24)
  )
}

function Receipt-Path([string]$RepoRoot){
  return (Join-Path $RepoRoot "proofs\receipts\storage.ndjson")
}

function Append-Receipt([string]$RepoRoot,[hashtable]$Receipt){
  $json = ToCanonJson $Receipt
  $hash = HexSha256TextLf $json
  $final = [ordered]@{}
  foreach($k in @($Receipt.Keys | Sort-Object)){
    $final[$k] = $Receipt[$k]
  }
  $final["receipt_hash"] = $hash
  Append-Utf8NoBomLf (Receipt-Path $RepoRoot) (ToCanonJson $final)
  return $hash
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RawLib     = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib  = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib    = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$VerifyLib  = Join-Path $RepoRoot "scripts\storage\ld_verify_fat32_layout_v1.ps1"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$VerifyLib)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die ("MISSING_DEP: " + $p)
  }
}

. $RawLib
. $LayoutLib
. $BootLib

function Get-DiskFactsSafe([int]$DiskNumber){
  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  $parts = @(@(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue))

  $obj = [ordered]@{
    disk_number = [int]$disk.Number
    friendly_name = [string]$disk.FriendlyName
    serial_number = [string]$disk.SerialNumber
    bus_type = [string]$disk.BusType
    partition_style = [string]$disk.PartitionStyle
    is_boot = [bool]$disk.IsBoot
    is_system = [bool]$disk.IsSystem
    operational_status = [string]$disk.OperationalStatus
    health_status = [string]$disk.HealthStatus
    size = [UInt64]$disk.Size
    partitions = @()
  }

  foreach($part in $parts){
    $entry = [ordered]@{
      partition_number = [int]$part.PartitionNumber
      drive_letter = [string]$part.DriveLetter
      type = [string]$part.Type
      size = [UInt64]$part.Size
    }
    $obj.partitions += ,$entry
  }

  return $obj
}

function Print-Inspect([int]$DiskNumber){
  $facts = Get-DiskFactsSafe -DiskNumber $DiskNumber
  $facts | ConvertTo-Json -Depth 20
}

function List-Disks(){
  $rows = @()
  foreach($d in @(Get-Disk | Sort-Object Number)){
    $deviceId = ""
    try {
      $facts = Get-DiskFactsSafe -DiskNumber ([int]$d.Number)
      $seed = "disk|" + $facts.disk_number + "|" + $facts.friendly_name + "|" + $facts.serial_number + "|" + $facts.bus_type + "|" + $facts.size
      $deviceId = "win.disk.v1:" + $facts.disk_number + ":" + (HexSha256TextLf $seed)
    } catch {
      $deviceId = "win.disk.v1:" + [int]$d.Number + ":unknown"
    }

    $rows += [pscustomobject]@{
      DiskNumber = [int]$d.Number
      DeviceId = $deviceId
    }
  }
  $rows | Format-Table -AutoSize
}

function Verify-BasicImageBytes([string]$DevicePath,[hashtable]$Plan){
  $mbr = Read-BytesAt -Path $DevicePath -Offset 0 -Count 512
  if((Get-U16LE -Buffer $mbr -Offset 510) -ne 43605){
    Die "VERIFY_FAIL_MBR_SIGNATURE"
  }
  if($mbr[450] -ne [byte]$Plan.partition_type){
    Die ("VERIFY_FAIL_PARTITION_TYPE: actual=" + $mbr[450] + " expected=" + [byte]$Plan.partition_type)
  }
  if((Get-U32LE -Buffer $mbr -Offset 454) -ne [UInt32]$Plan.partition_start_lba){
    Die ("VERIFY_FAIL_PARTITION_START: actual=" + (Get-U32LE -Buffer $mbr -Offset 454) + " expected=" + [UInt32]$Plan.partition_start_lba)
  }

  $bootOffset = [UInt64]$Plan.partition_start_lba * [UInt64]$Plan.bytes_per_sector
  $boot = Read-BytesAt -Path $DevicePath -Offset $bootOffset -Count 512
  if((Get-U16LE -Buffer $boot -Offset 510) -ne 43605){
    Die "VERIFY_FAIL_BOOT_SIGNATURE"
  }
  if((Get-U16LE -Buffer $boot -Offset 11) -ne [UInt16]$Plan.bytes_per_sector){
    Die "VERIFY_FAIL_BOOT_BPS"
  }
  if($boot[13] -ne [byte]$Plan.sectors_per_cluster){
    Die "VERIFY_FAIL_BOOT_SPC"
  }

  $fsiOffset = $bootOffset + ([UInt64]$Plan.fsinfo_sector * [UInt64]$Plan.bytes_per_sector)
  $fsi = Read-BytesAt -Path $DevicePath -Offset $fsiOffset -Count 512
  if((Get-U32LE -Buffer $fsi -Offset 0) -ne [UInt32]1096897106){
    Die ("VERIFY_FAIL_FSINFO_LEAD: actual=" + (Get-U32LE -Buffer $fsi -Offset 0))
  }

  return [ordered]@{
    mbr = (HexSha256Bytes $mbr)
    boot = (HexSha256Bytes $boot)
    fsinfo = (HexSha256Bytes $fsi)
  }
}

function Format-OwnedFat32([int]$DiskNumber,[string]$Label,[string]$RepoRoot){
  if(-not (IsAdmin)){
    Die "ADMIN_REQUIRED: run PowerShell as Administrator for format operations"
  }

  if($DiskNumber -lt 0){
    Die "DISKNUMBER_REQUIRED"
  }

  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  if($disk.IsBoot -or $disk.IsSystem){
    Die ("REFUSE_SYSTEM_OR_BOOT_DISK: " + $DiskNumber)
  }

  $expectedToken = "ERASE_DISK_" + $DiskNumber
  if($IUnderstand -ne $expectedToken){
    Die ("IUNDERSTAND_TOKEN_REQUIRED: " + $expectedToken)
  }

  $devicePath = "\\.\PhysicalDrive" + $DiskNumber
  Assert-CanOpenRawDevice $devicePath

  $diskSizeBytes = [UInt64]$disk.Size
  $bytesPerSector = 512

  $plan = LDFAT-NewPlan `
    -DiskSizeBytes $diskSizeBytes `
    -BytesPerSector $bytesPerSector `
    -DeviceId ("win.disk.v1:" + $DiskNumber + ":" + (HexSha256TextLf ("disk|" + $DiskNumber + "|" + [string]$disk.FriendlyName + "|" + [string]$disk.SerialNumber + "|" + [string]$disk.BusType + "|" + [UInt64]$disk.Size))) `
    -DiskNumber $DiskNumber `
    -Label $Label `
    -ClusterKiB 0

  $mbr   = LDFAT-BuildMbrSector $plan
  $boot  = LDBOOT-BuildBootSector $plan
  $fsi   = LDBOOT-BuildFsInfoSector $plan
  $bb    = LDBOOT-BuildBackupBootSector $plan
  $fat0  = LDBOOT-BuildFatSector0 $plan
  $root0 = LDBOOT-BuildRootDirSector0 $plan

  $partsBefore = @(@(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue))
  foreach($p in $partsBefore){
    try {
      Remove-Partition -DiskNumber $DiskNumber -PartitionNumber $p.PartitionNumber -Confirm:$false -ErrorAction Stop
    } catch { }
  }

  try {
    Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop | Out-Null
  } catch { }

  Start-Sleep -Milliseconds 500

  Write-BytesAt -Path $devicePath -Offset 0 -Bytes $mbr

  $bootOffset = [UInt64]$plan.partition_start_lba * [UInt64]$plan.bytes_per_sector
  Write-BytesAt -Path $devicePath -Offset $bootOffset -Bytes $boot

  $fsiOffset = $bootOffset + ([UInt64]$plan.fsinfo_sector * [UInt64]$plan.bytes_per_sector)
  Write-BytesAt -Path $devicePath -Offset $fsiOffset -Bytes $fsi

  $bbOffset = $bootOffset + ([UInt64]$plan.backup_boot_sector * [UInt64]$plan.bytes_per_sector)
  Write-BytesAt -Path $devicePath -Offset $bbOffset -Bytes $bb

  $fat0Offset = [UInt64]$plan.fat1_start_lba * [UInt64]$plan.bytes_per_sector
  Write-BytesAt -Path $devicePath -Offset $fat0Offset -Bytes $fat0

  $fat1Offset = [UInt64]$plan.fat2_start_lba * [UInt64]$plan.bytes_per_sector
  Write-BytesAt -Path $devicePath -Offset $fat1Offset -Bytes $fat0

  $root0Offset = [UInt64]$plan.root_dir_first_lba * [UInt64]$plan.bytes_per_sector
  Write-BytesAt -Path $devicePath -Offset $root0Offset -Bytes $root0

  try {
    Update-Disk -Number $DiskNumber -ErrorAction Stop | Out-Null
  } catch { }

  Start-Sleep -Seconds 2

  $part = $null
  $partsAfter = @(@(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue))
  if($partsAfter.Count -gt 0){
    $part = $partsAfter | Sort-Object Size -Descending | Select-Object -First 1
  }

  if($null -eq $part){
    try {
      $part = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -DriveLetter E -ErrorAction Stop
    } catch { }
  }

  if($null -eq $part){
    Die ("PARTITION_NOT_VISIBLE_AFTER_WRITE: " + $DiskNumber)
  }

  $driveLetter = ""
  if($part.DriveLetter){
    $driveLetter = [string]$part.DriveLetter
  }

  $sectorHashes = Verify-BasicImageBytes -DevicePath $devicePath -Plan $plan

  $receipt = [ordered]@{
    schema = "ld.fat32.imagefile.receipt.v1"
    event_type = "ld.fat32.imagefile.receipt.v1"
    ok = $true
    repo_root = $RepoRoot
    image_path = $devicePath
    image_sha256 = ""
    plan_sha256 = (HexSha256TextLf (ToCanonJson $plan))
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
      mbr = $sectorHashes.mbr
      boot = $sectorHashes.boot
      fsinfo = $sectorHashes.fsinfo
      backup_boot = (HexSha256Bytes $bb)
      fat0 = (HexSha256Bytes $fat0)
      root0 = (HexSha256Bytes $root0)
    }
  }

  $receiptHash = Append-Receipt -RepoRoot $RepoRoot -Receipt $receipt

  Write-Host ("PICKED_DISK: #" + $DiskNumber + " " + [string]$disk.FriendlyName + " device_id=" + [string]$plan.device_id) -ForegroundColor Green
  Write-Host ("PARTITION_OK: " + $driveLetter + ":") -ForegroundColor Green
  Write-Host ("FORMAT_FAT32_OWNED_OK: " + $driveLetter + ": label=" + [string]$plan.volume_label) -ForegroundColor Green
  Write-Host ("RECEIPT_HASH: " + $receiptHash) -ForegroundColor Green
}

switch($Cmd){
  "list" {
    List-Disks
    break
  }
  "inspect" {
    if($DiskNumber -lt 0){
      Die "DISKNUMBER_REQUIRED_FOR_INSPECT"
    }
    Print-Inspect -DiskNumber $DiskNumber
    break
  }
  "format" {
    if($Fs.ToLowerInvariant() -ne "fat32"){
      Die ("UNSUPPORTED_FS: " + $Fs + " (owned path currently supports fat32 only)")
    }
    Format-OwnedFat32 -DiskNumber $DiskNumber -Label $Label -RepoRoot $RepoRoot
    break
  }
  default {
    Die ("UNKNOWN_CMD: " + $Cmd)
  }
}