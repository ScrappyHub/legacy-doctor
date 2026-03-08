param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DeviceId,
  [int]$DiskNumber = -1,
  [string]$Label = "SDCARD",
  [int]$ClusterKiB = 0,
  [Parameter(Mandatory=$true)][string]$IUnderstand,
  [switch]$EmitReceipt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_lib_ld_rawdisk_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_fat32_layout_v1.ps1")

function FMT-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function FMT-RequireToken([int]$DiskNumber,[string]$Token){
  $expected = "ERASE_DISK_" + $DiskNumber
  if($Token -ne $expected){
    FMT-Die "SAFETY_TOKEN_INVALID" ("expected=" + $expected + " got=" + $Token)
  }
}

function FMT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function FMT-Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }

function FMT-AppendUtf8NoBomLf([string]$path,[string]$line){
  $dir = Split-Path -Parent $path
  if($dir){ FMT-EnsureDir $dir }
  $t = ($line -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($path,$t,(FMT-Utf8NoBom))
}

function FMT-Canon($v){
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
      $o[$k] = FMT-Canon $v[$k]
    }
    return $o
  }

  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $a = @()
    foreach($x in $v){
      $a += ,(FMT-Canon $x)
    }
    return $a
  }

  return ([string]$v)
}

function FMT-ToCanonJson($v){
  return ((FMT-Canon $v) | ConvertTo-Json -Depth 50 -Compress)
}

function FMT-Sha256HexTextLf([string]$s){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes(($s + "`n"))
  return (LD-Sha256Hex $bytes)
}

function FMT-ReceiptPath([string]$RepoRoot){
  return (Join-Path $RepoRoot "proofs\receipts\storage.ndjson")
}

function FMT-EmitReceipt([string]$RepoRoot,[hashtable]$Obj){
  $rp = FMT-ReceiptPath $RepoRoot
  $json = FMT-ToCanonJson $Obj
  $rh = FMT-Sha256HexTextLf $json

  $o2 = [ordered]@{}
  foreach($k in $Obj.Keys){ $o2[$k] = $Obj[$k] }
  $o2["receipt_hash"] = $rh

  FMT-AppendUtf8NoBomLf $rp (FMT-ToCanonJson $o2)
}

function FMT-MakeDeviceId($d){
  $u = ""
  try { if($d.UniqueId){ $u = [string]$d.UniqueId } } catch { $u = "" }

  $base = ("disk_number=" + $d.Number + "|unique_id=" + $u + "|size=" + $d.Size + "|name=" + $d.FriendlyName)
  $h = FMT-Sha256HexTextLf $base

  return ("win.disk.v1:" + $d.Number + ":" + $h)
}

function FMT-PickDisk([string]$DeviceId,[int]$DiskNumber){
  $ds = @(Get-Disk | Sort-Object Number)

  if($DiskNumber -ge 0){
    $d = $ds | Where-Object { $_.Number -eq $DiskNumber } | Select-Object -First 1
    if(-not $d){ FMT-Die "DISK_NOT_FOUND" ([string]$DiskNumber) }
    return $d
  }

  if([string]::IsNullOrWhiteSpace($DeviceId)){
    FMT-Die "MISSING_TARGET" "pass -DiskNumber or -DeviceId"
  }

  $hits = @()
  foreach($d in $ds){
    if((FMT-MakeDeviceId $d) -eq $DeviceId){
      $hits += ,$d
    }
  }

  if(@($hits).Count -ne 1){
    FMT-Die "DEVICEID_NOT_UNIQUE_OR_NOT_FOUND" ("count=" + @($hits).Count)
  }

  return $hits[0]
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

try {

  $disk = FMT-PickDisk -DeviceId $DeviceId -DiskNumber $DiskNumber

  if($disk.IsBoot){ FMT-Die "REFUSE_BOOT_DISK" ("disk " + $disk.Number) }
  if($disk.IsSystem){ FMT-Die "REFUSE_SYSTEM_DISK" ("disk " + $disk.Number) }

  FMT-RequireToken $disk.Number $IUnderstand

  $deviceId = FMT-MakeDeviceId $disk

  $facts = LD-GetDiskFacts -DiskNumber $disk.Number

  $plan = LDFAT-NewPlan `
    -DiskSizeBytes ([UInt64]$facts.size_bytes) `
    -BytesPerSector ([int]$facts.logical_sector_size) `
    -DeviceId $deviceId `
    -DiskNumber ([int]$disk.Number) `
    -Label $Label `
    -ClusterKiB $ClusterKiB

  $bps = [int]$plan.bytes_per_sector

  Write-Host ("FORMAT_START disk=" + $disk.Number) -ForegroundColor Yellow

  # ---------------- write MBR ----------------

  $mbr = LDFAT-BuildMbrSector $plan
  LD-WriteSector -DiskNumber $disk.Number -Lba 0 -Bytes $mbr -BytesPerSector $bps

  # ---------------- build boot sector ----------------

  $boot = New-Object byte[] $bps

  $boot[0] = 0xEB
  $boot[1] = 0x58
  $boot[2] = 0x90

  $oem = [System.Text.Encoding]::ASCII.GetBytes($plan.oem_name.PadRight(8))
  [Array]::Copy($oem,0,$boot,3,8)

  LD-SetU16LE $boot 11 $plan.bytes_per_sector
  $boot[13] = [byte]$plan.sectors_per_cluster
  LD-SetU16LE $boot 14 $plan.reserved_sectors
  $boot[16] = [byte]$plan.fat_count
  LD-SetU16LE $boot 17 0
  LD-SetU16LE $boot 19 0
  $boot[21] = [byte]$plan.media_descriptor
  LD-SetU16LE $boot 22 0
  LD-SetU16LE $boot 24 63
  LD-SetU16LE $boot 26 255

  LD-SetU32LE $boot 28 $plan.partition_start_lba
  LD-SetU32LE $boot 32 $plan.partition_size_lba
  LD-SetU32LE $boot 36 $plan.fat_size_sectors
  LD-SetU16LE $boot 40 0
  LD-SetU16LE $boot 42 0
  LD-SetU32LE $boot 44 $plan.root_cluster
  LD-SetU16LE $boot 48 $plan.fsinfo_sector
  LD-SetU16LE $boot 50 $plan.backup_boot_sector

  $boot[64] = 0x80
  $boot[66] = 0x29

  LD-SetU32LE $boot 67 $plan.volume_serial

  $labelBytes = [System.Text.Encoding]::ASCII.GetBytes($plan.volume_label.PadRight(11))
  [Array]::Copy($labelBytes,0,$boot,71,11)

  $fstype = [System.Text.Encoding]::ASCII.GetBytes("FAT32   ")
  [Array]::Copy($fstype,0,$boot,82,8)

  $boot[510] = 0x55
  $boot[511] = 0xAA

  LD-WriteSector -DiskNumber $disk.Number -Lba $plan.partition_start_lba -Bytes $boot -BytesPerSector $bps

  # ---------------- FSINFO ----------------

  $fsinfo = New-Object byte[] $bps

  LD-SetU32LE $fsinfo 0 0x41615252
  LD-SetU32LE $fsinfo 484 0x61417272
  LD-SetU32LE $fsinfo 488 0xFFFFFFFF
  LD-SetU32LE $fsinfo 492 0xFFFFFFFF
  LD-SetU32LE $fsinfo 508 0xAA550000

  LD-WriteSector -DiskNumber $disk.Number -Lba ($plan.partition_start_lba + $plan.fsinfo_sector) -Bytes $fsinfo -BytesPerSector $bps

  # ---------------- backup boot ----------------

  LD-WriteSector -DiskNumber $disk.Number -Lba ($plan.partition_start_lba + $plan.backup_boot_sector) -Bytes $boot -BytesPerSector $bps

  # ---------------- FAT tables ----------------

  $fatBytes = New-Object byte[] ($plan.fat_size_sectors * $bps)

  LD-SetU32LE $fatBytes 0 0x0FFFFFF8
  LD-SetU32LE $fatBytes 4 0xFFFFFFFF
  LD-SetU32LE $fatBytes 8 0x0FFFFFFF

  LD-WriteSectors -DiskNumber $disk.Number -Lba $plan.fat1_start_lba -Bytes $fatBytes -BytesPerSector $bps
  LD-WriteSectors -DiskNumber $disk.Number -Lba $plan.fat2_start_lba -Bytes $fatBytes -BytesPerSector $bps

  # ---------------- root directory ----------------

  $root = New-Object byte[] ($plan.sectors_per_cluster * $bps)

  $labelEntry = [System.Text.Encoding]::ASCII.GetBytes($plan.volume_label.PadRight(11))
  [Array]::Copy($labelEntry,0,$root,0,11)

  $root[11] = 0x08

  LD-WriteSectors -DiskNumber $disk.Number -Lba $plan.root_dir_first_lba -Bytes $root -BytesPerSector $bps

  Write-Host ("FORMAT_COMPLETE disk=" + $disk.Number) -ForegroundColor Green

  if($EmitReceipt){
    $receipt = [ordered]@{
      schema = "storage.receipt.v1"
      action = "format-fat32-owned"
      time_utc = [DateTime]::UtcNow.ToString("o")
      host = $env:COMPUTERNAME
      disk_number = $plan.disk_number
      device_id = $plan.device_id
      label = $plan.volume_label
      token = "FORMAT_FAT32_OWNED_OK"
      ok = $true
      plan_sha256 = FMT-Sha256HexTextLf (FMT-ToCanonJson $plan)
    }

    FMT-EmitReceipt $RepoRoot $receipt
  }

  Write-Host "FORMAT_FAT32_OWNED_OK" -ForegroundColor Green

  exit 0
}
catch {

  $msg = $_.Exception.Message
  Write-Host $msg -ForegroundColor Red

  if($EmitReceipt){
    try{
      $receipt = [ordered]@{
        schema = "storage.receipt.v1"
        action = "format-fat32-owned-fail"
        time_utc = [DateTime]::UtcNow.ToString("o")
        host = $env:COMPUTERNAME
        disk_number = $DiskNumber
        device_id = $DeviceId
        label = $Label
        reason = $msg
        ok = $false
      }

      FMT-EmitReceipt $RepoRoot $receipt
    } catch {}
  }

  exit 1
}
