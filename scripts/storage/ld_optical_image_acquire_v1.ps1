param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$DriveLetter,
  [string]$ExpectedDeviceName="",
  [UInt64]$ExpectedSizeBytes=0,
  [string]$ExpectedMediaFingerprintSha256="",
  [UInt64]$MaxBytes=0,
  [Parameter(Mandatory=$true)][string]$DestinationPath,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Add-Unique([object[]]$Items,[string]$Value){$r=@($Items);if(-not($r-contains$Value)){$r+=$Value};return @($r)}
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;EnsureDir $dir;$t=($Text-replace"`r`n","`n")-replace"`r","`n";if(-not$t.EndsWith("`n")){$t+="`n"};[IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_ld_receipts_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_verified_image_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_optical_v1.ps1")
$DriveLetter=$DriveLetter.Trim().TrimEnd(":").ToUpperInvariant()
if($DriveLetter-notmatch"^[A-Z]$"){throw("OPTICAL_DRIVE_LETTER_INVALID:"+$DriveLetter)}
$DestinationPath=[IO.Path]::GetFullPath($DestinationPath);$temporaryPath=$DestinationPath+".legacy-doctor.partial"
$device=$null;$logical=$null;$volume=$null
try{$device=Get-CimInstance Win32_CDROMDrive -ErrorAction Stop|Where-Object{([string]$_.Drive).TrimEnd(":")-eq$DriveLetter}|Select-Object -First 1}catch{$device=$null}
try{$logical=Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='"+$DriveLetter+":'") -ErrorAction Stop|Select-Object -First 1}catch{$logical=$null}
try{$volume=Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop}catch{$volume=$null}
$mediaLoaded=($null-ne$device-and[bool]$device.MediaLoaded)
$size=[UInt64]0;if($null-ne$logical-and$null-ne$logical.Size){$size=[UInt64]$logical.Size}elseif($null-ne$volume-and$null-ne$volume.Size){$size=[UInt64]$volume.Size}
$actualVolumeSerial=$(if($null-ne$logical){[string]$logical.VolumeSerialNumber}else{""})
$actualVolumeSerialSha256=$(if([string]::IsNullOrWhiteSpace($actualVolumeSerial)){""}else{LDREC-HexSha256TextLf $actualVolumeSerial})
$deviceName=$(if($null-ne$device){[string]$device.Name}else{""})
$readProbeOk=$false;$readProbeError="";$sampleBytes=0;$mediaFingerprint=""
if($mediaLoaded){$probeStream=$null;try{$probeStream=LDOPT-OpenVolumeRead $DriveLetter;$probe=LDOPT-ProbeStream -Stream $probeStream -DeviceName $deviceName;$size=[UInt64]$probe.size_bytes;$sampleBytes=[int]$probe.sample_bytes;$mediaFingerprint=[string]$probe.media_fingerprint_sha256;$readProbeOk=$true}catch{$readProbeError=[string]$_.Exception.Message}finally{if($null-ne$probeStream){$probeStream.Dispose()}}}
$facts=[ordered]@{media_loaded=[bool]$mediaLoaded;device_name=$deviceName;size_bytes=$size;volume_serial_sha256=$actualVolumeSerialSha256;read_probe_ok=[bool]$readProbeOk;media_fingerprint_sha256=$mediaFingerprint}
$destinationDisk=-1;$destinationFree=[Int64]-1;$blockers=@()
if(-not(Test-Path -LiteralPath (Split-Path -Parent $DestinationPath) -PathType Container)){$blockers=Add-Unique $blockers "DESTINATION_PARENT_MISSING"}
if(Test-Path -LiteralPath $DestinationPath){$blockers=Add-Unique $blockers "DESTINATION_COLLISION"};if(Test-Path -LiteralPath $temporaryPath){$blockers=Add-Unique $blockers "STALE_PARTIAL_COLLISION"}
try{$qualifier=Split-Path -Qualifier $DestinationPath;$letter=$qualifier.TrimEnd("\").TrimEnd(":");$destinationPartition=Get-Partition -DriveLetter $letter -ErrorAction Stop;$destinationDisk=[int]$destinationPartition.DiskNumber;$destinationVolume=Get-Volume -DriveLetter $letter -ErrorAction Stop;$destinationFree=[Int64]$destinationVolume.SizeRemaining}catch{$destinationDisk=-1;$destinationFree=-1}
foreach($reason in @(LDOPT-EvaluateMedia -Facts $facts -ExpectedDeviceName $ExpectedDeviceName -ExpectedBytes $ExpectedSizeBytes -ExpectedMediaFingerprintSha256 $ExpectedMediaFingerprintSha256 -MaxBytes $MaxBytes -DestinationFreeBytes $destinationFree)){$blockers=Add-Unique $blockers ([string]$reason)}
$noMedia=(@($blockers)-contains"NO_MEDIA");$preflightReady=(@($blockers).Count-eq 0);$executionAllowed=($Execute.IsPresent-and$preflightReady)
$writesDestination=$false;$bytesCopied=[UInt64]0;$sourceHash="";$sourceRecheckHash="";$destinationHash="";$sourceStable=$false;$destinationMatches=$false;$executionFailed=$false
if($executionAllowed){$stream=$null;try{$stream=LDOPT-OpenVolumeRead $DriveLetter;$writesDestination=$true;$result=LDIMG-CopyStreamVerified -SourceStream $stream -TemporaryPath $temporaryPath -ExpectedBytes $ExpectedSizeBytes;$bytesCopied=[UInt64]$result.bytes_copied;$sourceHash=[string]$result.source_sha256;$sourceRecheckHash=[string]$result.source_recheck_sha256;$destinationHash=[string]$result.destination_sha256;$sourceStable=[bool]$result.source_stable;$destinationMatches=[bool]$result.destination_matches;if(-not$sourceStable){throw "OPTICAL_SOURCE_CHANGED"};if(-not$destinationMatches){throw "DESTINATION_HASH_MISMATCH"};[IO.File]::Move($temporaryPath,$DestinationPath)}catch{$executionFailed=$true;$blockers=Add-Unique $blockers ("EXECUTION_FAILED:"+[string]$_.Exception.Message);if(Test-Path -LiteralPath $temporaryPath){Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue}}finally{if($null-ne$stream){$stream.Dispose()}}}
$status="dry_run_blocked";$ok=$false;$availability="blocked"
if($noMedia){$status="no_media";$ok=$true;$availability="waiting_for_media"}
elseif(-not$Execute.IsPresent-and$preflightReady){$status="dry_run_ready";$ok=$true;$availability="available"}
elseif($executionAllowed-and-not$executionFailed-and$sourceStable-and$destinationMatches){$status="executed_verified";$ok=$true;$availability="available"}
elseif($executionFailed){$status="execution_failed";$availability="failed"}
$receipt=[ordered]@{schema="ld.optical.image_acquire.receipt.v1";event_type="ld.optical.image_acquire.receipt.v1";ok=[bool]$ok;availability=$availability;repo_root=$RepoRoot;mode="optical_volume_read_only_image";destructive=$false;writes_source=$false;drive_letter=$DriveLetter;device_name=[string]$facts.device_name;media_loaded=[bool]$mediaLoaded;file_system=$(if($null-ne$volume){[string]$volume.FileSystem}else{""});volume_label=$(if($null-ne$volume){[string]$volume.FileSystemLabel}else{""});volume_serial_sha256=$actualVolumeSerialSha256;read_probe_ok=[bool]$readProbeOk;read_probe_error=$readProbeError;sample_bytes=[int]$sampleBytes;media_fingerprint_sha256=$mediaFingerprint;source_size_bytes=$size;expected_size_bytes=$ExpectedSizeBytes;max_bytes=$MaxBytes;destination_path=$DestinationPath;destination_disk_number=[int]$destinationDisk;execute_requested=[bool]$Execute.IsPresent;preflight_ready=[bool]$preflightReady;execution_allowed=[bool]$executionAllowed;writes_destination=[bool]$writesDestination;bytes_copied=$bytesCopied;source_sha256=$sourceHash;source_recheck_sha256=$sourceRecheckHash;destination_sha256=$destinationHash;source_stable=[bool]$sourceStable;destination_matches=[bool]$destinationMatches;execution_status=$status;blockers=@($blockers);created_utc=[DateTime]::UtcNow.ToString("o")}
$outDir=Join-Path $RepoRoot "proofs\receipts\optical_image_acquire";$outPath=Join-Path $outDir ("optical_image_acquire_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")+".json");$json=$receipt|ConvertTo-Json -Depth 30 -Compress;Write-Utf8NoBomLf $outPath $json
Write-Output ("OPTICAL_IMAGE_ACQUIRE_PATH: "+$outPath);Write-Output ("OPTICAL_IMAGE_ACQUIRE_STATUS: "+$status);Write-Output $json
if($ok){Write-Output "LD_OPTICAL_IMAGE_ACQUIRE_OK"}else{Write-Output "LD_OPTICAL_IMAGE_ACQUIRE_BLOCKED"}
