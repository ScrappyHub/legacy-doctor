param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
function Require([bool]$Condition,[string]$Code,[string]$Detail){ if(-not $Condition){ Die $Code $Detail } }
function EnsureDir([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Container)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")

$base = Join-Path $RepoRoot "proofs\selftest\storage03_interruption_recovery"
$allowed = [IO.Path]::GetFullPath((Join-Path $RepoRoot "proofs\selftest")).TrimEnd("\") + "\"
$full = [IO.Path]::GetFullPath($base)
Require ($full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) "FIXTURE_ESCAPE" $full
if(Test-Path -LiteralPath $full){ Remove-Item -LiteralPath $full -Recurse -Force }

$source = Join-Path $full "source"
EnsureDir $source
function Put([string]$Relative,[string]$Text){
  $path = Join-Path $source $Relative
  EnsureDir (Split-Path -Parent $path)
  [IO.File]::WriteAllBytes($path,[Text.Encoding]::UTF8.GetBytes($Text))
}
Put "music\one.m4a" "one-song-bytes"
Put "roms\game.nes" "game-rom-bytes"
Put "archive\device.cos" "device-cos-bytes"
$sourceHashes = @{}
foreach($file in @(Get-ChildItem -LiteralPath $source -File -Recurse)){ $sourceHashes[$file.FullName] = LDREC-HexSha256File $file.FullName }

$suffix = ".legacy-doctor.partial"
$recovery = Join-Path $RepoRoot "scripts\storage\ld_storage03_interruption_recovery_v1.ps1"
$backup = Join-Path $RepoRoot "scripts\media\ld_mounted_media_backup_v1.ps1"

function New-Destination([string]$Name){
  $path = Join-Path $full $Name
  EnsureDir $path
  return $path
}
function Put-Partial([string]$Destination,[string]$Relative,[string]$Text){
  $path = Join-Path $Destination ($Relative + $suffix)
  EnsureDir (Split-Path -Parent $path)
  [IO.File]::WriteAllBytes($path,[Text.Encoding]::UTF8.GetBytes($Text))
  return $path
}
function Run-Recovery([string]$Destination,[bool]$Recover,[bool]$ExecuteNow,[string]$SourceRoot = $source){
  $extra = @("-SourceRoot",$SourceRoot,"-DestinationRoot",$Destination)
  if($Recover){ $extra += "-RecoverStalePartials" }
  if($ExecuteNow){ $extra += "-Execute" }
  return (LDREC-RunReceiptScript -ScriptPath $recovery -RepoRoot $RepoRoot -ExpectedSchema "ld.device.storage03_interruption_recovery.receipt.v1" -ExtraArgs $extra)
}
function Assert-Unchanged([string]$PartialPath,[string]$Expected,[string]$Name){
  Require (Test-Path -LiteralPath $PartialPath -PathType Leaf) ($Name + "_PARTIAL_MOVED") $PartialPath
  Require ((LDREC-HexSha256File $PartialPath) -ceq (LDREC-HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($Expected)))) ($Name + "_PARTIAL_CHANGED") $PartialPath
}

# Positive: an exact prefix of the source is recoverable. Dry run and missing -Execute change nothing.
$dest = New-Destination "recoverable"
$prefixText = "one-song"
$partialPath = Put-Partial $dest "music\one.m4a" $prefixText

$plan = Run-Recovery $dest $true $false
Require ([bool]$plan.ok) "PLAN_NOT_OK" (@($plan.blockers) -join ",")
Require (([string]$plan.status) -eq "plan_ready") "PLAN_STATUS_BAD" ([string]$plan.status)
Require ([int]$plan.recoverable_count -eq 1) "PLAN_RECOVERABLE_COUNT_BAD" ([string]$plan.recoverable_count)
Require ([int]$plan.quarantined_count -eq 0) "PLAN_QUARANTINED" ""
Assert-Unchanged $partialPath $prefixText "PLAN"
Require (-not (Test-Path -LiteralPath (Join-Path $dest "quarantine"))) "PLAN_CREATED_QUARANTINE" ""

$noFlag = Run-Recovery $dest $false $true
Require (-not [bool]$noFlag.ok) "EXECUTE_WITHOUT_FLAG_NOT_BLOCKED" ""
Require (@($noFlag.blockers) -contains "EXECUTE_REQUIRES_RECOVER_FLAG") "EXECUTE_WITHOUT_FLAG_REASON" ""
Assert-Unchanged $partialPath $prefixText "NO_FLAG"

# Positive: recovery quarantines the partial (never deletes it), then the normal executor completes the copy.
$recovered = Run-Recovery $dest $true $true
Require ([bool]$recovered.ok) "RECOVERY_NOT_OK" (@($recovered.blockers) -join ",")
Require (([string]$recovered.status) -eq "quarantined") "RECOVERY_STATUS_BAD" ([string]$recovered.status)
Require ([int]$recovered.quarantined_count -eq 1) "RECOVERY_COUNT_BAD" ([string]$recovered.quarantined_count)
Require (-not (Test-Path -LiteralPath $partialPath)) "RECOVERY_LEFT_PARTIAL_AT_ORIGIN" $partialPath
$row = $recovered.rows[0]
Require ([bool]$row.quarantined) "ROW_NOT_QUARANTINED" ""
Require (Test-Path -LiteralPath ([string]$row.quarantine_path) -PathType Leaf) "QUARANTINED_FILE_MISSING" ([string]$row.quarantine_path)
Require ((LDREC-HexSha256File ([string]$row.quarantine_path)) -ceq (LDREC-HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($prefixText)))) "QUARANTINED_BYTES_CHANGED" ""

$copy = LDREC-RunReceiptScript -ScriptPath $backup -RepoRoot $RepoRoot -ExpectedSchema "ld.media.mounted_backup.receipt.v1" -ExtraArgs @("-SourceRoot",$source,"-DestinationRoot",$dest,"-MaxFiles","10","-MaxBytes","1048576","-Execute")
Require ([bool]$copy.ok) "POST_RECOVERY_COPY_NOT_OK" (@($copy.blockers) -join ",")
Require ([int]$copy.verified_file_count -eq 3) "POST_RECOVERY_VERIFIED_BAD" ([string]$copy.verified_file_count)
foreach($file in @(Get-ChildItem -LiteralPath $source -File -Recurse)){
  $relative = $file.FullName.Substring($source.Length + 1)
  Require ((LDREC-HexSha256File (Join-Path $dest $relative)) -ceq $sourceHashes[$file.FullName]) "POST_RECOVERY_BYTES_DIFFER" $relative
}

$replay = Run-Recovery $dest $true $true
Require ([bool]$replay.ok) "REPLAY_NOT_OK" (@($replay.blockers) -join ",")
Require (([string]$replay.status) -eq "no_partials") "REPLAY_NOT_NOOP" ([string]$replay.status)
Require ([int]$replay.partial_count -eq 0) "REPLAY_FOUND_PARTIALS" ""

# Negative: each of these must block and leave every partial exactly where and as it was.
function Assert-Blocked([string]$Name,[string]$Reason,[object]$Receipt){
  Require (-not [bool]$Receipt.ok) ($Name + "_NOT_BLOCKED") ""
  Require (([string]$Receipt.status) -eq "blocked") ($Name + "_STATUS_BAD") ([string]$Receipt.status)
  Require ([int]$Receipt.quarantined_count -eq 0) ($Name + "_QUARANTINED") ""
  $reasons = @(@($Receipt.rows | ForEach-Object { [string]$_.reason }) + @($Receipt.blockers))
  Require ($reasons -contains $Reason) ($Name + "_REASON_MISSING") ($reasons -join ",")
}

$dest = New-Destination "not-prefix"
$p = Put-Partial $dest "music\one.m4a" "zzz-song"
Assert-Blocked "NOT_PREFIX" "PARTIAL_NOT_SOURCE_PREFIX" (Run-Recovery $dest $true $true)
Assert-Unchanged $p "zzz-song" "NOT_PREFIX"

$dest = New-Destination "larger-than-source"
$p = Put-Partial $dest "music\one.m4a" "one-song-bytes-and-much-more"
Assert-Blocked "LARGER" "PARTIAL_LARGER_THAN_SOURCE" (Run-Recovery $dest $true $true)
Assert-Unchanged $p "one-song-bytes-and-much-more" "LARGER"

$dest = New-Destination "final-present"
$p = Put-Partial $dest "music\one.m4a" "one-song"
[IO.File]::WriteAllBytes((Join-Path $dest "music\one.m4a"),[Text.Encoding]::UTF8.GetBytes("already-here"))
Assert-Blocked "FINAL_PRESENT" "FINAL_FILE_PRESENT" (Run-Recovery $dest $true $true)
Assert-Unchanged $p "one-song" "FINAL_PRESENT"

$dest = New-Destination "source-missing"
$p = Put-Partial $dest "music\not-in-source.m4a" "abc"
Assert-Blocked "SOURCE_MISSING" "SOURCE_FILE_MISSING" (Run-Recovery $dest $true $true)
Assert-Unchanged $p "abc" "SOURCE_MISSING"

# One foreign partial blocks everything, including a recoverable one next to it.
$dest = New-Destination "mixed"
$good = Put-Partial $dest "music\one.m4a" "one-song"
$bad = Put-Partial $dest "roms\game.nes" "not-the-rom"
Assert-Blocked "MIXED" "PARTIAL_NOT_SOURCE_PREFIX" (Run-Recovery $dest $true $true)
Assert-Unchanged $good "one-song" "MIXED_GOOD"
Assert-Unchanged $bad "not-the-rom" "MIXED_BAD"

# Destination overlapping the source or the repository is refused before any enumeration.
$overlap = Run-Recovery $source $true $true
Require (-not [bool]$overlap.ok) "OVERLAP_NOT_BLOCKED" ""
Require (@($overlap.blockers) -contains "SOURCE_DESTINATION_OVERLAP") "OVERLAP_REASON_MISSING" ""
$repoDest = Run-Recovery $RepoRoot $true $true
Require (-not [bool]$repoDest.ok) "REPO_DESTINATION_NOT_BLOCKED" ""
Require (@($repoDest.blockers) -contains "REPO_ROOT_DESTINATION_FORBIDDEN") "REPO_DESTINATION_REASON_MISSING" ""
$missing = Run-Recovery (Join-Path $full "does-not-exist") $true $true
Require (-not [bool]$missing.ok) "MISSING_DESTINATION_NOT_BLOCKED" ""
Require (@($missing.blockers) -contains "DESTINATION_ROOT_MISSING") "MISSING_DESTINATION_REASON_MISSING" ""

$sourceUnchanged = $true
foreach($path in @($sourceHashes.Keys)){ if((LDREC-HexSha256File $path) -cne [string]$sourceHashes[$path]){ $sourceUnchanged = $false } }
Require $sourceUnchanged "SOURCE_CHANGED" ""

Write-Output "PASS: exact-prefix partial is recoverable; dry run and missing flag change nothing"
Write-Output "PASS: recovery quarantines with matching hash, normal executor completes byte-identical copy, replay is a no-op"
Write-Output "PASS: non-prefix, oversized, final-present, source-missing, mixed, overlap, repo-root, and missing-destination cases block without changes"
Write-Output "SELFTEST_LD_STORAGE03_INTERRUPTION_RECOVERY_OK"
