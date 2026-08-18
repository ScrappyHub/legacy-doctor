param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
function Require([bool]$Condition,[string]$Code,[string]$Detail){ if(-not $Condition){ Die $Code $Detail } }
function EnsureDir([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Container)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null } }
function Write-Fixture([string]$Root,[string]$Relative,[string]$Payload){ $path=Join-Path $Root $Relative;EnsureDir (Split-Path -Parent $path);[IO.File]::WriteAllBytes($path,[Text.Encoding]::UTF8.GetBytes($Payload)) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$fixtureBase = Join-Path $RepoRoot "proofs\selftest\mounted_media_backup"
$allowedPrefix = [IO.Path]::GetFullPath((Join-Path $RepoRoot "proofs\selftest")).TrimEnd("\") + "\"
$resolvedFixture = [IO.Path]::GetFullPath($fixtureBase)
Require ($resolvedFixture.StartsWith($allowedPrefix,[StringComparison]::OrdinalIgnoreCase)) "FIXTURE_PATH_OUTSIDE_SELFTEST" $resolvedFixture
if(Test-Path -LiteralPath $resolvedFixture){ Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }

$source = Join-Path $resolvedFixture "source"
$destination = Join-Path $resolvedFixture "destination"
$boundedDestination = Join-Path $resolvedFixture "bounded_destination"
EnsureDir $source
EnsureDir $destination
EnsureDir $boundedDestination
Write-Fixture $source "iPod_Control\Music\F00\SONG.m4a" "owned-fixture-song"
Write-Fixture $source "VIDEO_TS\VIDEO_TS.IFO" "owned-fixture-dvd"
Write-Fixture $source "ROMS\game.nes" "owned-fixture-rom"
Write-Fixture $source "archive\device.cos" "owned-fixture-cos"

$library = Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1"
$backupScript = Join-Path $RepoRoot "scripts\media\ld_mounted_media_backup_v1.ps1"
if(-not (Test-Path -LiteralPath $library -PathType Leaf)){ Die "RECEIPT_LIBRARY_MISSING" $library }
if(-not (Test-Path -LiteralPath $backupScript -PathType Leaf)){ Die "BACKUP_SCRIPT_MISSING" $backupScript }
. $library

$sourceHashes = @{}
foreach($file in @(Get-ChildItem -LiteralPath $source -File -Recurse)){
  $sourceHashes[$file.FullName] = LDREC-HexSha256File $file.FullName
}

function Run-Backup([string]$Destination,[int]$MaxFiles,[bool]$ExecuteNow){
  $childArgs = @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$backupScript,"-RepoRoot",$RepoRoot,"-SourceRoot",$source,"-DestinationRoot",$Destination,"-MaxFiles",[string]$MaxFiles,"-MaxBytes","1048576")
  if($ExecuteNow){ $childArgs += "-Execute" }
  $output = & powershell.exe @childArgs
  if($LASTEXITCODE -ne 0){ Die "BACKUP_SCRIPT_EXIT_NONZERO" ([string]$LASTEXITCODE) }
  return (LDREC-ReadReceiptFromOutput -Output $output -ExpectedSchema "ld.media.mounted_backup.receipt.v1" -SchemaDirectory (Join-Path $RepoRoot "schemas"))
}

$dryRun = Run-Backup -Destination $destination -MaxFiles 20 -ExecuteNow $false
Require ([bool]$dryRun.ok) "DRY_RUN_NOT_OK" ([string]$dryRun.execution_status)
Require (([string]$dryRun.execution_status) -eq "dry_run_ready") "DRY_RUN_NOT_READY" ([string]$dryRun.execution_status)
Require (-not [bool]$dryRun.performs_copy) "DRY_RUN_COPIED" ""
Require (@(Get-ChildItem -LiteralPath $destination -File -Recurse).Count -eq 0) "DRY_RUN_WROTE_DESTINATION" ""

$executed = Run-Backup -Destination $destination -MaxFiles 20 -ExecuteNow $true
Require ([bool]$executed.ok) "EXECUTION_NOT_OK" ([string]$executed.execution_status)
Require (([string]$executed.execution_status) -eq "executed_verified") "EXECUTION_NOT_VERIFIED" ([string]$executed.execution_status)
Require ([int]$executed.copied_file_count -eq 4) "COPIED_COUNT_BAD" ([string]$executed.copied_file_count)
Require ([int]$executed.verified_file_count -eq 4) "VERIFIED_COUNT_BAD" ([string]$executed.verified_file_count)
Require ([bool]$executed.write_probe_ok) "WRITE_PROBE_NOT_OK" ""

foreach($row in @($executed.rows)){
  Require (([string]$row.status) -eq "COPIED_VERIFIED") "ROW_NOT_VERIFIED" ([string]$row.relative_path)
  $destinationHash = LDREC-HexSha256File ([string]$row.destination_path)
  Require ($destinationHash -ceq [string]$row.expected_sha256) "DESTINATION_HASH_BAD" ([string]$row.relative_path)
  Require ($destinationHash -ceq [string]$row.destination_sha256) "RECEIPT_HASH_BAD" ([string]$row.relative_path)
}

foreach($sourcePath in $sourceHashes.Keys){
  $afterHash = LDREC-HexSha256File $sourcePath
  Require ($afterHash -ceq [string]$sourceHashes[$sourcePath]) "SOURCE_MODIFIED" $sourcePath
}
Require (@(Get-ChildItem -LiteralPath $destination -File -Recurse -Filter "*.legacy-doctor.partial").Count -eq 0) "PARTIAL_FILE_LEFT_BEHIND" ""

$duplicates = Run-Backup -Destination $destination -MaxFiles 20 -ExecuteNow $true
Require ([bool]$duplicates.ok) "DUPLICATE_RUN_NOT_OK" ([string]$duplicates.execution_status)
Require ([int]$duplicates.duplicate_file_count -eq 4) "DUPLICATE_COUNT_BAD" ([string]$duplicates.duplicate_file_count)
Require ([int]$duplicates.skipped_file_count -eq 4) "SKIPPED_COUNT_BAD" ([string]$duplicates.skipped_file_count)
Require ([int]$duplicates.copied_file_count -eq 0) "DUPLICATE_RUN_COPIED_FILES" ([string]$duplicates.copied_file_count)
Require (-not [bool]$duplicates.writes_destination) "DUPLICATE_RUN_WROTE_DESTINATION" ""
foreach($row in @($duplicates.rows)){ Require (([string]$row.status) -eq "SKIP_DUPLICATE_VERIFIED") "DUPLICATE_ROW_STATUS_BAD" ([string]$row.relative_path) }

$changedDestination = [string]$executed.rows[0].destination_path
[IO.File]::WriteAllBytes($changedDestination,[Text.Encoding]::UTF8.GetBytes("different-existing-bytes"))
$collision = Run-Backup -Destination $destination -MaxFiles 20 -ExecuteNow $true
Require (-not [bool]$collision.ok) "MISMATCHED_COLLISION_NOT_BLOCKED" ""
Require (@($collision.blockers) -contains "DESTINATION_COLLISION") "MISMATCHED_COLLISION_REASON_MISSING" ""
Require ([int]$collision.copied_file_count -eq 0) "MISMATCHED_COLLISION_COPIED_FILES" ([string]$collision.copied_file_count)

$overlap = Join-Path $source "destination_inside_source"
EnsureDir $overlap
$overlapReceipt = Run-Backup -Destination $overlap -MaxFiles 20 -ExecuteNow $true
Require (-not [bool]$overlapReceipt.ok) "OVERLAP_NOT_BLOCKED" ""
Require (@($overlapReceipt.blockers) -contains "SOURCE_DESTINATION_OVERLAP") "OVERLAP_REASON_MISSING" ""

$bounded = Run-Backup -Destination $boundedDestination -MaxFiles 2 -ExecuteNow $true
Require (-not [bool]$bounded.ok) "TRUNCATED_EXECUTION_NOT_BLOCKED" ""
Require (@($bounded.blockers) -contains "CATALOG_TRUNCATED") "TRUNCATION_REASON_MISSING" ""
Require (@(Get-ChildItem -LiteralPath $boundedDestination -File -Recurse).Count -eq 0) "TRUNCATED_EXECUTION_COPIED" ""

Write-Output "PASS: dry run planned without destination writes"
Write-Output "PASS: execute copied and independently verified four files"
Write-Output "PASS: source bytes remained unchanged and no partials remained"
Write-Output "PASS: matching hashes skip as duplicates while mismatched collisions fail closed"
Write-Output "PASS: path overlap and truncated catalogs fail closed"
Write-Output "SELFTEST_LD_MOUNTED_MEDIA_BACKUP_OK"
