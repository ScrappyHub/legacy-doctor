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

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
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

function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
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

function Read-BytesAt([string]$Path,[UInt64]$Offset,[int]$Count){
  $fs = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try {
    [void]$fs.Seek([Int64]$Offset,[IO.SeekOrigin]::Begin)
    $buf = New-Object byte[] $Count
    $read = $fs.Read($buf,0,$buf.Length)
    if($read -ne $Count){
      Die "READ_SHORT" ($Path + ": offset=" + $Offset + " read=" + $read + " expected=" + $Count)
    }
    return $buf
  } finally {
    $fs.Dispose()
  }
}

function Compare-BytesExact([string]$Name,[byte[]]$Actual,[byte[]]$Expected){
  Require ($null -ne $Actual) "NULL_ACTUAL" $Name
  Require ($null -ne $Expected) "NULL_EXPECTED" $Name
  Require ($Actual.Length -eq $Expected.Length) "LEN_MISMATCH" ($Name + ": actual=" + $Actual.Length + " expected=" + $Expected.Length)

  for($i = 0; $i -lt $Actual.Length; $i++){
    if($Actual[$i] -ne $Expected[$i]){
      Die "BYTE_MISMATCH" ($Name + ": offset=" + $i + " actual=" + $Actual[$i] + " expected=" + $Expected[$i])
    }
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RawLib      = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib   = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib     = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$FormatFile  = Join-Path $RepoRoot "scripts\storage\ld_format_fat32_owned_v1.ps1"
$VerifyFile  = Join-Path $RepoRoot "scripts\storage\ld_verify_fat32_layout_v1.ps1"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$FormatFile,$VerifyFile)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

. $RawLib
. $LayoutLib
. $BootLib

$RuntimeDir = Join-Path $RepoRoot "proofs\receipts\fat32_owned_imagefile"
EnsureDir $RuntimeDir

$ImagePath = Join-Path $RuntimeDir "fat32_owned_test.img"
if(Test-Path -LiteralPath $ImagePath -PathType Leaf){
  Remove-Item -LiteralPath $ImagePath -Force
}

$DiskSizeBytes = [UInt64]4294967296
$BytesPerSector = 512

$plan = LDFAT-NewPlan `
  -DiskSizeBytes $DiskSizeBytes `
  -BytesPerSector $BytesPerSector `
  -DeviceId "win.disk.v1:test:imagefile" `
  -DiskNumber 777 `
  -Label "SDCARD" `
  -ClusterKiB 0

$mbr   = LDFAT-BuildMbrSector $plan
$boot  = LDBOOT-BuildBootSector $plan
$fsi   = LDBOOT-BuildFsInfoSector $plan
$bb    = LDBOOT-BuildBackupBootSector $plan
$fat0  = LDBOOT-BuildFatSector0 $plan
$root0 = LDBOOT-BuildRootDirSector0 $plan

# Create a sparse/truncated image file without allocating a 4 GiB byte array.
$createFs = [IO.File]::Open($ImagePath,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
  $createFs.SetLength([Int64]$DiskSizeBytes)
  $createFs.Flush()
} finally {
  $createFs.Dispose()
}

Require (Test-Path -LiteralPath $ImagePath -PathType Leaf) "IMAGE_CREATE_FAIL" $ImagePath

$actualLen = [UInt64](Get-Item -LiteralPath $ImagePath).Length
Require ($actualLen -eq $DiskSizeBytes) "IMAGE_LENGTH_BAD" ("actual=" + $actualLen + " expected=" + $DiskSizeBytes)

$fs = [IO.File]::Open($ImagePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
  [void]$fs.Seek(0,[IO.SeekOrigin]::Begin)
  $fs.Write($mbr,0,$mbr.Length)

  $bootOffset = [UInt64]$plan.partition_start_lba * [UInt64]$plan.bytes_per_sector
  [void]$fs.Seek([Int64]$bootOffset,[IO.SeekOrigin]::Begin)
  $fs.Write($boot,0,$boot.Length)

  $fsInfoOffset = $bootOffset + ([UInt64]$plan.fsinfo_sector * [UInt64]$plan.bytes_per_sector)
  [void]$fs.Seek([Int64]$fsInfoOffset,[IO.SeekOrigin]::Begin)
  $fs.Write($fsi,0,$fsi.Length)

  $backupOffset = $bootOffset + ([UInt64]$plan.backup_boot_sector * [UInt64]$plan.bytes_per_sector)
  [void]$fs.Seek([Int64]$backupOffset,[IO.SeekOrigin]::Begin)
  $fs.Write($bb,0,$bb.Length)

  $fat0Offset = [UInt64]$plan.fat1_start_lba * [UInt64]$plan.bytes_per_sector
  [void]$fs.Seek([Int64]$fat0Offset,[IO.SeekOrigin]::Begin)
  $fs.Write($fat0,0,$fat0.Length)

  $root0Offset = [UInt64]$plan.root_dir_first_lba * [UInt64]$plan.bytes_per_sector
  [void]$fs.Seek([Int64]$root0Offset,[IO.SeekOrigin]::Begin)
  $fs.Write($root0,0,$root0.Length)

  $fs.Flush()
} finally {
  $fs.Dispose()
}

Write-Host ("IMAGE_WRITE_OK: " + $ImagePath) -ForegroundColor Green

$mbrRead = Read-BytesAt -Path $ImagePath -Offset 0 -Count 512
Compare-BytesExact -Name "mbr" -Actual $mbrRead -Expected $mbr
Write-Host "PASS: image mbr bytes" -ForegroundColor Green

$bootRead = Read-BytesAt -Path $ImagePath -Offset ([UInt64]$plan.partition_start_lba * [UInt64]$plan.bytes_per_sector) -Count 512
Compare-BytesExact -Name "boot" -Actual $bootRead -Expected $boot
Write-Host "PASS: image boot bytes" -ForegroundColor Green

$fsiRead = Read-BytesAt -Path $ImagePath -Offset (([UInt64]$plan.partition_start_lba + [UInt64]$plan.fsinfo_sector) * [UInt64]$plan.bytes_per_sector) -Count 512
Compare-BytesExact -Name "fsinfo" -Actual $fsiRead -Expected $fsi
Write-Host "PASS: image fsinfo bytes" -ForegroundColor Green

$bbRead = Read-BytesAt -Path $ImagePath -Offset (([UInt64]$plan.partition_start_lba + [UInt64]$plan.backup_boot_sector) * [UInt64]$plan.bytes_per_sector) -Count 512
Compare-BytesExact -Name "backup_boot" -Actual $bbRead -Expected $bb
Write-Host "PASS: image backup boot bytes" -ForegroundColor Green

$fat0Read = Read-BytesAt -Path $ImagePath -Offset ([UInt64]$plan.fat1_start_lba * [UInt64]$plan.bytes_per_sector) -Count 512
Compare-BytesExact -Name "fat0" -Actual $fat0Read -Expected $fat0
Write-Host "PASS: image fat0 bytes" -ForegroundColor Green

$root0Read = Read-BytesAt -Path $ImagePath -Offset ([UInt64]$plan.root_dir_first_lba * [UInt64]$plan.bytes_per_sector) -Count 512
Compare-BytesExact -Name "root0" -Actual $root0Read -Expected $root0
Write-Host "PASS: image root0 bytes" -ForegroundColor Green

$hashes = [ordered]@{
  image = (HexSha256File $ImagePath)
  mbr = (HexSha256Bytes $mbrRead)
  boot = (HexSha256Bytes $bootRead)
  fsinfo = (HexSha256Bytes $fsiRead)
  backup_boot = (HexSha256Bytes $bbRead)
  fat0 = (HexSha256Bytes $fat0Read)
  root0 = (HexSha256Bytes $root0Read)
}
$hashesJson = ($hashes | ConvertTo-Json -Depth 20 -Compress)
Write-Host ("IMAGEFILE_HASHES: " + $hashesJson) -ForegroundColor Cyan

Write-Host "SELFTEST_LD_FAT32_OWNED_IMAGEFILE_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"