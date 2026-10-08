param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$DestinationRoot,
  [Parameter(Mandatory=$true)][string]$ProfileLabel,
  [Parameter(Mandatory=$true)][ValidateSet("file_backup","disk_image","optical_image","device_export")][string]$BackupMode,
  [Parameter(Mandatory=$true)][string]$DeviceName,
  [Parameter(Mandatory=$true)][string]$DeviceIdentitySha256,
  [string]$BackupId="",
  [UInt64]$MinFreeBytes=1073741824,
  [switch]$Execute,
  [switch]$OwnedTestFixture
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Add-Unique([object[]]$Items,[string]$Value){$r=@($Items);if(-not($r-contains$Value)){$r+=$Value};return @($r)}
function Write-Lf([string]$Path,[string]$Text){$t=($Text-replace"`r`n","`n")-replace"`r","`n";if(-not$t.EndsWith("`n")){$t+="`n"};[IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_ld_receipts_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_ld_destination_profile_v1.ps1")
$DestinationRoot=LDDST-FullPath $DestinationRoot;if([string]::IsNullOrWhiteSpace($BackupId)){$BackupId=[DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss-fffZ")}
$setupScript=Join-Path $PSScriptRoot "ld_backup_destination_setup_v1.ps1";$workspaceScript=Join-Path $PSScriptRoot "ld_backup_workspace_v1.ps1";$schemaDir=Join-Path $RepoRoot "schemas";$blockers=@()
$setupArgs=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$setupScript,"-RepoRoot",$RepoRoot,"-DestinationRoot",$DestinationRoot,"-ProfileLabel",$ProfileLabel,"-MinFreeBytes",[string]$MinFreeBytes);if($OwnedTestFixture){$setupArgs+="-OwnedTestFixture"};if($Execute){$setupArgs+="-Execute"}
$setupOutput=& powershell.exe @setupArgs;if($LASTEXITCODE-ne 0){throw("DESTINATION_SETUP_EXIT_NONZERO:"+[string]$LASTEXITCODE)};$setup=LDREC-ReadReceiptFromOutput -Output $setupOutput -ExpectedSchema "ld.backup.destination_setup.receipt.v1" -SchemaDirectory $schemaDir
$profileId=[string]$setup.profile_id;$profileHash=[string]$setup.profile_sha256;$layout=LDDST-Layout $DestinationRoot;$base=LDDST-ModeFolder -Profile ([pscustomobject]@{folder_map=[pscustomobject]$layout}) -Mode $BackupMode;$deviceSegment=(LDDST-SafeSegment $DeviceName "device")+"--"+$(if($DeviceIdentitySha256.Length-ge 12){$DeviceIdentitySha256.Substring(0,12).ToLowerInvariant()}else{"invalid"});$workspaceRoot=Join-Path (Join-Path $base $deviceSegment) $BackupId;$payload=Join-Path $workspaceRoot "payload";$metadata=Join-Path $workspaceRoot "metadata";$receipts=Join-Path $workspaceRoot "receipts";$logs=Join-Path $workspaceRoot "logs"
$workspaceStatus="deferred";$workspace=$null
if(-not[bool]$setup.ok){foreach($reason in @($setup.blockers)){$blockers=Add-Unique $blockers ([string]$reason)}}elseif($Execute){$workspaceArgs=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$workspaceScript,"-RepoRoot",$RepoRoot,"-DestinationRoot",$DestinationRoot,"-BackupMode",$BackupMode,"-DeviceName",$DeviceName,"-DeviceIdentitySha256",$DeviceIdentitySha256,"-BackupId",$BackupId);if($OwnedTestFixture){$workspaceArgs+="-OwnedTestFixture"};$workspaceArgs+="-Execute";$workspaceOutput=& powershell.exe @workspaceArgs;if($LASTEXITCODE-ne 0){throw("WORKSPACE_SETUP_EXIT_NONZERO:"+[string]$LASTEXITCODE)};$workspace=LDREC-ReadReceiptFromOutput -Output $workspaceOutput -ExpectedSchema "ld.backup.workspace.receipt.v1" -SchemaDirectory $schemaDir;$workspaceStatus=[string]$workspace.execution_status;if(-not[bool]$workspace.ok){foreach($reason in @($workspace.blockers)){$blockers=Add-Unique $blockers ([string]$reason)}}else{$profileHash=[string]$workspace.destination_profile_sha256;$workspaceRoot=[string]$workspace.workspace_root;$payload=[string]$workspace.payload_path;$metadata=[string]$workspace.metadata_path;$receipts=[string]$workspace.receipts_path;$logs=[string]$workspace.logs_path}}
$ok=$false;$availability="blocked";$status="blocked";$writes=$false
if(-not$Execute-and[bool]$setup.ok){$ok=$true;$availability="available";$status="dry_run_ready"}
elseif($Execute-and[bool]$setup.ok-and$null-ne$workspace-and[bool]$workspace.ok){$ok=$true;$availability="available";$writes=([bool]$setup.writes_destination-or[bool]$workspace.writes_destination);if(([string]$setup.execution_status)-eq"already_configured"-and([string]$workspace.execution_status)-eq"already_configured"){$status="already_configured"}else{$status="created_verified"}}
elseif($Execute-and[bool]$setup.ok){$status="partially_configured";$availability="failed"}
elseif(([string]$setup.availability)-eq"failed"){$status="failed";$availability="failed"}
$receipt=[ordered]@{schema="ld.backup.one_click_setup.receipt.v1";event_type="ld.backup.one_click_setup.receipt.v1";ok=[bool]$ok;availability=$availability;repo_root=$RepoRoot;mode="one_click_backup_setup";destructive=$false;writes_source=$false;execute_requested=[bool]$Execute;destination_root=$DestinationRoot;profile_label=$ProfileLabel;destination_profile_id=$profileId;destination_profile_sha256=$profileHash;backup_mode=$BackupMode;backup_id=$BackupId;device_name=$DeviceName;device_identity_sha256=$DeviceIdentitySha256.ToLowerInvariant();workspace_root=$workspaceRoot;payload_path=$payload;metadata_path=$metadata;receipts_path=$receipts;logs_path=$logs;destination_setup_status=[string]$setup.execution_status;workspace_setup_status=$workspaceStatus;writes_destination=[bool]$writes;execution_status=$status;blockers=@($blockers);created_utc=[DateTime]::UtcNow.ToString("o")}
$outDir=Join-Path $RepoRoot "proofs\receipts\backup_one_click_setup";New-Item -ItemType Directory -Force -Path $outDir|Out-Null;$outPath=Join-Path $outDir ("backup_one_click_setup_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")+".json");$json=$receipt|ConvertTo-Json -Depth 30 -Compress;Write-Lf $outPath $json
Write-Output ("BACKUP_ONE_CLICK_SETUP_PATH: "+$outPath);Write-Output ("BACKUP_ONE_CLICK_SETUP_STATUS: "+$status);Write-Output $json;if($ok){Write-Output "LD_BACKUP_ONE_CLICK_SETUP_OK"}else{Write-Output "LD_BACKUP_ONE_CLICK_SETUP_BLOCKED"}
