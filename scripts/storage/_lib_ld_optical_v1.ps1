param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDOPT-EvaluateMedia(
  [object]$Facts,
  [string]$ExpectedDeviceName,
  [UInt64]$ExpectedBytes,
  [string]$ExpectedMediaFingerprintSha256,
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
  if(-not[bool]$Facts.read_probe_ok){$blockers+="RAW_MEDIA_READ_PROBE_FAILED"}
  if($ExpectedMediaFingerprintSha256-notmatch"^[a-f0-9]{64}$"){$blockers+="EXPECTED_MEDIA_FINGERPRINT_REQUIRED"}
  elseif(([string]$Facts.media_fingerprint_sha256).Trim().ToLowerInvariant()-cne$ExpectedMediaFingerprintSha256.Trim().ToLowerInvariant()){$blockers+="MEDIA_FINGERPRINT_MISMATCH"}
  if($DestinationFreeBytes-lt 0){$blockers+="DESTINATION_SPACE_UNKNOWN"}
  elseif([UInt64]$DestinationFreeBytes-lt$ExpectedBytes){$blockers+="DESTINATION_SPACE_INSUFFICIENT"}
  return @($blockers|Sort-Object -Unique)
}

function LDOPT-ProbeStream([System.IO.Stream]$Stream,[string]$DeviceName,[int]$SampleBytes=65536){
  if($null-eq$Stream-or-not$Stream.CanRead-or-not$Stream.CanSeek){throw "OPTICAL_STREAM_NOT_PROBEABLE"}
  if($SampleBytes-lt 2048){throw "OPTICAL_SAMPLE_TOO_SMALL"}
  $length=[UInt64]$Stream.Length
  if($length-lt 1){throw "OPTICAL_LENGTH_UNAVAILABLE"}
  $sampleLength=[int][Math]::Min([UInt64]$SampleBytes,$length)
  $first=New-Object byte[] $sampleLength;[void]$Stream.Seek(0,[IO.SeekOrigin]::Begin);$firstRead=0
  while($firstRead-lt$sampleLength){$n=$Stream.Read($first,$firstRead,$sampleLength-$firstRead);if($n-le 0){throw "OPTICAL_FIRST_SAMPLE_SHORT_READ"};$firstRead+=$n}
  $last=New-Object byte[] $sampleLength;[void]$Stream.Seek(([Int64]$length-$sampleLength),[IO.SeekOrigin]::Begin);$lastRead=0
  while($lastRead-lt$sampleLength){$n=$Stream.Read($last,$lastRead,$sampleLength-$lastRead);if($n-le 0){throw "OPTICAL_LAST_SAMPLE_SHORT_READ"};$lastRead+=$n}
  $metadata=[Text.Encoding]::UTF8.GetBytes(($DeviceName+"`n"+[string]$length+"`n"))
  $combined=New-Object byte[] ($metadata.Length+$first.Length+$last.Length)
  [Array]::Copy($metadata,0,$combined,0,$metadata.Length);[Array]::Copy($first,0,$combined,$metadata.Length,$first.Length);[Array]::Copy($last,0,$combined,$metadata.Length+$first.Length,$last.Length)
  $sha=[Security.Cryptography.SHA256]::Create();try{$hash=$sha.ComputeHash($combined)}finally{$sha.Dispose()}
  $builder=New-Object Text.StringBuilder;foreach($byte in $hash){[void]$builder.Append($byte.ToString("x2"))}
  return [ordered]@{size_bytes=$length;sample_bytes=$sampleLength;media_fingerprint_sha256=$builder.ToString()}
}

function LDOPT-OpenVolumeRead([string]$DriveLetter){
  $letter=$DriveLetter.Trim().TrimEnd(":").ToUpperInvariant()
  if($letter-notmatch"^[A-Z]$"){throw("OPTICAL_DRIVE_LETTER_INVALID:"+$DriveLetter)}
  return New-Object IO.FileStream(("\\.\"+$letter+":"),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
}

function LDOPT-ExportModuleInfo(){return [ordered]@{schema="ld.optical.lib.info.v1";name="_lib_ld_optical_v1.ps1";provides=@("LDOPT-EvaluateMedia","LDOPT-ProbeStream","LDOPT-OpenVolumeRead")}}
