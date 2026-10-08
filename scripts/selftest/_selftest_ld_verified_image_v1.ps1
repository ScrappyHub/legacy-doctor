param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$Code,[string]$Detail){throw($Code+":"+$Detail)}
function Require([bool]$Condition,[string]$Code,[string]$Detail){if(-not$Condition){Die $Code $Detail}}
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_verified_image_v1.ps1")
$fixtureRoot=Join-Path $RepoRoot "proofs\selftest\verified_image"
$allowed=[IO.Path]::GetFullPath((Join-Path $RepoRoot "proofs\selftest")).TrimEnd("\")+"\"
$resolved=[IO.Path]::GetFullPath($fixtureRoot)
Require ($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) "FIXTURE_PATH_OUTSIDE_SELFTEST" $resolved
if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
EnsureDir $resolved

$source=Join-Path $resolved "source.img"
$payload=New-Object byte[] 1048576
for($i=0;$i-lt$payload.Length;$i++){$payload[$i]=[byte](($i*31+17)%256)}
[IO.File]::WriteAllBytes($source,$payload)
$expected=LDREC-HexSha256File $source
$restoreScript=Join-Path $RepoRoot "scripts\storage\ld_image_restore_file_v1.ps1"

function Run-Restore([string]$Destination,[string]$Hash,[bool]$ExecuteNow){
  $args=@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$restoreScript,"-RepoRoot",$RepoRoot,"-SourceImage",$source,"-DestinationImage",$Destination,"-ExpectedSha256",$Hash,"-MaxBytes","1048576")
  if($ExecuteNow){$args+="-Execute"}
  $output=& powershell.exe @args
  if($LASTEXITCODE-ne 0){Die "RESTORE_SCRIPT_EXIT_NONZERO" ([string]$LASTEXITCODE)}
  return (LDREC-ReadReceiptFromOutput -Output $output -ExpectedSchema "ld.image.restore_file.receipt.v1" -SchemaDirectory (Join-Path $RepoRoot "schemas"))
}

$destination=Join-Path $resolved "restored.img"
$dry=Run-Restore $destination $expected $false
Require ([bool]$dry.ok) "DRY_RUN_NOT_OK" ([string]$dry.execution_status)
Require (([string]$dry.execution_status)-eq"dry_run_ready") "DRY_RUN_NOT_READY" ([string]$dry.execution_status)
Require (-not(Test-Path -LiteralPath $destination)) "DRY_RUN_WROTE_DESTINATION" ""

$executed=Run-Restore $destination $expected $true
Require ([bool]$executed.ok) "RESTORE_NOT_OK" ([string]$executed.execution_status)
Require (([string]$executed.execution_status)-eq"executed_verified") "RESTORE_NOT_VERIFIED" ([string]$executed.execution_status)
Require ([UInt64]$executed.bytes_copied-eq[UInt64]$payload.Length) "RESTORE_SIZE_BAD" ([string]$executed.bytes_copied)
Require ((LDREC-HexSha256File $destination)-ceq$expected) "RESTORE_HASH_BAD" ""
Require (-not(Test-Path -LiteralPath ($destination+".legacy-doctor.partial"))) "PARTIAL_LEFT_BEHIND" ""

$collision=Run-Restore $destination $expected $true
Require (-not[bool]$collision.ok) "COLLISION_NOT_BLOCKED" ""
Require (@($collision.blockers)-contains"DESTINATION_COLLISION") "COLLISION_REASON_MISSING" ""

$wrongDestination=Join-Path $resolved "wrong.img"
$wrong=Run-Restore $wrongDestination ("0"*64) $true
Require (-not[bool]$wrong.ok) "WRONG_HASH_NOT_BLOCKED" ""
Require (@($wrong.blockers)-contains"SOURCE_HASH_MISMATCH") "WRONG_HASH_REASON_MISSING" ""
Require (-not(Test-Path -LiteralPath $wrongDestination)) "WRONG_HASH_WROTE_DESTINATION" ""

$shortSource=New-Object IO.MemoryStream(,[byte[]](1,2,3,4))
$shortTemp=Join-Path $resolved "short.partial"
$shortFailed=$false
try{[void](LDIMG-CopyStreamVerified -SourceStream $shortSource -TemporaryPath $shortTemp -ExpectedBytes 8 -BufferBytes 4096)}catch{$shortFailed=$_.Exception.Message.Contains("SOURCE_SHORT_READ")}finally{$shortSource.Dispose();if(Test-Path -LiteralPath $shortTemp){Remove-Item -LiteralPath $shortTemp -Force}}
Require $shortFailed "SHORT_READ_NOT_REJECTED" ""

$safeFacts=[ordered]@{disk_number=4;is_boot=$false;is_system=$false;size_bytes=[UInt64]1024;serial_number="DEVICE-4"}
$safeBlockers=@(LDIMG-EvaluatePhysicalSource -Facts $safeFacts -ExpectedDiskNumber 4 -ExpectedBytes 1024 -ExpectedSerialNumber "DEVICE-4" -MaxBytes 1024 -DestinationDiskNumber 0)
Require ($safeBlockers.Count-eq 0) "SAFE_FACTS_BLOCKED" ($safeBlockers-join",")
$systemFacts=[ordered]@{disk_number=3;is_boot=$true;is_system=$true;size_bytes=[UInt64]1024;serial_number="SYSTEM"}
$systemBlockers=@(LDIMG-EvaluatePhysicalSource -Facts $systemFacts -ExpectedDiskNumber 3 -ExpectedBytes 1024 -ExpectedSerialNumber "SYSTEM" -MaxBytes 1024 -DestinationDiskNumber 3)
Require ($systemBlockers-contains"BOOT_DISK_FORBIDDEN") "BOOT_GATE_MISSING" ""
Require ($systemBlockers-contains"SYSTEM_DISK_FORBIDDEN") "SYSTEM_GATE_MISSING" ""
Require ($systemBlockers-contains"SOURCE_DESTINATION_DISK_SAME") "SAME_DISK_GATE_MISSING" ""

Write-Output "PASS: restore dry run made no writes"
Write-Output "PASS: image-to-file restore copied and independently verified every byte"
Write-Output "PASS: collisions, wrong hashes, and short reads fail closed"
Write-Output "PASS: physical-source safety blocks boot, system, and same-disk targets"
Write-Output "SELFTEST_LD_VERIFIED_IMAGE_OK"

