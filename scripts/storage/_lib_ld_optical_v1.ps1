param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDOPT-EvaluateMedia(
  [object]$Facts,
  [string]$ExpectedDeviceName,
  [UInt64]$ExpectedBytes,
  [string]$ExpectedVolumeSerialSha256,
  [UInt64]$MaxBytes,
  [Int64]$DestinationFreeBytes
){
  $blockers=@()
  if($null-eq$Facts){return @("OPTICAL_DEVICE_NOT_FOUND")}
  if(-not[bool]$Facts.media_loaded){return @("NO_MEDIA")}
  if([string]::IsNullOrWhiteSpace($ExpectedDeviceName)){$blockers+="EXPECTED_DEVICE_NAME_REQUIRED"}
  elseif(([string]$Facts.device_name).Trim()-cne$ExpectedDeviceName.Trim()){$blockers+="OPTICAL_DEVICE_NAME_MISMATCH"}
  if($ExpectedBytes-lt 1-or$MaxBytes-ne$ExpectedBytes){$blockers+="EXACT_MEDIA_BOUND_REQUIRED"}
  if([UInt64]$Facts.size_bytes-ne$ExpectedBytes){$blockers+="MEDIA_SIZE_MISMATCH"}
  if($ExpectedVolumeSerialSha256-notmatch"^[a-f0-9]{64}$"){$blockers+="EXPECTED_VOLUME_SERIAL_SHA256_REQUIRED"}
  elseif(([string]$Facts.volume_serial_sha256).Trim().ToLowerInvariant()-cne$ExpectedVolumeSerialSha256.Trim().ToLowerInvariant()){$blockers+="VOLUME_SERIAL_MISMATCH"}
  if($DestinationFreeBytes-lt 0){$blockers+="DESTINATION_SPACE_UNKNOWN"}
  elseif([UInt64]$DestinationFreeBytes-lt$ExpectedBytes){$blockers+="DESTINATION_SPACE_INSUFFICIENT"}
  return @($blockers|Sort-Object -Unique)
}

function LDOPT-OpenVolumeRead([string]$DriveLetter){
  $letter=$DriveLetter.Trim().TrimEnd(":").ToUpperInvariant()
  if($letter-notmatch"^[A-Z]$"){throw("OPTICAL_DRIVE_LETTER_INVALID:"+$DriveLetter)}
  return New-Object IO.FileStream(("\\.\"+$letter+":"),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
}

function LDOPT-ExportModuleInfo(){return [ordered]@{schema="ld.optical.lib.info.v1";name="_lib_ld_optical_v1.ps1";provides=@("LDOPT-EvaluateMedia","LDOPT-OpenVolumeRead")}}
