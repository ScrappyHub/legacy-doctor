param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
function Require([bool]$Condition,[string]$Code,[string]$Detail){ if(-not $Condition){ Die $Code $Detail } }
function EnsureDir([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Container)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null } }
function Write-Lf([string]$Path,[string]$Text){
  EnsureDir (Split-Path -Parent $Path)
  $normalized = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $normalized.EndsWith("`n")){ $normalized += "`n" }
  [IO.File]::WriteAllText($Path,$normalized,[Text.UTF8Encoding]::new($false))
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")

$fixtureBase = Join-Path $RepoRoot "proofs\selftest\storage03_bounded_copy_executor"
$allowedPrefix = [IO.Path]::GetFullPath((Join-Path $RepoRoot "proofs\selftest")).TrimEnd("\") + "\"
$resolvedFixture = [IO.Path]::GetFullPath($fixtureBase)
Require ($resolvedFixture.StartsWith($allowedPrefix,[StringComparison]::OrdinalIgnoreCase)) "FIXTURE_PATH_OUTSIDE_SELFTEST" $resolvedFixture
if(Test-Path -LiteralPath $resolvedFixture){ Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }

$source = Join-Path $resolvedFixture "source"
$destination = Join-Path $resolvedFixture "destination"
$boundedDestination = Join-Path $resolvedFixture "bounded"
$stalePartialDestination = Join-Path $resolvedFixture "stale-partial"
EnsureDir $source
EnsureDir $destination
EnsureDir $boundedDestination
EnsureDir $stalePartialDestination

function Write-Fixture([string]$Relative,[string]$Payload){
  $path = Join-Path $source $Relative
  EnsureDir (Split-Path -Parent $path)
  [IO.File]::WriteAllBytes($path,[Text.Encoding]::UTF8.GetBytes($Payload))
}

Write-Fixture "iPod_Control\Music\F00\SONG.m4a" "fixture-song-bytes"
Write-Fixture "VIDEO_TS\VIDEO_TS.IFO" "fixture-dvd-bytes"
Write-Fixture "ROMS\game.nes" "fixture-rom-bytes"
Write-Fixture "archive\device.cos" "fixture-cos-bytes"

$backupScript = Join-Path $RepoRoot "scripts\media\ld_mounted_media_backup_v1.ps1"
Require (Test-Path -LiteralPath $backupScript -PathType Leaf) "BACKUP_SCRIPT_MISSING" $backupScript
$sourceHashes = @{}
foreach($file in @(Get-ChildItem -LiteralPath $source -File -Recurse -Force)){
  $sourceHashes[$file.FullName] = LDREC-HexSha256File $file.FullName
}

function Run-Backup([string]$Destination,[int]$MaxFiles,[bool]$ExecuteNow){
  $args = @(
    "-SourceRoot",$source,
    "-DestinationRoot",$Destination,
    "-MaxFiles",[string]$MaxFiles,
    "-MaxBytes","1048576"
  )
  if($ExecuteNow){ $args += "-Execute" }
  return (LDREC-RunReceiptScript -ScriptPath $backupScript -RepoRoot $RepoRoot -ExpectedSchema "ld.media.mounted_backup.receipt.v1" -ExtraArgs $args)
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
  Require ((LDREC-HexSha256File ([string]$row.destination_path)) -ceq [string]$row.expected_sha256) "DESTINATION_HASH_BAD" ([string]$row.relative_path)
  Require ((LDREC-HexSha256File ([string]$row.destination_path)) -ceq [string]$row.destination_sha256) "RECEIPT_HASH_BAD" ([string]$row.relative_path)
}

$duplicates = Run-Backup -Destination $destination -MaxFiles 20 -ExecuteNow $true
Require ([bool]$duplicates.ok) "DUPLICATE_RUN_NOT_OK" ([string]$duplicates.execution_status)
Require ([int]$duplicates.duplicate_file_count -eq 4) "DUPLICATE_COUNT_BAD" ([string]$duplicates.duplicate_file_count)
Require ([int]$duplicates.copied_file_count -eq 0) "DUPLICATE_RUN_COPIED_FILES" ([string]$duplicates.copied_file_count)
Require (-not [bool]$duplicates.writes_destination) "DUPLICATE_RUN_WROTE_DESTINATION" ""

$collisionPath = [string]$executed.rows[0].destination_path
[IO.File]::WriteAllBytes($collisionPath,[Text.Encoding]::UTF8.GetBytes("collision-bytes"))
$collision = Run-Backup -Destination $destination -MaxFiles 20 -ExecuteNow $true
Require (-not [bool]$collision.ok) "COLLISION_NOT_BLOCKED" ""
Require (@($collision.blockers) -contains "DESTINATION_COLLISION") "COLLISION_REASON_MISSING" ""
Require ([int]$collision.copied_file_count -eq 0) "COLLISION_COPIED_FILES" ([string]$collision.copied_file_count)

$bounded = Run-Backup -Destination $boundedDestination -MaxFiles 2 -ExecuteNow $true
Require (-not [bool]$bounded.ok) "TRUNCATION_NOT_BLOCKED" ""
Require (@($bounded.blockers) -contains "CATALOG_TRUNCATED") "TRUNCATION_REASON_MISSING" ""
Require (@(Get-ChildItem -LiteralPath $boundedDestination -File -Recurse).Count -eq 0) "TRUNCATION_COPIED" ""

$staleRelative = "iPod_Control\Music\F00\SONG.m4a"
$stalePath = Join-Path $stalePartialDestination ($staleRelative + ".legacy-doctor.partial")
EnsureDir (Split-Path -Parent $stalePath)
[IO.File]::WriteAllBytes($stalePath,[Text.Encoding]::UTF8.GetBytes("stale-partial"))
$stale = Run-Backup -Destination $stalePartialDestination -MaxFiles 20 -ExecuteNow $true
Require (-not [bool]$stale.ok) "STALE_PARTIAL_NOT_BLOCKED" ""
Require (@($stale.blockers) -contains "STALE_PARTIAL_COLLISION") "STALE_PARTIAL_REASON_MISSING" ""
Require ((LDREC-HexSha256File $stalePath) -ceq (LDREC-HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes("stale-partial")))) "STALE_PARTIAL_OVERWRITTEN" ""

$sourceUnchanged = $true
foreach($path in @($sourceHashes.Keys)){
  if((LDREC-HexSha256File $path) -cne [string]$sourceHashes[$path]){ $sourceUnchanged = $false }
}
Require $sourceUnchanged "SOURCE_CHANGED" ""

$tests = @(
  [ordered]@{ name="dry_run_no_destination_write"; passed=$true },
  [ordered]@{ name="positive_copy_and_rehash"; passed=$true },
  [ordered]@{ name="duplicate_detection_without_write"; passed=$true },
  [ordered]@{ name="destination_collision_fail_closed"; passed=$true },
  [ordered]@{ name="bounded_truncation_fail_closed"; passed=$true },
  [ordered]@{ name="stale_partial_fail_closed"; passed=$true },
  [ordered]@{ name="source_unchanged"; passed=$sourceUnchanged }
)

$receipt = [ordered]@{
  schema = "ld.device.storage03_bounded_copy_executor.receipt.v1"
  event_type = "ld.device.storage03_bounded_copy_executor.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "storage03_bounded_copy_executor_fixture"
  destructive = $false
  writes_source = $false
  performs_copy = $true
  writes_destination = $true
  hashes_file_contents = $true
  executor_schema = "ld.media.mounted_backup.receipt.v1"
  positive_planned_file_count = [int]$executed.planned_file_count
  positive_copied_file_count = [int]$executed.copied_file_count
  positive_verified_file_count = [int]$executed.verified_file_count
  duplicate_file_count = [int]$duplicates.duplicate_file_count
  collision_blocked = $true
  bounded_truncation_blocked = $true
  stale_partial_blocked = $true
  source_unchanged = [bool]$sourceUnchanged
  executor_created_partial_files_remaining = [int](@(Get-ChildItem -LiteralPath $destination -File -Recurse -Filter "*.legacy-doctor.partial").Count + @(Get-ChildItem -LiteralPath $boundedDestination -File -Recurse -Filter "*.legacy-doctor.partial").Count)
  preexisting_partial_files_preserved = [int](@(Get-ChildItem -LiteralPath $stalePartialDestination -File -Recurse -Filter "*.legacy-doctor.partial").Count)
  tests = @($tests)
  blockers = @()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_storage03_bounded_copy_executor"
EnsureDir $outDir
$outPath = Join-Path $outDir ("storage03_bounded_copy_executor_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")
$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Lf $outPath $json
Write-Output ("DEVICE_STORAGE03_BOUNDED_COPY_EXECUTOR_PATH: " + $outPath)
Write-Output $json
Write-Output "LD_DEVICE_STORAGE03_BOUNDED_COPY_EXECUTOR_OK"
