param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$DiskNumber = -1,
  [string]$DeviceId,
  [string]$ExpectedLabel,
  [switch]$EmitReceipt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_lib_ld_rawdisk_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_fat32_layout_v1.ps1")

function VFAT-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function VFAT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function VFAT-Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }

function VFAT-WriteUtf8NoBomLf([string]$path,[string]$text){
  $dir = Split-Path -Parent $path
  if($dir){ VFAT-EnsureDir $dir }
  $t = ($text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($path,$t,(VFAT-Utf8NoBom))
}

function VFAT-AppendUtf8NoBomLf([string]$path,[string]$line){
  $dir = Split-Path -Parent $path
  if($dir){ VFAT-EnsureDir $dir }
  $t = ($line -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($path,$t,(VFAT-Utf8NoBom))
}

function VFAT-Canon($v){
  if($null -eq $v){ return $null }

  if($v -is [string] -or $v -is [int] -or $v -is [long] -or $v -is [uint16] -or $v -is [uint32] -or $v -is [uint64] -or $v -is [double] -or $v -is [decimal] -or $v -is [bool]){
    return $v
  }

  if($v -is [datetime]){
    return $v.ToUniversalTime().ToString("o")
  }

  if($v -is [System.Collections.IDictionary]){
    $keys = @($v.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $o = [ordered]@{}
    foreach($k in $keys){
      $o[$k] = VFAT-Canon $v[$k]
    }
    return $o
  }

  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $a = @()
    foreach($x in $v){
      $a += ,(VFAT-Canon $x)
    }
    return $a
  }

  return ([string]$v)
}

function VFAT-ToCanonJson($v){
  return ((VFAT-Canon $v) | ConvertTo-Json -Depth 50 -Compress)
}

function VFAT-Sha256HexTextLf([string]$s){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes(($s + "`n"))
  return (LD-Sha256Hex $bytes)
}

function VFAT-ReceiptPath([string]$RepoRoot){
  return (Join-Path $RepoRoot "proofs\receipts\storage.ndjson")
}

function VFAT-EmitReceipt([string]$RepoRoot,[hashtable]$Obj){
  $rp = VFAT-ReceiptPath $RepoRoot
  $json = VFAT-ToCanonJson $Obj
  $rh = VFAT-Sha256HexTextLf $json
  $o2 = [ordered]@{}
  foreach($k in $Obj.Keys){ $o2[$k] = $Obj[$k] }
  $o2["receipt_hash"] = $rh
  VFAT-AppendUtf8NoBomLf $rp (VFAT-ToCanonJson $o2)
  return $rh
}

function VFAT-MakeDeviceId($d){
  $u = ""
  try { if($d.UniqueId){ $u = [string]$d.UniqueId } } catch { $u = "" }
  $base = ("disk_number=" + $d.Number + "|unique_id=" + $u + "|size=" + $d.Size + "|name=" + $d.FriendlyName)
  $h = VFAT-Sha256HexTextLf $base
  return ("win.disk.v1:" + $d.Number + ":" + $h)
}

function VFAT-PickDisk([string]$DeviceId,[int]$DiskNumber){
  $ds = @(Get-Disk | Sort-Object Number)

  if($DiskNumber -ge 0){
    $d = $ds | Where-Object { $_.Number -eq $DiskNumber } | Select-Object -First 1
    if(-not $d){ VFAT-Die "DISK_NOT_FOUND" ([string]$DiskNumber) }
    return $d
  }

  if([string]::IsNullOrWhiteSpace($DeviceId)){
    VFAT-Die "MISSING_TARGET" "pass -DiskNumber or -DeviceId"
  }

  $hits = @()
  foreach($d in $ds){
    if((VFAT-MakeDeviceId $d) -eq $DeviceId){
      $hits += ,$d
    }
  }

  if(@($hits).Count -ne 1){
    VFAT-Die "DEVICEID_NOT_UNIQUE_OR_NOT_FOUND" ("count=" + @($hits).Count)
  }

  return $hits[0]
}

function VFAT-AsciiTrim([byte[]]$Buffer,[int]$Offset,[int]$Length){
  if($null -eq $Buffer){ VFAT-Die "NULL_BUFFER" "Buffer" }
  if($Offset -lt 0 -or $Length -lt 0 -or ($Offset + $Length) -gt $Buffer.Length){
    VFAT-Die "OFFSET_OOB" ("Offset=" + $Offset + " Length=" + $Length + " BufferLength=" + $Buffer.Length)
  }

  $slice = New-Object byte[] $Length
  [Array]::Copy($Buffer,$Offset,$slice,0,$Length)
  $s = [System.Text.Encoding]::ASCII.GetString($slice)
  return $s.Trim([char]0x00,[char]0x20)
}

function VFAT-DecodeFatDateTime([UInt16]$Date,[UInt16]$Time){
  try {
    $year   = 1980 + (($Date -shr 9) -band 0x7F)
    $month  = (($Date -shr 5) -band 0x0F)
    $day    = ($Date -band 0x1F)
    $hour   = (($Time -shr 11) -band 0x1F)
    $minute = (($Time -shr 5) -band 0x3F)
    $second = (($Time -band 0x1F) * 2)

    if($month -lt 1 -or $month -gt 12){ return "" }
    if($day -lt 1 -or $day -gt 31){ return "" }

    return ([datetime]::new($year,$month,$day,$hour,$minute,$second,[DateTimeKind]::Utc).ToString("o"))
  } catch {
    return ""
  }
}

function VFAT-ParseVolumeLabelFromRoot([byte[]]$RootCluster,[int]$BytesPerSector,[uint32]$SectorsPerCluster){
  if($null -eq $RootCluster){ VFAT-Die "NULL_ROOT" "RootCluster" }

  $entrySize = 32
  $entryCount = [int]($RootCluster.Length / $entrySize)

  for($i=0; $i -lt $entryCount; $i++){
    $off = $i * $entrySize
    $first = $RootCluster[$off + 0]
    if($first -eq 0x00){ break }        # end of dir
    if($first -eq 0xE5){ continue }     # deleted
    $attr = $RootCluster[$off + 11]
    if($attr -eq 0x08){
      return (VFAT-AsciiTrim -Buffer $RootCluster -Offset $off -Length 11)
    }
  }

  return ""
}

function VFAT-BuildResult(
  [hashtable]$Plan,
  [hashtable]$DiskFacts,
  [hashtable]$Checks,
  [string]$Token,
  [bool]$Ok
){
  return [ordered]@{
    schema = "ld.fat32.verify.result.v1"
    ok = $Ok
    token = $Token
    disk_number = $Plan.disk_number
    device_id = $Plan.device_id
    friendly_name = $DiskFacts.friendly_name
    bus_type = $DiskFacts.bus_type
    partition_style = $DiskFacts.partition_style
    disk_size_bytes = $DiskFacts.size_bytes
    bytes_per_sector = $Plan.bytes_per_sector
    plan = $Plan
    checks = $Checks
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

try {
  $disk = VFAT-PickDisk -DeviceId $DeviceId -DiskNumber $DiskNumber
  $diskFacts = LD-GetDiskFacts -DiskNumber $disk.Number
  $deviceId = VFAT-MakeDeviceId $disk

  $plan = LDFAT-NewPlan -DiskSizeBytes ([UInt64]$diskFacts.size_bytes) -BytesPerSector ([int]$diskFacts.logical_sector_size) -DeviceId $deviceId -DiskNumber ([int]$disk.Number) -Label $ExpectedLabel -ClusterKiB 0

  $bps = [int]$plan.bytes_per_sector

  $mbr = LD-ReadSector -DiskNumber $disk.Number -Lba 0 -BytesPerSector $bps

  $bootLba = [UInt64]$plan.partition_start_lba
  $boot = LD-ReadSector -DiskNumber $disk.Number -Lba $bootLba -BytesPerSector $bps

  $fsInfoLba = [UInt64]$plan.partition_start_lba + [UInt64]$plan.fsinfo_sector
  $fsInfo = LD-ReadSector -DiskNumber $disk.Number -Lba $fsInfoLba -BytesPerSector $bps

  $backupBootLba = [UInt64]$plan.partition_start_lba + [UInt64]$plan.backup_boot_sector
  $backupBoot = LD-ReadSector -DiskNumber $disk.Number -Lba $backupBootLba -BytesPerSector $bps

  $fat1StartLba = [UInt64]$plan.fat1_start_lba
  $fat2StartLba = [UInt64]$plan.fat2_start_lba

  $fat1First = LD-ReadSector -DiskNumber $disk.Number -Lba $fat1StartLba -BytesPerSector $bps
  $fat2First = LD-ReadSector -DiskNumber $disk.Number -Lba $fat2StartLba -BytesPerSector $bps

  $rootLen = [int]([uint32]$plan.sectors_per_cluster * [uint32]$bps)
  $rootFirstLba = [UInt64]$plan.root_dir_first_lba
  $rootCluster = LD-ReadSectors -DiskNumber $disk.Number -Lba $rootFirstLba -SectorCount ([uint32]$plan.sectors_per_cluster) -BytesPerSector $bps

  $checks = [ordered]@{}

  # ---------------- MBR ----------------
  $mbrSig = LD-GetU16LE -Buffer $mbr -Offset 510
  $checks["mbr_signature_ok"] = ($mbrSig -eq 0xAA55)
  if(-not $checks["mbr_signature_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:MBR_SIGNATURE" ("sig=0x" + $mbrSig.ToString("X4")) }

  $entry = 446
  $ptype = [byte]$mbr[$entry + 4]
  $checks["partition_type_ok"] = ($ptype -eq 0x0C)
  if(-not $checks["partition_type_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:PARTITION_TYPE" ("actual=0x" + $ptype.ToString("X2")) }

  $pstart = LD-GetU32LE -Buffer $mbr -Offset ($entry + 8)
  $psize  = LD-GetU32LE -Buffer $mbr -Offset ($entry + 12)
  $checks["partition_start_ok"] = ([UInt64]$pstart -eq [UInt64]$plan.partition_start_lba)
  if(-not $checks["partition_start_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:PARTITION_START" ("actual=" + $pstart + " expected=" + $plan.partition_start_lba) }

  $checks["partition_size_ok"] = ([UInt64]$psize -eq [UInt64]$plan.partition_size_lba)
  if(-not $checks["partition_size_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:PARTITION_SIZE" ("actual=" + $psize + " expected=" + $plan.partition_size_lba) }

  # ---------------- Boot sector ----------------
  $jmp0 = [byte]$boot[0]
  $jmp2 = [byte]$boot[2]
  $jumpOk = (($jmp0 -eq 0xEB -and $jmp2 -eq 0x90) -or ($jmp0 -eq 0xE9))
  $checks["boot_jump_ok"] = $jumpOk
  if(-not $checks["boot_jump_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_JUMP" ("bytes=" + ($boot[0].ToString("X2")) + "," + ($boot[1].ToString("X2")) + "," + ($boot[2].ToString("X2"))) }

  $oem = VFAT-AsciiTrim -Buffer $boot -Offset 3 -Length 8
  $checks["boot_oem_name"] = $oem

  $bootBps = LD-GetU16LE -Buffer $boot -Offset 11
  $checks["boot_bps_ok"] = ($bootBps -eq [UInt16]$plan.bytes_per_sector)
  if(-not $checks["boot_bps_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_BPS" ("actual=" + $bootBps + " expected=" + $plan.bytes_per_sector) }

  $bootSpc = [byte]$boot[13]
  $checks["boot_spc_ok"] = ($bootSpc -eq [byte]$plan.sectors_per_cluster)
  if(-not $checks["boot_spc_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_SPC" ("actual=" + $bootSpc + " expected=" + $plan.sectors_per_cluster) }

  $bootReserved = LD-GetU16LE -Buffer $boot -Offset 14
  $checks["boot_reserved_ok"] = ($bootReserved -eq [UInt16]$plan.reserved_sectors)
  if(-not $checks["boot_reserved_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_RESERVED" ("actual=" + $bootReserved + " expected=" + $plan.reserved_sectors) }

  $bootFatCount = [byte]$boot[16]
  $checks["boot_fat_count_ok"] = ($bootFatCount -eq [byte]$plan.fat_count)
  if(-not $checks["boot_fat_count_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_FAT_COUNT" ("actual=" + $bootFatCount + " expected=" + $plan.fat_count) }

  $bootTot16 = LD-GetU16LE -Buffer $boot -Offset 19
  $bootTot32 = LD-GetU32LE -Buffer $boot -Offset 32
  $checks["boot_total_sectors_ok"] = (($bootTot16 -eq 0) -and ([UInt64]$bootTot32 -eq [UInt64]$plan.partition_size_lba))
  if(-not $checks["boot_total_sectors_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_TOTAL_SECTORS" ("tot16=" + $bootTot16 + " tot32=" + $bootTot32 + " expected=" + $plan.partition_size_lba) }

  $bootFatSz16 = LD-GetU16LE -Buffer $boot -Offset 22
  $bootFatSz32 = LD-GetU32LE -Buffer $boot -Offset 36
  $checks["boot_fat_size_ok"] = (($bootFatSz16 -eq 0) -and ([UInt64]$bootFatSz32 -eq [UInt64]$plan.fat_size_sectors))
  if(-not $checks["boot_fat_size_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_FAT_SIZE" ("fat16=" + $bootFatSz16 + " fat32=" + $bootFatSz32 + " expected=" + $plan.fat_size_sectors) }

  $bootRootCluster = LD-GetU32LE -Buffer $boot -Offset 44
  $checks["boot_root_cluster_ok"] = ($bootRootCluster -eq [UInt32]$plan.root_cluster)
  if(-not $checks["boot_root_cluster_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_ROOT_CLUSTER" ("actual=" + $bootRootCluster + " expected=" + $plan.root_cluster) }

  $bootFsInfo = LD-GetU16LE -Buffer $boot -Offset 48
  $checks["boot_fsinfo_ok"] = ($bootFsInfo -eq [UInt16]$plan.fsinfo_sector)
  if(-not $checks["boot_fsinfo_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_FSINFO" ("actual=" + $bootFsInfo + " expected=" + $plan.fsinfo_sector) }

  $bootBackup = LD-GetU16LE -Buffer $boot -Offset 50
  $checks["boot_backup_ok"] = ($bootBackup -eq [UInt16]$plan.backup_boot_sector)
  if(-not $checks["boot_backup_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_BACKUP" ("actual=" + $bootBackup + " expected=" + $plan.backup_boot_sector) }

  $media = [byte]$boot[21]
  $checks["boot_media_descriptor_ok"] = ($media -eq [byte]$plan.media_descriptor)
  if(-not $checks["boot_media_descriptor_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_MEDIA" ("actual=0x" + $media.ToString("X2") + " expected=0x" + ([byte]$plan.media_descriptor).ToString("X2")) }

  $volSerial = LD-GetU32LE -Buffer $boot -Offset 67
  $checks["boot_volume_serial_ok"] = ($volSerial -eq [UInt32]$plan.volume_serial)
  if(-not $checks["boot_volume_serial_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_SERIAL" ("actual=0x" + $volSerial.ToString("X8") + " expected=0x" + ([UInt32]$plan.volume_serial).ToString("X8")) }

  $bootLabel = VFAT-AsciiTrim -Buffer $boot -Offset 71 -Length 11
  $expectedLabel = LDFAT-UpperAsciiLabel $ExpectedLabel
  $checks["boot_label_ok"] = ($bootLabel -eq $expectedLabel)
  if(-not $checks["boot_label_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_LABEL" ("actual=" + $bootLabel + " expected=" + $expectedLabel) }

  $fsType = VFAT-AsciiTrim -Buffer $boot -Offset 82 -Length 8
  $checks["boot_fs_type_ok"] = ($fsType -eq "FAT32")
  if(-not $checks["boot_fs_type_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_FS_TYPE" ("actual=" + $fsType) }

  $bootSig = LD-GetU16LE -Buffer $boot -Offset 510
  $checks["boot_signature_ok"] = ($bootSig -eq 0xAA55)
  if(-not $checks["boot_signature_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BOOT_SIGNATURE" ("sig=0x" + $bootSig.ToString("X4")) }

  # ---------------- FSInfo ----------------
  $fsiLead = LD-GetU32LE -Buffer $fsInfo -Offset 0
  $fsiStruct = LD-GetU32LE -Buffer $fsInfo -Offset 484
  $fsiTrail = LD-GetU32LE -Buffer $fsInfo -Offset 508

  $checks["fsinfo_lead_ok"] = ($fsiLead -eq 0x41615252)
  if(-not $checks["fsinfo_lead_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:FSINFO_SIGNATURE" ("lead=0x" + $fsiLead.ToString("X8")) }

  $checks["fsinfo_struct_ok"] = ($fsiStruct -eq 0x61417272)
  if(-not $checks["fsinfo_struct_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:FSINFO_STRUCTURE" ("struct=0x" + $fsiStruct.ToString("X8")) }

  $checks["fsinfo_trail_ok"] = ($fsiTrail -eq 0xAA550000)
  if(-not $checks["fsinfo_trail_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:FSINFO_TRAIL" ("trail=0x" + $fsiTrail.ToString("X8")) }

  # ---------------- Backup boot ----------------
  $checks["backup_boot_match_ok"] = ($backupBoot.Length -eq $boot.Length -and ((LD-Sha256Hex $backupBoot) -eq (LD-Sha256Hex $boot)))
  if(-not $checks["backup_boot_match_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:BACKUP_BOOT" "backup boot sector does not match primary boot sector" }

  # ---------------- FAT mirror ----------------
  $fat1Hash = LD-Sha256Hex $fat1First
  $fat2Hash = LD-Sha256Hex $fat2First
  $checks["fat_mirror_ok"] = ($fat1Hash -eq $fat2Hash)
  if(-not $checks["fat_mirror_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:FAT_MIRROR" ("fat1=" + $fat1Hash + " fat2=" + $fat2Hash) }

  # FAT first entries
  $fatEntry0 = LD-GetU32LE -Buffer $fat1First -Offset 0
  $fatEntry1 = LD-GetU32LE -Buffer $fat1First -Offset 4
  $fatEntry2 = LD-GetU32LE -Buffer $fat1First -Offset 8

  $checks["fat_entry0_ok"] = (([UInt32]($fatEntry0 -band 0x0FFFFFFF)) -eq 0x0FFFFFF8)
  if(-not $checks["fat_entry0_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:FAT_ENTRY0" ("actual=0x" + $fatEntry0.ToString("X8")) }

  $checks["fat_entry1_ok"] = (([UInt32]($fatEntry1 -band 0x0FFFFFFF)) -eq 0x0FFFFFFF)
  if(-not $checks["fat_entry1_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:FAT_ENTRY1" ("actual=0x" + $fatEntry1.ToString("X8")) }

  $checks["fat_root_cluster_ok"] = (([UInt32]($fatEntry2 -band 0x0FFFFFFF)) -eq 0x0FFFFFFF)
  if(-not $checks["fat_root_cluster_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:ROOT_CLUSTER" ("actual=0x" + $fatEntry2.ToString("X8")) }

  # ---------------- Root directory ----------------
  $rootLabel = VFAT-ParseVolumeLabelFromRoot -RootCluster $rootCluster -BytesPerSector $bps -SectorsPerCluster ([uint32]$plan.sectors_per_cluster)
  $checks["root_label_found"] = $rootLabel
  if(-not [string]::IsNullOrWhiteSpace($rootLabel)){
    $checks["root_label_ok"] = ($rootLabel -eq $expectedLabel)
    if(-not $checks["root_label_ok"]){ VFAT-Die "FAT32_VERIFY_FAIL:ROOT_LABEL" ("actual=" + $rootLabel + " expected=" + $expectedLabel) }
  } else {
    $checks["root_label_ok"] = $true
  }

  $result = VFAT-BuildResult -Plan $plan -DiskFacts $diskFacts -Checks $checks -Token "FAT32_VERIFY_OK" -Ok $true

  $result | ConvertTo-Json -Depth 50
  Write-Host "FAT32_VERIFY_OK" -ForegroundColor Green

  if($EmitReceipt){
    $receipt = [ordered]@{
      schema = "storage.receipt.v1"
      action = "verify-fat32-layout-owned"
      time_utc = [DateTime]::UtcNow.ToString("o")
      host = $env:COMPUTERNAME
      disk_number = $plan.disk_number
      device_id = $plan.device_id
      expected_label = $expectedLabel
      token = "FAT32_VERIFY_OK"
      ok = $true
      fat32_verify_sha256 = VFAT-Sha256HexTextLf (VFAT-ToCanonJson $result)
    }
    [void](VFAT-EmitReceipt -RepoRoot $RepoRoot -Obj $receipt)
  }

  exit 0
}
catch {
  $msg = $_.Exception.Message
  Write-Host $msg -ForegroundColor Red

  if($EmitReceipt){
    try {
      $receipt2 = [ordered]@{
        schema = "storage.receipt.v1"
        action = "verify-fat32-layout-owned-fail"
        time_utc = [DateTime]::UtcNow.ToString("o")
        host = $env:COMPUTERNAME
        disk_number = $DiskNumber
        device_id = $DeviceId
        expected_label = $ExpectedLabel
        reason = $msg
        ok = $false
      }
      [void](VFAT-EmitReceipt -RepoRoot $RepoRoot -Obj $receipt2)
    } catch { }
  }

  exit 1
}
