param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][int]$DiskNumber,
  [string]$DeviceId,
  [string]$Label = "SDCARD",
  [int]$ClusterKiB = 0,
  [string]$IUnderstand
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

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Append-Utf8NoBomLf([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Line -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($Path,$t,(Utf8NoBom))
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
  return ((Canon $Value) | ConvertTo-Json -Depth 100 -Compress)
}

function Sha256HexBytes([byte[]]$Bytes){
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

function Sha256HexTextLf([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  return (Sha256HexBytes ($enc.GetBytes($Text + "`n")))
}

function ReceiptPath([string]$Root){
  return (Join-Path $Root "proofs\receipts\storage.ndjson")
}

function Emit-Receipt([string]$Root,[hashtable]$Obj){
  $rp = ReceiptPath $Root
  $json = ToCanonJson $Obj
  $hash = Sha256HexTextLf $json

  $o2 = [ordered]@{}
  foreach($k in $Obj.Keys){
    $o2[$k] = $Obj[$k]
  }
  $o2["receipt_hash"] = $hash

  Append-Utf8NoBomLf -Path $rp -Line (ToCanonJson $o2)
  return $hash
}

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    Die "ADMIN_REQUIRED" "owned FAT32 format requires elevation"
  }
}

function Select-DiskTarget([int]$DiskNumber,[string]$DeviceId){
  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop

  if(-not [string]::IsNullOrWhiteSpace($DeviceId)){
    $facts = LD-GetDiskFacts -DiskNumber $DiskNumber
    if([string]$facts.unique_id -ne [string]$DeviceId){
      Die "DEVICE_ID_MISMATCH" ("disk=" + $DiskNumber)
    }
  }

  if($disk.IsBoot){
    Die "SAFETY_BLOCK_BOOT_DISK" ([string]$DiskNumber)
  }
  if($disk.IsSystem){
    Die "SAFETY_BLOCK_SYSTEM_DISK" ([string]$DiskNumber)
  }

  return $disk
}

function Clear-ExistingLayout([int]$DiskNumber){
  $parts = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue)
  foreach($p in $parts){
    try {
      Remove-Partition -DiskNumber $DiskNumber -PartitionNumber $p.PartitionNumber -Confirm:$false -ErrorAction Stop | Out-Null
    } catch { }
  }

  try {
    Clear-Disk -Number $DiskNumber -RemoveData -Confirm:$false -ErrorAction Stop | Out-Null
  } catch { }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RawLib    = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib   = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$VerifyPs1 = Join-Path $RepoRoot "scripts\storage\ld_verify_fat32_layout_v1.ps1"
$PlanPs1   = Join-Path $RepoRoot "scripts\storage\ld_plan_format_fat32_owned_v1.ps1"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$VerifyPs1,$PlanPs1)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die "MISSING_DEP" $p
  }
}

. $RawLib
. $LayoutLib
. $BootLib

Require-Admin

$selected = Select-DiskTarget -DiskNumber $DiskNumber -DeviceId $DeviceId

$tokenExpected = "ERASE_DISK_" + $DiskNumber
if([string]::IsNullOrWhiteSpace($IUnderstand)){
  Die "SAFETY_TOKEN_REQUIRED" $tokenExpected
}
if($IUnderstand -ne $tokenExpected){
  Die "SAFETY_TOKEN_BAD" ("expected=" + $tokenExpected)
}

$facts = LD-GetDiskFacts -DiskNumber $DiskNumber

$actualDeviceId = ""
if(-not [string]::IsNullOrWhiteSpace($DeviceId)){
  $actualDeviceId = $DeviceId
} else {
  $uid = ""
  try {
    if($selected.UniqueId){ $uid = [string]$selected.UniqueId }
  } catch { $uid = "" }

  $base = ("disk_number=" + $selected.Number + "|unique_id=" + $uid + "|size=" + $selected.Size + "|name=" + $selected.FriendlyName)
  $actualDeviceId = "win.disk.v1:" + $selected.Number + ":" + (Sha256HexTextLf $base)
}

$t0 = [DateTime]::UtcNow.ToString("o")

$plan = LDFAT-NewPlan `
  -DiskSizeBytes ([UInt64]$facts.size_bytes) `
  -BytesPerSector ([int]$facts.logical_sector_size) `
  -DeviceId $actualDeviceId `
  -DiskNumber $DiskNumber `
  -Label $Label `
  -ClusterKiB $ClusterKiB

$planReceipt = [ordered]@{
  schema = "storage.receipt.v1"
  action = "plan-format-fat32-owned"
  formatter = "owned"
  ok = $true
  time_utc = [DateTime]::UtcNow.ToString("o")
  host = $env:COMPUTERNAME
  disk_number = [int]$DiskNumber
  device_id = $actualDeviceId
  size_bytes = [UInt64]$facts.size_bytes
  bytes_per_sector = [int]$facts.logical_sector_size
  partition_style = [string]$plan.partition_style
  partition_start_lba = [UInt64]$plan.partition_start_lba
  partition_size_lba = [UInt64]$plan.partition_size_lba
  sectors_per_cluster = [UInt32]$plan.sectors_per_cluster
  cluster_size_bytes = [UInt64]$plan.cluster_size_bytes
  reserved_sectors = [UInt16]$plan.reserved_sectors
  fat_count = [UInt16]$plan.fat_count
  fat_size_sectors = [UInt32]$plan.fat_size_sectors
  root_cluster = [UInt32]$plan.root_cluster
  fsinfo_sector = [UInt16]$plan.fsinfo_sector
  backup_boot_sector = [UInt16]$plan.backup_boot_sector
  volume_label = [string]$plan.volume_label
}
[void](Emit-Receipt -Root $RepoRoot -Obj $planReceipt)

$mbr = LDFAT-BuildMbrSector $plan
$boot = LDBOOT-BuildBootSector $plan
$fsi  = LDBOOT-BuildFsInfoSector $plan
$bootBackup = LDBOOT-BuildBackupBootSector $plan
$fat0 = LDBOOT-BuildFatSector0 $plan
$root0 = LDBOOT-BuildRootDirSector0 $plan

$fat1Lba = [UInt64]$plan.fat1_start_lba
$fat2Lba = [UInt64]$plan.fat2_start_lba
$dataLba = [UInt64]$plan.data_start_lba
$partLba = [UInt64]$plan.partition_start_lba
$fsiLba  = $partLba + [UInt64]$plan.fsinfo_sector
$bakLba  = $partLba + [UInt64]$plan.backup_boot_sector

Clear-ExistingLayout -DiskNumber $DiskNumber

LD-WriteSector -DiskNumber $DiskNumber -Lba 0 -Bytes $mbr -BytesPerSector ([int]$facts.logical_sector_size)
LD-WriteSector -DiskNumber $DiskNumber -Lba $partLba -Bytes $boot -BytesPerSector ([int]$facts.logical_sector_size)
LD-WriteSector -DiskNumber $DiskNumber -Lba $fsiLba -Bytes $fsi -BytesPerSector ([int]$facts.logical_sector_size)
LD-WriteSector -DiskNumber $DiskNumber -Lba $bakLba -Bytes $bootBackup -BytesPerSector ([int]$facts.logical_sector_size)
LD-WriteSector -DiskNumber $DiskNumber -Lba $fat1Lba -Bytes $fat0 -BytesPerSector ([int]$facts.logical_sector_size)
LD-WriteSector -DiskNumber $DiskNumber -Lba $fat2Lba -Bytes $fat0 -BytesPerSector ([int]$facts.logical_sector_size)
LD-WriteSector -DiskNumber $DiskNumber -Lba $dataLba -Bytes $root0 -BytesPerSector ([int]$facts.logical_sector_size)

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$verifyOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyPs1 `
  -RepoRoot $RepoRoot `
  -DiskNumber $DiskNumber `
  -DeviceId $actualDeviceId `
  -ExpectedPartitionStartLba ([UInt64]$plan.partition_start_lba) `
  -ExpectedPartitionSizeLba ([UInt64]$plan.partition_size_lba) `
  -ExpectedBytesPerSector ([UInt16]$plan.bytes_per_sector) `
  -ExpectedSectorsPerCluster ([UInt32]$plan.sectors_per_cluster) `
  -ExpectedReservedSectors ([UInt16]$plan.reserved_sectors) `
  -ExpectedFatCount ([UInt16]$plan.fat_count) `
  -ExpectedFatSizeSectors ([UInt32]$plan.fat_size_sectors) `
  -ExpectedRootCluster ([UInt32]$plan.root_cluster) `
  -ExpectedFsInfoSector ([UInt16]$plan.fsinfo_sector) `
  -ExpectedBackupBootSector ([UInt16]$plan.backup_boot_sector) 2>&1

$verifyText = (@(@($verifyOut)) -join "`n")
if($LASTEXITCODE -ne 0 -or $verifyText -notmatch "FAT32_VERIFY_OK"){
  $failObj = [ordered]@{
    schema = "storage.receipt.v1"
    action = "format-fat32-owned-fail"
    formatter = "owned"
    ok = $false
    time_start_utc = $t0
    time_end_utc = [DateTime]::UtcNow.ToString("o")
    host = $env:COMPUTERNAME
    disk_number = [int]$DiskNumber
    device_id = $actualDeviceId
    stage = "verify"
    reason_code = "VERIFY_FAILED"
    verifier_output = $verifyText
  }
  [void](Emit-Receipt -Root $RepoRoot -Obj $failObj)
  Die "VERIFY_FAILED" $verifyText
}

$t1 = [DateTime]::UtcNow.ToString("o")

$formatObj = [ordered]@{
  schema = "storage.receipt.v1"
  action = "format-fat32-owned"
  formatter = "owned"
  ok = $true
  time_start_utc = $t0
  time_end_utc = $t1
  host = $env:COMPUTERNAME
  disk_number = [int]$DiskNumber
  device_id = $actualDeviceId
  size_bytes = [UInt64]$facts.size_bytes
  partition_style = [string]$plan.partition_style
  partition_type_hex = [string]$plan.partition_type_hex
  partition_start_lba = [UInt64]$plan.partition_start_lba
  partition_size_lba = [UInt64]$plan.partition_size_lba
  bytes_per_sector = [UInt16]$plan.bytes_per_sector
  sectors_per_cluster = [UInt32]$plan.sectors_per_cluster
  cluster_size_bytes = [UInt64]$plan.cluster_size_bytes
  reserved_sectors = [UInt16]$plan.reserved_sectors
  fat_count = [UInt16]$plan.fat_count
  fat_size_sectors = [UInt32]$plan.fat_size_sectors
  root_cluster = [UInt32]$plan.root_cluster
  fsinfo_sector = [UInt16]$plan.fsinfo_sector
  backup_boot_sector = [UInt16]$plan.backup_boot_sector
  volume_label = [string]$plan.volume_label
  volume_serial = [UInt32]$plan.volume_serial
  mbr_sha256 = (Sha256HexBytes $mbr)
  boot_sha256 = (Sha256HexBytes $boot)
  fsinfo_sha256 = (Sha256HexBytes $fsi)
  backup_boot_sha256 = (Sha256HexBytes $bootBackup)
  fat0_sha256 = (Sha256HexBytes $fat0)
  root0_sha256 = (Sha256HexBytes $root0)
  verifier_output = $verifyText
}

$rh = Emit-Receipt -Root $RepoRoot -Obj $formatObj

Write-Host ("FORMAT_FAT32_OWNED_OK: disk=" + $DiskNumber + " label=" + [string]$plan.volume_label) -ForegroundColor Green
Write-Host ("RECEIPT_OK: " + $rh) -ForegroundColor Green
Write-Output "FORMAT_FAT32_OWNED_OK"
