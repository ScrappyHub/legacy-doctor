param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][int]$DiskNumber,
  [Parameter(Mandatory=$true)][UInt64]$ExpectedSizeBytes,
  [Parameter(Mandatory=$true)][string]$ExpectedSerialNumber,
  [Parameter(Mandatory=$true)][string]$DestinationPath,
  [Parameter(Mandatory=$true)][UInt64]$MaxBytes,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
function Add-Unique([object[]]$Items,[string]$Value){ $r=@($Items);if(-not ($r -contains $Value)){$r+=$Value};return @($r) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir=Split-Path -Parent $Path;if(-not (Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
  $normalized=($Text -replace "`r`n","`n") -replace "`r","`n";if(-not $normalized.EndsWith("`n")){$normalized+="`n"}
  [IO.File]::WriteAllText($Path,$normalized,[Text.UTF8Encoding]::new($false))
}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_ld_receipts_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_rawdisk_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_verified_image_v1.ps1")

$facts=LD-GetDiskFacts -DiskNumber $DiskNumber
$DestinationPath=[IO.Path]::GetFullPath($DestinationPath)
$temporaryPath=$DestinationPath+".legacy-doctor.partial"
$destinationParent=Split-Path -Parent $DestinationPath
$destinationDiskNumber=-1
$blockers=@()

if(-not (Test-Path -LiteralPath $destinationParent -PathType Container)){ $blockers=Add-Unique $blockers "DESTINATION_PARENT_MISSING" }
if(Test-Path -LiteralPath $DestinationPath){ $blockers=Add-Unique $blockers "DESTINATION_COLLISION" }
if(Test-Path -LiteralPath $temporaryPath){ $blockers=Add-Unique $blockers "STALE_PARTIAL_COLLISION" }
try {
  $qualifier=Split-Path -Qualifier $DestinationPath
  if(-not [string]::IsNullOrWhiteSpace($qualifier)){
    $driveLetter=$qualifier.TrimEnd("\").TrimEnd(":")
    $destinationDiskNumber=[int](Get-Partition -DriveLetter $driveLetter -ErrorAction Stop).DiskNumber
  }
} catch { $destinationDiskNumber=-1 }
foreach($reason in @(LDIMG-EvaluatePhysicalSource -Facts $facts -ExpectedDiskNumber $DiskNumber -ExpectedBytes $ExpectedSizeBytes -ExpectedSerialNumber $ExpectedSerialNumber -MaxBytes $MaxBytes -DestinationDiskNumber $destinationDiskNumber)){
  $blockers=Add-Unique $blockers ([string]$reason)
}

$preflightReady=(@($blockers).Count -eq 0)
$executionAllowed=($Execute.IsPresent -and $preflightReady)
$writesDestination=$false
$bytesCopied=[UInt64]0
$sourceHash="";$sourceRecheckHash="";$destinationHash=""
$sourceStable=$false;$destinationMatches=$false
$executionFailed=$false

if($executionAllowed){
  $sourceStream=$null
  try {
    $sourceStream=LD-OpenRawDiskRead -DiskNumber $DiskNumber
    $writesDestination=$true
    $result=LDIMG-CopyStreamVerified -SourceStream $sourceStream -TemporaryPath $temporaryPath -ExpectedBytes $ExpectedSizeBytes
    $bytesCopied=[UInt64]$result.bytes_copied
    $sourceHash=[string]$result.source_sha256
    $sourceRecheckHash=[string]$result.source_recheck_sha256
    $destinationHash=[string]$result.destination_sha256
    $sourceStable=[bool]$result.source_stable
    $destinationMatches=[bool]$result.destination_matches
    if($bytesCopied -ne $ExpectedSizeBytes){ throw "COPIED_SIZE_MISMATCH" }
    if(-not $sourceStable){ throw "SOURCE_CHANGED_DURING_ACQUISITION" }
    if(-not $destinationMatches){ throw "DESTINATION_HASH_MISMATCH" }
    [IO.File]::Move($temporaryPath,$DestinationPath)
  } catch {
    $executionFailed=$true
    $blockers=Add-Unique $blockers ("EXECUTION_FAILED:"+[string]$_.Exception.Message)
    if(Test-Path -LiteralPath $temporaryPath -PathType Leaf){ Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
  } finally {
    if($null -ne $sourceStream){$sourceStream.Dispose()}
  }
}

$status="dry_run_blocked";$ok=$false;$availability="blocked"
if(-not $Execute.IsPresent -and $preflightReady){$status="dry_run_ready";$ok=$true;$availability="available"}
elseif($executionAllowed -and -not $executionFailed -and $destinationMatches -and $sourceStable){$status="executed_verified";$ok=$true;$availability="available"}
elseif($executionFailed){$status="execution_failed";$availability="failed"}

$receipt=[ordered]@{
  schema="ld.raw_image.acquire.receipt.v1";event_type="ld.raw_image.acquire.receipt.v1";ok=[bool]$ok;availability=$availability
  repo_root=$RepoRoot;mode="physical_disk_read_only_image";destructive=$false;writes_source=$false;full_disk_image=$true
  disk_number=[int]$facts.disk_number;source_path=[string]$facts.path;source_name=[string]$facts.friendly_name;source_bus_type=[string]$facts.bus_type
  source_size_bytes=[UInt64]$facts.size_bytes;source_serial_sha256=(LDREC-HexSha256TextLf ([string]$facts.serial_number).Trim())
  destination_path=$DestinationPath;destination_disk_number=[int]$destinationDiskNumber;expected_size_bytes=$ExpectedSizeBytes;max_bytes=$MaxBytes
  execute_requested=[bool]$Execute.IsPresent;preflight_ready=[bool]$preflightReady;execution_allowed=[bool]$executionAllowed;writes_destination=[bool]$writesDestination
  bytes_copied=$bytesCopied;source_sha256=$sourceHash;source_recheck_sha256=$sourceRecheckHash;destination_sha256=$destinationHash
  source_stable=[bool]$sourceStable;destination_matches=[bool]$destinationMatches;execution_status=$status;blockers=@($blockers);created_utc=[DateTime]::UtcNow.ToString("o")
}
$outDir=Join-Path $RepoRoot "proofs\receipts\raw_image_acquire"
$outPath=Join-Path $outDir ("raw_image_acquire_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")+".json")
$json=$receipt|ConvertTo-Json -Depth 20 -Compress
Write-Utf8NoBomLf $outPath $json
Write-Output ("RAW_IMAGE_ACQUIRE_PATH: "+$outPath)
Write-Output ("RAW_IMAGE_ACQUIRE_STATUS: "+$status)
Write-Output $json
if($ok){Write-Output "LD_RAW_IMAGE_ACQUIRE_OK"}else{Write-Output "LD_RAW_IMAGE_ACQUIRE_BLOCKED"}

