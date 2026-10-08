param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
function Require([bool]$Condition,[string]$Code,[string]$Detail){ if(-not $Condition){ Die $Code $Detail } }
function EnsureDir([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Container)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")

$base = Join-Path $RepoRoot "proofs\selftest\capacity_test"
$allowed = [IO.Path]::GetFullPath((Join-Path $RepoRoot "proofs\selftest")).TrimEnd("\") + "\"
$full = [IO.Path]::GetFullPath($base)
Require ($full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) "FIXTURE_ESCAPE" $full
if(Test-Path -LiteralPath $full){ Remove-Item -LiteralPath $full -Recurse -Force }
EnsureDir $full

$lane = Join-Path $RepoRoot "scripts\storage\ld_capacity_test_v1.ps1"
$schemaName = "ld.device.capacity_test.receipt.v1"
$MB = 1048576

function Run-Lane([string[]]$ScriptArgs){
  return (LDREC-RunReceiptScript -ScriptPath $lane -RepoRoot $RepoRoot -ExpectedSchema $schemaName -ExtraArgs $ScriptArgs)
}
function Fresh([string]$Name){
  $p = Join-Path $full $Name
  EnsureDir $p
  return $p
}
function Tree([string]$Path){
  return (@(Get-ChildItem -LiteralPath $Path -Recurse -Force | ForEach-Object { $_.FullName }) | Sort-Object) -join "|"
}

# 1. Genuine simulated device: every block verifies and the full tested region is good.
$t1 = Fresh "sim_genuine"
$r = Run-Lane @("-TargetRoot",$t1,"-SimulatedAdvertisedBytes",[string](32*$MB),"-SimulatedRealBytes",[string](32*$MB),"-ReserveBytes","0","-FileBytes",[string](8*$MB),"-Execute")
Require ($r.status -eq "executed_pass") "GENUINE_SIM_STATUS" ([string]$r.status + " " + ($r.blockers -join ","))
Require ($r.verdict -eq "PASS_TESTED_REGION_VERIFIED") "GENUINE_SIM_VERDICT" ([string]$r.verdict)
Require ([int64]$r.bad_block_count -eq 0) "GENUINE_SIM_BAD_BLOCKS" ([string]$r.bad_block_count)
Require ([int64]$r.verified_good_bytes -eq 32*$MB) "GENUINE_SIM_GOOD_BYTES" ([string]$r.verified_good_bytes)
Require ([int64]$r.first_bad_offset -eq -1) "GENUINE_SIM_FIRST_BAD" ""
Require ([bool]$r.cleanup_ok) "GENUINE_SIM_CLEANUP" ""
Require (@(Get-ChildItem -LiteralPath $t1 -Force).Count -eq 0) "GENUINE_SIM_LEFT_FILES" (Tree $t1)
Write-Output "PASS: genuine simulated device verifies in full and cleans up"

# 2. Fake simulated device (advertises 64 MB, stores 16 MB, wraps): the test must detect it
#    and the verified good bytes must equal the real size.
$t2 = Fresh "sim_fake"
$r = Run-Lane @("-TargetRoot",$t2,"-SimulatedAdvertisedBytes",[string](64*$MB),"-SimulatedRealBytes",[string](16*$MB),"-ReserveBytes","0","-FileBytes",[string](8*$MB),"-Execute")
Require ($r.status -eq "executed_fail") "FAKE_SIM_STATUS" ([string]$r.status)
Require ($r.verdict -eq "FAIL_DATA_MISMATCH") "FAKE_SIM_VERDICT" ([string]$r.verdict)
Require (-not [bool]$r.ok) "FAKE_SIM_OK" ""
Require ([int64]$r.bad_block_count -eq 48) "FAKE_SIM_BAD_BLOCKS" ([string]$r.bad_block_count)
Require ([int64]$r.verified_good_bytes -eq 16*$MB) "FAKE_SIM_GOOD_BYTES" ([string]$r.verified_good_bytes)
Require ([int64]$r.first_bad_offset -ge 0) "FAKE_SIM_FIRST_BAD" ([string]$r.first_bad_offset)
Require (@($r.bad_regions).Count -gt 0) "FAKE_SIM_NO_REGIONS" ""
Require ([double]$r.tested_fraction_of_claimed -lt 0.5) "FAKE_SIM_FRACTION" ([string]$r.tested_fraction_of_claimed)
Require (@(Get-ChildItem -LiteralPath $t2 -Force).Count -eq 0) "FAKE_SIM_LEFT_FILES" (Tree $t2)
Write-Output "PASS: wrap-around fake capacity is detected and real size is measured"

# 3. Real filesystem under the selftest folder: existing files are untouched and the run cleans up.
$t3 = Fresh "real_fs"
$sentinel = Join-Path $t3 "existing_user_file.txt"
[IO.File]::WriteAllText($sentinel,"do not touch this file")
$beforeHash = LDREC-HexSha256File $sentinel
$r = Run-Lane @("-TargetRoot",$t3,"-TestBytes",[string](24*$MB),"-FileBytes",[string](8*$MB),"-Execute")
Require ($r.status -eq "executed_pass") "REAL_STATUS" ([string]$r.status + " " + ($r.blockers -join ",") + " " + [string]$r.write_error)
Require ($r.verdict -eq "PASS_TESTED_REGION_VERIFIED") "REAL_VERDICT" ([string]$r.verdict)
Require ([int64]$r.written_bytes -eq 24*$MB) "REAL_WRITTEN" ([string]$r.written_bytes)
Require ([int64]$r.verified_good_bytes -eq 24*$MB) "REAL_GOOD" ([string]$r.verified_good_bytes)
Require (-not [bool]$r.writes_existing_files) "REAL_WRITES_EXISTING" ""
Require ([bool]$r.cleanup_ok) "REAL_CLEANUP" ""
Require ((LDREC-HexSha256File $sentinel) -eq $beforeHash) "REAL_SENTINEL_CHANGED" ""
Require (@(Get-ChildItem -LiteralPath $t3 -Force).Count -eq 1) "REAL_LEFT_FILES" (Tree $t3)
Require (@($r.limitations) -contains "FREE_SPACE_ONLY") "REAL_LIMITATION_MISSING" ""
Write-Output ("PASS: real filesystem run verified 24 MB, left existing file intact, cache_bypassed=" + [string]$r.read_cache_bypassed)

# 4. Dry run plans but writes nothing.
$t4 = Fresh "dry_run"
$r = Run-Lane @("-TargetRoot",$t4,"-TestBytes",[string](16*$MB))
Require ($r.status -eq "dry_run_ready") "DRY_STATUS" ([string]$r.status + " " + ($r.blockers -join ","))
Require (-not [bool]$r.execution_allowed) "DRY_EXEC_ALLOWED" ""
Require ($r.verdict -eq "NOT_RUN") "DRY_VERDICT" ""
Require ([int64]$r.planned_bytes -eq 16*$MB) "DRY_PLANNED" ([string]$r.planned_bytes)
Require ([int64]$r.written_bytes -eq 0) "DRY_WRITTEN" ""
Require (@(Get-ChildItem -LiteralPath $t4 -Force).Count -eq 0) "DRY_WROTE" (Tree $t4)
Write-Output "PASS: dry run plans and writes nothing"

# 5. Refusals. Each must produce a blocked receipt and leave nothing behind.
function Assert-Blocked([string]$Name,[object]$Receipt,[string]$Blocker){
  Require ($Receipt.status -eq "blocked") ($Name + "_STATUS") ([string]$Receipt.status)
  Require (-not [bool]$Receipt.ok) ($Name + "_OK") ""
  Require (-not [bool]$Receipt.execution_allowed) ($Name + "_ALLOWED") ""
  Require (@($Receipt.blockers) -contains $Blocker) ($Name + "_BLOCKER") ((@($Receipt.blockers)) -join ",")
  Require ([int64]$Receipt.written_bytes -eq 0) ($Name + "_WROTE") ""
}
$missing = Join-Path $full "does_not_exist"
Assert-Blocked "MISSING" (Run-Lane @("-TargetRoot",$missing,"-Execute")) "TARGET_ROOT_MISSING"

$repoTarget = Join-Path $RepoRoot "scripts"
$beforeTree = Tree $repoTarget
Assert-Blocked "REPO" (Run-Lane @("-TargetRoot",$repoTarget,"-TestBytes",[string](8*$MB),"-Execute")) "REPO_ROOT_TARGET_FORBIDDEN"
Require ((Tree $repoTarget) -eq $beforeTree) "REPO_TARGET_CHANGED" ""

$t5 = Fresh "bad_chunk"
Assert-Blocked "CHUNK" (Run-Lane @("-TargetRoot",$t5,"-ChunkBytes","1000","-Execute")) "CHUNK_BYTES_INVALID"

# A fixed disk outside the selftest folder is refused without touching it.
$fixedTarget = [IO.Path]::GetTempPath().TrimEnd("\")
$beforeTemp = @(Get-ChildItem -LiteralPath $fixedTarget -Force -ErrorAction SilentlyContinue).Count
$rr = Run-Lane @("-TargetRoot",$fixedTarget,"-TestBytes",[string](8*$MB),"-Execute")
Require ($rr.status -eq "blocked") "FIXED_STATUS" ([string]$rr.status)
Require (@($rr.blockers) -contains "TARGET_VOLUME_FIXED_FORBIDDEN") "FIXED_BLOCKER" ((@($rr.blockers)) -join ",")
Require ([int64]$rr.written_bytes -eq 0) "FIXED_WROTE" ""
$afterTemp = @(Get-ChildItem -LiteralPath $fixedTarget -Force -ErrorAction SilentlyContinue).Count
Require ($afterTemp -eq $beforeTemp) "FIXED_TARGET_CHANGED" ""

# Simulation is refused outside the selftest folder.
$rs = Run-Lane @("-TargetRoot",$fixedTarget,"-SimulatedAdvertisedBytes",[string](8*$MB),"-SimulatedRealBytes",[string](4*$MB),"-Execute")
Require (@($rs.blockers) -contains "SIMULATION_ONLY_UNDER_SELFTEST") "SIM_OUTSIDE_BLOCKER" ((@($rs.blockers)) -join ",")
Require ([int64]$rs.written_bytes -eq 0) "SIM_OUTSIDE_WROTE" ""
Write-Output "PASS: missing target, repo root, bad chunk, fixed disk, and out-of-selftest simulation are all refused with nothing written"

Write-Output "SELFTEST_LD_CAPACITY_TEST_OK"
