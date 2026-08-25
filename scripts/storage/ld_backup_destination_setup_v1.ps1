param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$DestinationRoot,
  [Parameter(Mandatory=$true)][string]$ProfileLabel,
  [UInt64]$MinFreeBytes=1073741824,
  [switch]$Execute,
  [switch]$OwnedTestFixture,
  [switch]$SelfTestFailAfterDirectories
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Add-Unique([object[]]$Items,[string]$Value){$r=@($Items);if(-not($r-contains$Value)){$r+=$Value};return @($r)}
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Path $Path -ErrorAction Stop|Out-Null}}
function Write-Lf([string]$Path,[string]$Text){$t=($Text-replace"`r`n","`n")-replace"`r","`n";if(-not$t.EndsWith("`n")){$t+="`n"};[IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_ld_receipts_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_destination_profile_v1.ps1")
$DestinationRoot=LDDST-FullPath $DestinationRoot
$profilePath=LDDST-ProfilePath $DestinationRoot;$layout=LDDST-Layout $DestinationRoot
$blockers=@();$createdDirs=@();$rootCreated=$false;$writesDestination=$false;$rollbackPerformed=$false;$rollbackOk=$true
$profileId=LDDST-ProfileId -Root $DestinationRoot -Label $ProfileLabel;$profileHash="";$existingValid=$false
if([string]::IsNullOrWhiteSpace($ProfileLabel)-or$ProfileLabel.Length-gt 80){$blockers=Add-Unique $blockers "PROFILE_LABEL_INVALID"}
if($SelfTestFailAfterDirectories.IsPresent-and-not$OwnedTestFixture.IsPresent){$blockers=Add-Unique $blockers "SELFTEST_INJECTION_FORBIDDEN"}
$repoProofs=Join-Path $RepoRoot "proofs\selftest"
if(LDDST-IsSameOrNested -Candidate $DestinationRoot -Root $RepoRoot){if(-not($OwnedTestFixture.IsPresent-and(LDDST-IsSameOrNested -Candidate $DestinationRoot -Root $repoProofs))){$blockers=Add-Unique $blockers "REPOSITORY_DESTINATION_FORBIDDEN"}}
$parent=Split-Path -Parent $DestinationRoot;if([string]::IsNullOrWhiteSpace($parent)-or-not(Test-Path -LiteralPath $parent -PathType Container)){$blockers=Add-Unique $blockers "DESTINATION_PARENT_MISSING"}
$free=[UInt64]0
try{$driveInfo=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($DestinationRoot));$free=[UInt64]$driveInfo.AvailableFreeSpace}catch{$blockers=Add-Unique $blockers "DESTINATION_VOLUME_UNAVAILABLE"}
if($free-lt$MinFreeBytes){$blockers=Add-Unique $blockers "INSUFFICIENT_FREE_SPACE"}

if(Test-Path -LiteralPath $profilePath -PathType Leaf){
  try{
    $schema=LDREC-ConvertFromJson (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "schemas\ld.backup.destination_profile.v1.json"))
    $existing=LDREC-ConvertFromJson (Get-Content -Raw -LiteralPath $profilePath)
    LDREC-AssertReceiptAgainstSchema -Receipt $existing -Schema $schema -ExpectedSchema "ld.backup.destination_profile.v1"
    $profileHash=LDREC-HexSha256File $profilePath
    if(([string]$existing.profile_id)-cne$profileId){$blockers=Add-Unique $blockers "PROFILE_ID_MISMATCH"}
    if(-not(LDDST-IsSameOrNested -Candidate ([string]$existing.root_path) -Root $DestinationRoot)-or-not(LDDST-IsSameOrNested -Candidate $DestinationRoot -Root ([string]$existing.root_path))){$blockers=Add-Unique $blockers "PROFILE_ROOT_MISMATCH"}
    foreach($folder in @($layout.Values)){if(-not(Test-Path -LiteralPath $folder -PathType Container)){$blockers=Add-Unique $blockers "PROFILE_FOLDER_MISSING"}}
    $existingValid=(@($blockers).Count-eq 0)
  }catch{$blockers=Add-Unique $blockers ("PROFILE_INVALID:"+[string]$_.Exception.Message)}
}elseif(Test-Path -LiteralPath $DestinationRoot -PathType Container){
  $entries=@(Get-ChildItem -LiteralPath $DestinationRoot -Force -ErrorAction Stop)
  if($entries.Count-gt 0){$blockers=Add-Unique $blockers "UNMANAGED_NONEMPTY_ROOT"}
}

$preflightReady=(@($blockers).Count-eq 0);$executionAllowed=($Execute.IsPresent-and$preflightReady-and-not$existingValid);$executionFailed=$false
if($executionAllowed){
  $tempProfile=$profilePath+".partial"
  try{
    if(Test-Path -LiteralPath $tempProfile){throw "PROFILE_PARTIAL_COLLISION"}
    if(-not(Test-Path -LiteralPath $DestinationRoot -PathType Container)){EnsureDir $DestinationRoot;$createdDirs+= $DestinationRoot;$rootCreated=$true}
    foreach($folder in @($layout.Values)){if(-not(Test-Path -LiteralPath $folder -PathType Container)){EnsureDir $folder;$createdDirs+= $folder}}
    if($SelfTestFailAfterDirectories.IsPresent){throw "SELFTEST_FAILURE_AFTER_DIRECTORIES"}
    $writesDestination=$true;$createdUtc=[DateTime]::UtcNow.ToString("o");$profile=LDDST-NewProfile -Root $DestinationRoot -Label $ProfileLabel -CreatedUtc $createdUtc
    Write-Lf -Path $tempProfile -Text (LDREC-ToCanonJson $profile)
    $schema=LDREC-ConvertFromJson (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "schemas\ld.backup.destination_profile.v1.json"));$check=LDREC-ConvertFromJson (Get-Content -Raw -LiteralPath $tempProfile);LDREC-AssertReceiptAgainstSchema -Receipt $check -Schema $schema -ExpectedSchema "ld.backup.destination_profile.v1"
    [IO.File]::Move($tempProfile,$profilePath);$profileHash=LDREC-HexSha256File $profilePath
  }catch{
    $executionFailed=$true;$blockers=Add-Unique $blockers ("EXECUTION_FAILED:"+[string]$_.Exception.Message);$rollbackPerformed=$true
    if(Test-Path -LiteralPath $tempProfile){Remove-Item -LiteralPath $tempProfile -Force -ErrorAction SilentlyContinue}
    foreach($dir in @($createdDirs|Sort-Object Length -Descending)){try{if((Test-Path -LiteralPath $dir -PathType Container)-and@(Get-ChildItem -LiteralPath $dir -Force).Count-eq 0){Remove-Item -LiteralPath $dir -Force}}catch{$rollbackOk=$false}}
    if($rootCreated-and(Test-Path -LiteralPath $DestinationRoot -PathType Container)){try{if(@(Get-ChildItem -LiteralPath $DestinationRoot -File -Recurse -Force).Count-eq 0){Remove-Item -LiteralPath $DestinationRoot -Recurse -Force}}catch{$rollbackOk=$false}}
  }
}

$status="dry_run_blocked";$ok=$false;$availability="blocked"
if($existingValid){$status="already_configured";$ok=$true;$availability="available"}
elseif(-not$Execute.IsPresent-and$preflightReady){$status="dry_run_ready";$ok=$true;$availability="available"}
elseif($executionAllowed-and-not$executionFailed-and(Test-Path -LiteralPath $profilePath -PathType Leaf)){$status="created_verified";$ok=$true;$availability="available"}
elseif($executionFailed-and-not$rollbackOk){$status="execution_failed_rollback_incomplete";$availability="failed"}
elseif($executionFailed){$status="execution_failed";$availability="failed"}
$receipt=[ordered]@{schema="ld.backup.destination_setup.receipt.v1";event_type="ld.backup.destination_setup.receipt.v1";ok=[bool]$ok;availability=$availability;repo_root=$RepoRoot;mode="backup_destination_setup";destructive=$false;writes_source=$false;execute_requested=[bool]$Execute.IsPresent;root_path=$DestinationRoot;profile_label=$ProfileLabel;profile_path=$profilePath;profile_id=$profileId;profile_sha256=$profileHash;min_free_bytes=$MinFreeBytes;destination_free_bytes=$free;preflight_ready=[bool]$preflightReady;execution_allowed=[bool]$executionAllowed;writes_destination=[bool]$writesDestination;created_directory_count=[int]$createdDirs.Count;rollback_performed=[bool]$rollbackPerformed;rollback_ok=[bool]$rollbackOk;execution_status=$status;folders=$layout;blockers=@($blockers);created_utc=[DateTime]::UtcNow.ToString("o")}
$outDir=Join-Path $RepoRoot "proofs\receipts\backup_destination_setup";New-Item -ItemType Directory -Force -Path $outDir|Out-Null;$outPath=Join-Path $outDir ("backup_destination_setup_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")+".json");$json=$receipt|ConvertTo-Json -Depth 30 -Compress;Write-Lf $outPath $json
Write-Output ("BACKUP_DESTINATION_SETUP_PATH: "+$outPath);Write-Output ("BACKUP_DESTINATION_SETUP_STATUS: "+$status);Write-Output $json;if($ok){Write-Output "LD_BACKUP_DESTINATION_SETUP_OK"}else{Write-Output "LD_BACKUP_DESTINATION_SETUP_BLOCKED"}
