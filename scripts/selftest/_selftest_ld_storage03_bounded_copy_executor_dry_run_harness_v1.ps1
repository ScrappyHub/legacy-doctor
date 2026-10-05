param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
function Die([string]$Code,[string]$Detail){throw($Code+":"+$Detail)}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path;. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")
$harness=Join-Path $RepoRoot "scripts\storage\ld_bounded_copy_executor_dry_run_harness_v1.ps1";$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $harness -RepoRoot $RepoRoot;if($LASTEXITCODE-ne0){Die "HARNESS_EXIT_NONZERO" ([string]$LASTEXITCODE)}
$receipt=LDREC-ReadReceiptFromOutput $out "ld.device.bounded_copy_executor_dry_run_harness.receipt.v1" (Join-Path $RepoRoot "schemas")
if(-not[bool]$receipt.ok){Die "HARNESS_RECEIPT_NOT_OK" ""};if(-not(Test-Path -LiteralPath ([string]$receipt.guard_receipt_path) -PathType Leaf)){Die "GUARD_RECEIPT_MISSING" ([string]$receipt.guard_receipt_path)};if((LDREC-HexSha256File ([string]$receipt.guard_receipt_path))-cne[string]$receipt.guard_receipt_sha256){Die "GUARD_RECEIPT_HASH_MISMATCH" ""};if([bool]$receipt.guard_would_invoke_future_executor){Die "GUARD_WOULD_INVOKE" ""};if([int]$receipt.would_execute_count-ne0){Die "WOULD_EXECUTE_COUNT_NONZERO" ([string]$receipt.would_execute_count)};if([int]$receipt.would_not_execute_count-ne1){Die "WOULD_NOT_EXECUTE_COUNT_BAD" ([string]$receipt.would_not_execute_count)};if([bool]$receipt.performs_copy){Die "PERFORMS_COPY_TRUE" ""};if([bool]$receipt.writes_destination){Die "WRITES_DESTINATION_TRUE" ""};if(([string]$receipt.rows[0].disposition)-cne"WOULD_NOT_EXECUTE"){Die "WOULD_NOT_EXECUTE_ROW_MISSING" ""}
Write-Output "PASS: blocked contract is exercised through the bounded dry-run harness"
Write-Output "PASS: would_execute_count=0 and WOULD_NOT_EXECUTE row are independently checked"
Write-Output "PASS: dry-run harness performs no copy and writes no destination bytes"
Write-Output "SELFTEST_LD_STORAGE03_BOUNDED_COPY_EXECUTOR_DRY_RUN_HARNESS_OK"
