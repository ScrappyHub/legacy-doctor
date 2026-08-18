param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SourceImage,
  [Parameter(Mandatory=$true)][string]$DestinationImage,
  [Parameter(Mandatory=$true)][string]$ExpectedSha256,
  [Parameter(Mandatory=$true)][UInt64]$MaxBytes,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Add-Unique([object[]]$Items,[string]$Value){$r=@($Items);if(-not ($r -contains $Value)){$r+=$Value};return @($r)}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Force -Path $dir|Out-Null};$t=($Text-replace"`r`n","`n")-replace"`r","`n";if(-not$t.EndsWith("`n")){$t+="`n"};[IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_ld_receipts_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_verified_image_v1.ps1")
$SourceImage=[IO.Path]::GetFullPath($SourceImage);$DestinationImage=[IO.Path]::GetFullPath($DestinationImage)
$temporaryPath=$DestinationImage+".legacy-doctor.partial";$ExpectedSha256=$ExpectedSha256.ToLowerInvariant()
$blockers=@();$sourceSize=[UInt64]0;$sourceHash=""
if(-not(Test-Path -LiteralPath $SourceImage -PathType Leaf)){$blockers=Add-Unique $blockers "SOURCE_IMAGE_MISSING"}else{$sourceSize=[UInt64](Get-Item -LiteralPath $SourceImage).Length}
if($ExpectedSha256 -notmatch "^[a-f0-9]{64}$"){$blockers=Add-Unique $blockers "EXPECTED_SHA256_INVALID"}
if($sourceSize -lt 1 -or $sourceSize -gt $MaxBytes){$blockers=Add-Unique $blockers "SOURCE_SIZE_OUT_OF_BOUNDS"}
if($SourceImage.Equals($DestinationImage,[StringComparison]::OrdinalIgnoreCase)){$blockers=Add-Unique $blockers "SOURCE_DESTINATION_SAME"}
if(-not(Test-Path -LiteralPath (Split-Path -Parent $DestinationImage) -PathType Container)){$blockers=Add-Unique $blockers "DESTINATION_PARENT_MISSING"}
if(Test-Path -LiteralPath $DestinationImage){$blockers=Add-Unique $blockers "DESTINATION_COLLISION"}
if(Test-Path -LiteralPath $temporaryPath){$blockers=Add-Unique $blockers "STALE_PARTIAL_COLLISION"}
if(@($blockers).Count -eq 0){$sourceHash=LDREC-HexSha256File $SourceImage;if($sourceHash -cne $ExpectedSha256){$blockers=Add-Unique $blockers "SOURCE_HASH_MISMATCH"}}

$preflightReady=(@($blockers).Count -eq 0);$executionAllowed=($Execute.IsPresent -and $preflightReady)
$writesDestination=$false;$bytesCopied=[UInt64]0;$sourceRecheckHash="";$destinationHash="";$sourceStable=$false;$destinationMatches=$false;$executionFailed=$false
if($executionAllowed){
  $stream=$null
  try{
    $stream=[IO.File]::Open($SourceImage,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $writesDestination=$true
    $result=LDIMG-CopyStreamVerified -SourceStream $stream -TemporaryPath $temporaryPath -ExpectedBytes $sourceSize
    $bytesCopied=[UInt64]$result.bytes_copied;$sourceHash=[string]$result.source_sha256;$sourceRecheckHash=[string]$result.source_recheck_sha256;$destinationHash=[string]$result.destination_sha256
    $sourceStable=[bool]$result.source_stable;$destinationMatches=[bool]$result.destination_matches
    if($sourceHash -cne $ExpectedSha256 -or $sourceRecheckHash -cne $ExpectedSha256){throw "SOURCE_HASH_MISMATCH"}
    if(-not $sourceStable){throw "SOURCE_CHANGED_DURING_RESTORE"};if(-not $destinationMatches){throw "DESTINATION_HASH_MISMATCH"}
    [IO.File]::Move($temporaryPath,$DestinationImage)
  }catch{$executionFailed=$true;$blockers=Add-Unique $blockers ("EXECUTION_FAILED:"+[string]$_.Exception.Message);if(Test-Path -LiteralPath $temporaryPath -PathType Leaf){Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue}}
  finally{if($null-ne$stream){$stream.Dispose()}}
}
$status="dry_run_blocked";$ok=$false;$availability="blocked"
if(-not$Execute.IsPresent -and $preflightReady){$status="dry_run_ready";$ok=$true;$availability="available"}
elseif($executionAllowed -and -not$executionFailed -and $sourceStable -and $destinationMatches){$status="executed_verified";$ok=$true;$availability="available"}
elseif($executionFailed){$status="execution_failed";$availability="failed"}
$receipt=[ordered]@{schema="ld.image.restore_file.receipt.v1";event_type="ld.image.restore_file.receipt.v1";ok=[bool]$ok;availability=$availability;repo_root=$RepoRoot;mode="verified_image_to_disposable_file";destructive=$false;writes_device=$false;device_restore=$false;source_image=$SourceImage;destination_image=$DestinationImage;expected_sha256=$ExpectedSha256;source_size_bytes=$sourceSize;max_bytes=$MaxBytes;execute_requested=[bool]$Execute.IsPresent;preflight_ready=[bool]$preflightReady;execution_allowed=[bool]$executionAllowed;writes_destination=[bool]$writesDestination;bytes_copied=$bytesCopied;source_sha256=$sourceHash;source_recheck_sha256=$sourceRecheckHash;destination_sha256=$destinationHash;source_stable=[bool]$sourceStable;destination_matches=[bool]$destinationMatches;execution_status=$status;blockers=@($blockers);created_utc=[DateTime]::UtcNow.ToString("o")}
$outDir=Join-Path $RepoRoot "proofs\receipts\image_restore_file";$outPath=Join-Path $outDir ("image_restore_file_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")+".json")
$json=$receipt|ConvertTo-Json -Depth 20 -Compress;Write-Utf8NoBomLf $outPath $json
Write-Output ("IMAGE_RESTORE_FILE_PATH: "+$outPath);Write-Output ("IMAGE_RESTORE_FILE_STATUS: "+$status);Write-Output $json
if($ok){Write-Output "LD_IMAGE_RESTORE_FILE_OK"}else{Write-Output "LD_IMAGE_RESTORE_FILE_BLOCKED"}

