param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDIMG-Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }

function LDIMG-HashToHex([byte[]]$Hash){
  $builder = New-Object System.Text.StringBuilder
  foreach($byte in $Hash){ [void]$builder.Append($byte.ToString("x2")) }
  return $builder.ToString()
}

function LDIMG-HashStream([System.IO.Stream]$Stream,[UInt64]$ExpectedBytes,[int]$BufferBytes = 4194304){
  if($null -eq $Stream){ LDIMG-Die "NULL_SOURCE_STREAM" "" }
  if(-not $Stream.CanRead){ LDIMG-Die "SOURCE_STREAM_NOT_READABLE" "" }
  if(-not $Stream.CanSeek){ LDIMG-Die "SOURCE_STREAM_NOT_SEEKABLE" "" }
  if($ExpectedBytes -lt 1){ LDIMG-Die "EXPECTED_BYTES_INVALID" ([string]$ExpectedBytes) }
  if($BufferBytes -lt 4096){ LDIMG-Die "BUFFER_BYTES_INVALID" ([string]$BufferBytes) }

  [void]$Stream.Seek(0,[IO.SeekOrigin]::Begin)
  $buffer = New-Object byte[] $BufferBytes
  $remaining = [UInt64]$ExpectedBytes
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    while($remaining -gt 0){
      $wanted = [int][Math]::Min([UInt64]$buffer.Length,$remaining)
      $read = $Stream.Read($buffer,0,$wanted)
      if($read -le 0){ LDIMG-Die "SOURCE_SHORT_READ" ("remaining=" + [string]$remaining) }
      [void]$sha.TransformBlock($buffer,0,$read,$buffer,0)
      $remaining -= [UInt64]$read
    }
    [void]$sha.TransformFinalBlock((New-Object byte[] 0),0,0)
    return (LDIMG-HashToHex $sha.Hash)
  } finally {
    $sha.Dispose()
  }
}

function LDIMG-CopyStreamVerified(
  [System.IO.Stream]$SourceStream,
  [string]$TemporaryPath,
  [UInt64]$ExpectedBytes,
  [int]$BufferBytes = 4194304
){
  if(Test-Path -LiteralPath $TemporaryPath){ LDIMG-Die "TEMPORARY_PATH_COLLISION" $TemporaryPath }
  if($null -eq $SourceStream){ LDIMG-Die "NULL_SOURCE_STREAM" "" }
  if(-not $SourceStream.CanRead){ LDIMG-Die "SOURCE_STREAM_NOT_READABLE" "" }
  if(-not $SourceStream.CanSeek){ LDIMG-Die "SOURCE_STREAM_NOT_SEEKABLE" "" }

  [void]$SourceStream.Seek(0,[IO.SeekOrigin]::Begin)
  $buffer = New-Object byte[] $BufferBytes
  $remaining = [UInt64]$ExpectedBytes
  $copied = [UInt64]0
  $sourceSha = [Security.Cryptography.SHA256]::Create()
  $sourceHash = ""
  $destination = $null
  try {
    $destination = New-Object IO.FileStream($TemporaryPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,$BufferBytes,[IO.FileOptions]::SequentialScan)
    while($remaining -gt 0){
      $wanted = [int][Math]::Min([UInt64]$buffer.Length,$remaining)
      $read = $SourceStream.Read($buffer,0,$wanted)
      if($read -le 0){ LDIMG-Die "SOURCE_SHORT_READ" ("copied=" + [string]$copied + ":expected=" + [string]$ExpectedBytes) }
      $destination.Write($buffer,0,$read)
      [void]$sourceSha.TransformBlock($buffer,0,$read,$buffer,0)
      $copied += [UInt64]$read
      $remaining -= [UInt64]$read
    }
    [void]$sourceSha.TransformFinalBlock((New-Object byte[] 0),0,0)
    $sourceHash = LDIMG-HashToHex $sourceSha.Hash
    $destination.Flush($true)
  } finally {
    if($null -ne $destination){ $destination.Dispose() }
    $sourceSha.Dispose()
  }

  $destinationHash = LDREC-HexSha256File $TemporaryPath
  $sourceRecheckHash = LDIMG-HashStream -Stream $SourceStream -ExpectedBytes $ExpectedBytes -BufferBytes $BufferBytes
  return [ordered]@{
    bytes_copied = [UInt64]$copied
    source_sha256 = $sourceHash
    source_recheck_sha256 = $sourceRecheckHash
    destination_sha256 = $destinationHash
    source_stable = ($sourceHash -ceq $sourceRecheckHash)
    destination_matches = ($sourceHash -ceq $destinationHash)
  }
}

function LDIMG-EvaluatePhysicalSource(
  [object]$Facts,
  [int]$ExpectedDiskNumber,
  [UInt64]$ExpectedBytes,
  [string]$ExpectedSerialNumber,
  [UInt64]$MaxBytes,
  [int]$DestinationDiskNumber
){
  $blockers = @()
  if($null -eq $Facts){ return @("SOURCE_FACTS_MISSING") }
  if([int]$Facts.disk_number -ne $ExpectedDiskNumber){ $blockers += "DISK_NUMBER_MISMATCH" }
  if([bool]$Facts.is_boot){ $blockers += "BOOT_DISK_FORBIDDEN" }
  if([bool]$Facts.is_system){ $blockers += "SYSTEM_DISK_FORBIDDEN" }
  if([UInt64]$Facts.size_bytes -ne $ExpectedBytes){ $blockers += "SOURCE_SIZE_MISMATCH" }
  if($ExpectedBytes -lt 1 -or $MaxBytes -ne $ExpectedBytes){ $blockers += "FULL_DISK_BOUND_REQUIRED" }
  $actualSerial = ([string]$Facts.serial_number).Trim()
  if([string]::IsNullOrWhiteSpace($ExpectedSerialNumber)){ $blockers += "EXPECTED_SERIAL_REQUIRED" }
  elseif($actualSerial -cne $ExpectedSerialNumber.Trim()){ $blockers += "SOURCE_SERIAL_MISMATCH" }
  if($DestinationDiskNumber -lt 0){ $blockers += "DESTINATION_DISK_UNRESOLVED" }
  elseif($DestinationDiskNumber -eq $ExpectedDiskNumber){ $blockers += "SOURCE_DESTINATION_DISK_SAME" }
  return @($blockers | Sort-Object -Unique)
}

function LDIMG-ExportModuleInfo(){
  return [ordered]@{schema="ld.verified_image.lib.info.v1";name="_lib_ld_verified_image_v1.ps1";provides=@("LDIMG-HashStream","LDIMG-CopyStreamVerified","LDIMG-EvaluatePhysicalSource")}
}
