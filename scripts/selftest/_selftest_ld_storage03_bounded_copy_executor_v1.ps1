param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")
$scriptPath = Join-Path $RepoRoot "scripts\storage\ld_storage03_bounded_copy_executor_v1.ps1"
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "EXECUTOR_FIXTURE_EXIT_NONZERO" ([string]$LASTEXITCODE) }
$receipt = LDREC-ReadReceiptFromOutput -Output $out -ExpectedSchema "ld.device.storage03_bounded_copy_executor.receipt.v1" -SchemaDirectory (Join-Path $RepoRoot "schemas")
if(-not [bool]$receipt.ok){ Die "EXECUTOR_FIXTURE_NOT_OK" "" }
if([int]$receipt.positive_copied_file_count -ne 4){ Die "POSITIVE_COPY_COUNT_BAD" ([string]$receipt.positive_copied_file_count) }
if([int]$receipt.positive_verified_file_count -ne 4){ Die "POSITIVE_VERIFY_COUNT_BAD" ([string]$receipt.positive_verified_file_count) }
if([int]$receipt.duplicate_file_count -ne 4){ Die "DUPLICATE_COUNT_BAD" ([string]$receipt.duplicate_file_count) }
if(-not [bool]$receipt.collision_blocked){ Die "COLLISION_NOT_BLOCKED" "" }
if(-not [bool]$receipt.bounded_truncation_blocked){ Die "TRUNCATION_NOT_BLOCKED" "" }
if(-not [bool]$receipt.stale_partial_blocked){ Die "STALE_PARTIAL_NOT_BLOCKED" "" }
if(-not [bool]$receipt.source_unchanged){ Die "SOURCE_CHANGED" "" }
if([int]$receipt.executor_created_partial_files_remaining -ne 0){ Die "EXECUTOR_PARTIAL_CLEANUP_FAILED" ([string]$receipt.executor_created_partial_files_remaining) }
if([int]$receipt.preexisting_partial_files_preserved -ne 1){ Die "PREEXISTING_PARTIAL_NOT_PRESERVED" ([string]$receipt.preexisting_partial_files_preserved) }
Write-Output "PASS: bounded copy performs partial promotion and independent source/destination rehashing"
Write-Output "PASS: duplicate, collision, bound, and stale-partial states fail closed"
Write-Output "PASS: source remains unchanged and the intentional stale fixture remains receipted"
Write-Output "SELFTEST_LD_STORAGE03_BOUNDED_COPY_EXECUTOR_OK"
