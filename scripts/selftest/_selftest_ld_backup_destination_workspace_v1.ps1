param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$Code,[string]$Detail){throw($Code+":"+$Detail)}
function Require([bool]$Condition,[string]$Code,[string]$Detail){if(-not$Condition){Die $Code $Detail}}
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")
$fixtureBase=Join-Path $RepoRoot "proofs\selftest\backup_destination_workspace";$allowed=[IO.Path]::GetFullPath((Join-Path $RepoRoot "proofs\selftest")).TrimEnd("\")+"\";$resolved=[IO.Path]::GetFullPath($fixtureBase)
Require ($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) "FIXTURE_PATH_OUTSIDE_SELFTEST" $resolved
if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force};EnsureDir $resolved
$setupScript=Join-Path $RepoRoot "scripts\storage\ld_backup_destination_setup_v1.ps1";$workspaceScript=Join-Path $RepoRoot "scripts\storage\ld_backup_workspace_v1.ps1";$oneClickScript=Join-Path $RepoRoot "scripts\storage\ld_backup_one_click_setup_v1.ps1";$schemaDir=Join-Path $RepoRoot "schemas"

function Run-Setup([string]$Root,[bool]$ExecuteNow,[bool]$InjectFailure=$false){$args=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$setupScript,"-RepoRoot",$RepoRoot,"-DestinationRoot",$Root,"-ProfileLabel","Fixture Vault","-MinFreeBytes","0","-OwnedTestFixture");if($ExecuteNow){$args+="-Execute"};if($InjectFailure){$args+="-SelfTestFailAfterDirectories"};$output=& powershell.exe @args;if($LASTEXITCODE-ne 0){Die "SETUP_EXIT_NONZERO" ([string]$LASTEXITCODE)};return (LDREC-ReadReceiptFromOutput -Output $output -ExpectedSchema "ld.backup.destination_setup.receipt.v1" -SchemaDirectory $schemaDir)}
function Run-Workspace([string]$Root,[string]$BackupId,[bool]$ExecuteNow){$identity=LDREC-HexSha256TextLf "fixture-ipod-identity";$args=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$workspaceScript,"-RepoRoot",$RepoRoot,"-DestinationRoot",$Root,"-BackupMode","disk_image","-DeviceName","Apple iPod Fixture","-DeviceIdentitySha256",$identity,"-BackupId",$BackupId,"-OwnedTestFixture");if($ExecuteNow){$args+="-Execute"};$output=& powershell.exe @args;if($LASTEXITCODE-ne 0){Die "WORKSPACE_EXIT_NONZERO" ([string]$LASTEXITCODE)};return (LDREC-ReadReceiptFromOutput -Output $output -ExpectedSchema "ld.backup.workspace.receipt.v1" -SchemaDirectory $schemaDir)}
function Run-OneClick([string]$Root,[bool]$ExecuteNow){$identity=LDREC-HexSha256TextLf "fixture-dvd-identity";$args=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$oneClickScript,"-RepoRoot",$RepoRoot,"-DestinationRoot",$Root,"-ProfileLabel","One Click Vault","-BackupMode","optical_image","-DeviceName","Fixture DVD","-DeviceIdentitySha256",$identity,"-BackupId","disc-001","-MinFreeBytes","0","-OwnedTestFixture");if($ExecuteNow){$args+="-Execute"};$output=& powershell.exe @args;if($LASTEXITCODE-ne 0){Die "ONE_CLICK_EXIT_NONZERO" ([string]$LASTEXITCODE)};return (LDREC-ReadReceiptFromOutput -Output $output -ExpectedSchema "ld.backup.one_click_setup.receipt.v1" -SchemaDirectory $schemaDir)}

$vault=Join-Path $resolved "vault"
$dry=Run-Setup $vault $false
Require ([bool]$dry.ok) "SETUP_DRY_NOT_OK" ([string]$dry.execution_status);Require (([string]$dry.execution_status)-eq"dry_run_ready") "SETUP_DRY_NOT_READY" ([string]$dry.execution_status);Require (-not(Test-Path -LiteralPath $vault)) "SETUP_DRY_WROTE" ""
$created=Run-Setup $vault $true
Require ([bool]$created.ok) "SETUP_EXECUTE_NOT_OK" ([string]$created.execution_status);Require (([string]$created.execution_status)-eq"created_verified") "SETUP_NOT_CREATED" ([string]$created.execution_status);Require ([int]$created.created_directory_count-ge 10) "LAYOUT_FOLDER_COUNT_BAD" ([string]$created.created_directory_count);Require (Test-Path -LiteralPath ([string]$created.profile_path) -PathType Leaf) "PROFILE_MISSING" "";$profileHash=[string]$created.profile_sha256
foreach($folder in @($created.folders.PSObject.Properties.Value)){Require (Test-Path -LiteralPath ([string]$folder) -PathType Container) "LAYOUT_FOLDER_MISSING" ([string]$folder)}
$repeat=Run-Setup $vault $true
Require ([bool]$repeat.ok) "SETUP_REPEAT_NOT_OK" ([string]$repeat.execution_status);Require (([string]$repeat.execution_status)-eq"already_configured") "SETUP_NOT_IDEMPOTENT" ([string]$repeat.execution_status);Require (([string]$repeat.profile_sha256)-ceq$profileHash) "PROFILE_HASH_CHANGED" ""

$workspaceDry=Run-Workspace $vault "backup-001" $false
Require ([bool]$workspaceDry.ok) "WORKSPACE_DRY_NOT_OK" ([string]$workspaceDry.execution_status);Require (-not(Test-Path -LiteralPath ([string]$workspaceDry.workspace_root))) "WORKSPACE_DRY_WROTE" ""
$workspace=Run-Workspace $vault "backup-001" $true
Require ([bool]$workspace.ok) "WORKSPACE_EXECUTE_NOT_OK" ([string]$workspace.execution_status);Require (([string]$workspace.execution_status)-eq"created_verified") "WORKSPACE_NOT_CREATED" ([string]$workspace.execution_status);foreach($path in @($workspace.payload_path,$workspace.metadata_path,$workspace.receipts_path,$workspace.logs_path)){Require (Test-Path -LiteralPath ([string]$path) -PathType Container) "WORKSPACE_FOLDER_MISSING" ([string]$path)};Require (Test-Path -LiteralPath ([string]$workspace.workspace_manifest_path) -PathType Leaf) "WORKSPACE_MANIFEST_MISSING" "";$workspaceHash=[string]$workspace.workspace_manifest_sha256
$workspaceRepeat=Run-Workspace $vault "backup-001" $true
Require (([string]$workspaceRepeat.execution_status)-eq"already_configured") "WORKSPACE_NOT_IDEMPOTENT" ([string]$workspaceRepeat.execution_status);Require (([string]$workspaceRepeat.workspace_manifest_sha256)-ceq$workspaceHash) "WORKSPACE_HASH_CHANGED" ""

$failureRoot=Join-Path $resolved "rollback-vault";$failed=Run-Setup $failureRoot $true $true
Require (-not[bool]$failed.ok) "INJECTED_FAILURE_NOT_FAILED" "";Require ([bool]$failed.rollback_performed) "ROLLBACK_NOT_PERFORMED" "";Require ([bool]$failed.rollback_ok) "ROLLBACK_NOT_OK" "";Require (-not(Test-Path -LiteralPath $failureRoot)) "ROLLBACK_ROOT_REMAINED" $failureRoot
$unmanaged=Join-Path $resolved "unmanaged";EnsureDir $unmanaged;[IO.File]::WriteAllText((Join-Path $unmanaged "user.txt"),"owned fixture",[Text.UTF8Encoding]::new($false));$blocked=Run-Setup $unmanaged $true
Require (-not[bool]$blocked.ok) "UNMANAGED_ROOT_NOT_BLOCKED" "";Require (@($blocked.blockers)-contains"UNMANAGED_NONEMPTY_ROOT") "UNMANAGED_REASON_MISSING" "";Require (Test-Path -LiteralPath (Join-Path $unmanaged "user.txt") -PathType Leaf) "UNMANAGED_FILE_CHANGED" ""
$escape=Run-Workspace $vault "..\escape" $true
Require (-not[bool]$escape.ok) "ESCAPE_ID_NOT_BLOCKED" "";Require ((@($escape.blockers)-contains"BACKUP_ID_INVALID")-or(@($escape.blockers)-contains"WORKSPACE_PATH_ESCAPE")) "ESCAPE_REASON_MISSING" "";Require (-not[bool]$escape.writes_destination) "ESCAPE_WROTE_DESTINATION" ""

$oneClickRoot=Join-Path $resolved "one-click-vault";$oneDry=Run-OneClick $oneClickRoot $false
Require ([bool]$oneDry.ok) "ONE_CLICK_DRY_NOT_OK" ([string]$oneDry.execution_status);Require (([string]$oneDry.execution_status)-eq"dry_run_ready") "ONE_CLICK_DRY_NOT_READY" ([string]$oneDry.execution_status);Require (-not(Test-Path -LiteralPath $oneClickRoot)) "ONE_CLICK_DRY_WROTE" ""
$oneCreated=Run-OneClick $oneClickRoot $true
Require ([bool]$oneCreated.ok) "ONE_CLICK_EXECUTE_NOT_OK" ([string]$oneCreated.execution_status);Require (([string]$oneCreated.execution_status)-eq"created_verified") "ONE_CLICK_NOT_CREATED" ([string]$oneCreated.execution_status);Require (Test-Path -LiteralPath ([string]$oneCreated.payload_path) -PathType Container) "ONE_CLICK_PAYLOAD_MISSING" ([string]$oneCreated.payload_path)
$oneRepeat=Run-OneClick $oneClickRoot $true
Require ([bool]$oneRepeat.ok) "ONE_CLICK_REPEAT_NOT_OK" ([string]$oneRepeat.execution_status);Require (([string]$oneRepeat.execution_status)-eq"already_configured") "ONE_CLICK_NOT_IDEMPOTENT" ([string]$oneRepeat.execution_status)

Write-Output "PASS: destination dry run, atomic setup, and idempotent profile verification"
Write-Output "PASS: deterministic per-device workspace creation and idempotent manifest verification"
Write-Output "PASS: injected failure rolled back every owned folder"
Write-Output "PASS: unmanaged roots and path escape attempts fail closed without altering user files"
Write-Output "PASS: one backend call dry-runs, creates, verifies, and idempotently reopens a complete backup workspace"
Write-Output "SELFTEST_LD_BACKUP_DESTINATION_WORKSPACE_OK"
