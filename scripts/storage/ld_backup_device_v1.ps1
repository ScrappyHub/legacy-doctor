param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$DiskNumber = -1,
  [string]$SourcePath = "",
  [ValidateSet("raw_image","file_copy")][string]$Mode = "raw_image",
  [int]$ChunkSizeBytes = 1048576
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
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
    foreach($x in @($Value)){
      $arr += ,(Canon $x)
    }
    return ,$arr
  }

  return ([string]$Value)
}

function ToCanonJson([object]$Value){
  return ((Canon $Value) | ConvertTo-Json -Depth 60 -Compress)
}

function Append-Receipt([string]$LedgerPath,[hashtable]$Receipt){
  $json = ToCanonJson $Receipt
  $hash = HexSha256TextLf $json

  $final = [ordered]@{}
  foreach($k in @($Receipt.Keys | Sort-Object)){
    $final[$k] = $Receipt[$k]
  }
  $final["receipt_hash"] = $hash

  Append-Utf8NoBomLf $LedgerPath (ToCanonJson $final)
  return $hash
}

function Get-DeviceIdFromDisk([int]$DiskNumber){
  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  $seed = "disk|" + `
    [string]$disk.Number + "|" + `
    [string]$disk.FriendlyName + "|" + `
    [string]$disk.SerialNumber + "|" + `
    [string]$disk.BusType + "|" + `
    [string]([UInt64]$disk.Size)

  return ("win.disk.v1:" + [string]$DiskNumber + ":" + (HexSha256TextLf $seed))
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$AcquireLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_acquire_v1.ps1"
$BackupSchema = Join-Path $RepoRoot "schemas\ld.device.backup.receipt.v1.json"

foreach($p in @($AcquireLib,$BackupSchema)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die "MISSING_DEP" $p
  }
}

. $AcquireLib

if($Mode -ne "raw_image"){
  Die "UNSUPPORTED_MODE" $Mode
}

$sourceKind = ""
$resolvedSourcePath = ""
$deviceId = ""
$sourceSizeBytes = [UInt64]0
$maxBytes = [UInt64]0

if(-not [string]::IsNullOrWhiteSpace($SourcePath)){
  $resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
  $sourceKind = "image_file"
  $deviceId = ("image.file.v1:" + (HexSha256TextLf $resolvedSourcePath))

  $fi = Get-Item -LiteralPath $resolvedSourcePath -ErrorAction Stop
  $sourceSizeBytes = [UInt64]$fi.Length
  $maxBytes = $sourceSizeBytes
}
elseif($DiskNumber -ge 0){
  $sourceKind = "physical_drive"
  $resolvedSourcePath = "\\.\PhysicalDrive" + $DiskNumber
  $deviceId = Get-DeviceIdFromDisk -DiskNumber $DiskNumber
  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  $sourceSizeBytes = [UInt64]$disk.Size
  $maxBytes = $sourceSizeBytes
}
else {
  Die "SOURCE_REQUIRED" "provide either -SourcePath or -DiskNumber"
}

$OutRoot = Join-Path $RepoRoot "proofs\acquire"
EnsureDir $OutRoot

$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$baseName = ""
if($sourceKind -eq "physical_drive"){
  $baseName = "disk_" + $DiskNumber + "_" + $stamp
} else {
  $baseName = "image_" + $stamp
}

$RunDir = Join-Path $OutRoot $baseName
EnsureDir $RunDir

$DestImagePath = Join-Path $RunDir ($baseName + ".img")
$ManifestPath = Join-Path $RunDir ($baseName + ".manifest.json")
$LedgerPath = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"

$copyResult = LDACQ-CopyRawImage `
  -SourcePath $resolvedSourcePath `
  -SourceKind $sourceKind `
  -DestImagePath $DestImagePath `
  -ChunkSizeBytes $ChunkSizeBytes `
  -MaxBytes $maxBytes

$imageSha256 = LDACQ-HexSha256File $DestImagePath

$manifest = [ordered]@{
  schema = "ld.device.backup.manifest.v1"
  repo_root = $RepoRoot
  device_id = $deviceId
  disk_number = $(if($DiskNumber -ge 0){ [int]$DiskNumber } else { $null })
  source_kind = $sourceKind
  source_path = $resolvedSourcePath
  mode = $Mode
  image_path = $DestImagePath
  chunk_size_bytes = [int]$ChunkSizeBytes
  source_size_bytes = [UInt64]$copyResult.source_size_bytes
  image_sha256 = $imageSha256
  chunk_count = [int]$copyResult.chunk_count
  chunks = @($copyResult.chunks)
}

Write-Utf8NoBomLf $ManifestPath (ToCanonJson $manifest)

$receipt = [ordered]@{
  schema = "ld.device.backup.receipt.v1"
  event_type = "ld.device.backup.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  device_id = $deviceId
  disk_number = $(if($DiskNumber -ge 0){ [int]$DiskNumber } else { $null })
  source_kind = $sourceKind
  source_path = $resolvedSourcePath
  mode = $Mode
  image_path = $DestImagePath
  manifest_path = $ManifestPath
  chunk_size_bytes = [int]$ChunkSizeBytes
  source_size_bytes = [UInt64]$copyResult.source_size_bytes
  image_sha256 = $imageSha256
  chunk_count = [int]$copyResult.chunk_count
}

$receiptHash = Append-Receipt -LedgerPath $LedgerPath -Receipt $receipt

Write-Host ("BACKUP_SOURCE: " + $resolvedSourcePath) -ForegroundColor Green
Write-Host ("BACKUP_IMAGE: " + $DestImagePath) -ForegroundColor Green
Write-Host ("BACKUP_MANIFEST: " + $ManifestPath) -ForegroundColor Green
Write-Host ("BACKUP_RECEIPT_HASH: " + $receiptHash) -ForegroundColor Green
Write-Output (ToCanonJson $receipt)
Write-Output "LD_BACKUP_DEVICE_OK"