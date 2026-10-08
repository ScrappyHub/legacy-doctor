param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$BackupReceiptPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
function EnsureDir([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Container)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null } }
function Write-Lf([string]$Path,[string]$Text){ EnsureDir (Split-Path -Parent $Path); $t=($Text-replace"`r`n","`n")-replace"`r","`n";if(-not$t.EndsWith("`n")){$t+="`n"};[IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false)) }
function SafeStr([object]$Value){ if($null -eq $Value){ return "" }; return [string]$Value }
function SafeBool([object]$Value){ if($null -eq $Value){ return $false }; return [bool]$Value }
function SafeInt([object]$Value){ if($null -eq $Value){ return 0 }; return [int]$Value }
function Add-Unique([object[]]$Items,[string]$Value){ $out=@($Items);if(-not($out-contains$Value)){$out+=$Value};return @($out) }
function PathUnderRoot([string]$Root,[string]$Path){
  try { $r=[IO.Path]::GetFullPath($Root).TrimEnd("\")+"\";$p=[IO.Path]::GetFullPath($Path);return $p.StartsWith($r,[StringComparison]::OrdinalIgnoreCase) } catch { return $false }
}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
if(-not(Test-Path -LiteralPath $BackupReceiptPath -PathType Leaf)){Die "BACKUP_RECEIPT_MISSING" $BackupReceiptPath}
$BackupReceiptPath=(Resolve-Path -LiteralPath $BackupReceiptPath).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")

$errors=@();$rows=@();$verified=0;$copied=0;$duplicates=0;$sourceMismatch=0;$destinationMismatch=0;$missingDestination=0;$partials=@()
try {
  $receipt=LDREC-ConvertFromJson (Get-Content -LiteralPath $BackupReceiptPath -Raw)
  $schema=LDREC-ConvertFromJson (Get-Content -LiteralPath (Join-Path $RepoRoot "schemas\ld.media.mounted_backup.receipt.v1.json") -Raw)
  LDREC-AssertReceiptAgainstSchema -Receipt $receipt -Schema $schema -ExpectedSchema "ld.media.mounted_backup.receipt.v1"
} catch { $errors=Add-Unique $errors ("BACKUP_RECEIPT_INVALID:"+[string]$_.Exception.Message);$receipt=$null }

if($null -ne $receipt){
  if(-not(SafeBool $receipt.ok)){ $errors=Add-Unique $errors "BACKUP_RECEIPT_NOT_OK" }
  if((SafeStr $receipt.execution_status) -ne "executed_verified"){ $errors=Add-Unique $errors "BACKUP_RECEIPT_NOT_EXECUTED_VERIFIED" }
  if(SafeBool $receipt.writes_source){ $errors=Add-Unique $errors "SOURCE_WRITES_CLAIMED" }
  $sourceRoot=SafeStr $receipt.source_root;$destinationRoot=SafeStr $receipt.destination_root
  foreach($row in @($receipt.rows)){
    $rowErrors=@();$sourcePath=SafeStr $row.source_path;$destinationPath=SafeStr $row.destination_path;$expected=SafeStr $row.expected_sha256
    if((SafeStr $row.status) -notin @("COPIED_VERIFIED","SKIP_DUPLICATE_VERIFIED")){ $rowErrors=Add-Unique $rowErrors "ROW_STATUS_NOT_VERIFIED" }
    if($expected -notmatch "^[a-fA-F0-9]{64}$"){ $rowErrors=Add-Unique $rowErrors "EXPECTED_SHA256_INVALID" }
    if(-not(PathUnderRoot $sourceRoot $sourcePath)){ $rowErrors=Add-Unique $rowErrors "SOURCE_ESCAPE" }
    if(-not(PathUnderRoot $destinationRoot $destinationPath)){ $rowErrors=Add-Unique $rowErrors "DESTINATION_ESCAPE" }
    if(-not(Test-Path -LiteralPath $sourcePath -PathType Leaf)){ $rowErrors=Add-Unique $rowErrors "SOURCE_MISSING" }
    else { try { if((LDREC-HexSha256File $sourcePath) -cne $expected){$rowErrors=Add-Unique $rowErrors "SOURCE_HASH_MISMATCH";$sourceMismatch++} } catch {$rowErrors=Add-Unique $rowErrors "SOURCE_HASH_READ_FAILED"} }
    if(-not(Test-Path -LiteralPath $destinationPath -PathType Leaf)){ $rowErrors=Add-Unique $rowErrors "DESTINATION_MISSING";$missingDestination++ }
    else { try { if((LDREC-HexSha256File $destinationPath) -cne $expected){$rowErrors=Add-Unique $rowErrors "DESTINATION_HASH_MISMATCH";$destinationMismatch++} } catch {$rowErrors=Add-Unique $rowErrors "DESTINATION_HASH_READ_FAILED"} }
    $status=SafeStr $row.status;if($status -eq "COPIED_VERIFIED"){$copied++}elseif($status -eq "SKIP_DUPLICATE_VERIFIED"){$duplicates++}
    $rowOk=(@($rowErrors).Count -eq 0);if($rowOk){$verified++}
    $rows+=,[ordered]@{relative_path=(SafeStr $row.relative_path);source_path=$sourcePath;destination_path=$destinationPath;status=$status;expected_sha256=$expected;verify_ok=[bool]$rowOk;errors=@($rowErrors)}
    foreach($e in @($rowErrors)){$errors=Add-Unique $errors ((SafeStr $row.relative_path)+":"+[string]$e)}
  }
  $partials=@(Get-ChildItem -LiteralPath $destinationRoot -File -Recurse -Filter "*.legacy-doctor.partial" -ErrorAction SilentlyContinue)
  if($partials.Count -gt 0){$errors=Add-Unique $errors "PARTIAL_OUTPUT_PRESENT"}
  if($verified -ne @($receipt.rows).Count){$errors=Add-Unique $errors "ROW_VERIFICATION_COUNT_MISMATCH"}
  if($copied -ne (SafeInt $receipt.copied_file_count)){$errors=Add-Unique $errors "COPIED_COUNT_MISMATCH"}
  if($duplicates -ne (SafeInt $receipt.duplicate_file_count)){$errors=Add-Unique $errors "DUPLICATE_COUNT_MISMATCH"}
}

$ok=(@($errors).Count -eq 0)
$status=$(if($ok){"verified"}else{"blocked"})
$outReceipt=[ordered]@{schema="ld.device.storage03_post_copy_verifier.receipt.v1";event_type="ld.device.storage03_post_copy_verifier.receipt.v1";ok=[bool]$ok;repo_root=$RepoRoot;mode="storage03_post_copy_verifier";destructive=$false;writes_source=$false;performs_copy=$false;writes_destination=$false;hashes_file_contents=$true;consumes_receipt_schema="ld.media.mounted_backup.receipt.v1";backup_receipt_path=$BackupReceiptPath;backup_receipt_sha256=$(if(Test-Path -LiteralPath $BackupReceiptPath -PathType Leaf){LDREC-HexSha256File $BackupReceiptPath}else{""});verification_status=$status;row_count=[int]$rows.Count;verified_row_count=[int]$verified;copied_row_count=[int]$copied;duplicate_row_count=[int]$duplicates;source_hash_mismatch_count=[int]$sourceMismatch;destination_hash_mismatch_count=[int]$destinationMismatch;missing_destination_count=[int]$missingDestination;partial_file_count=[int]$(if($null -ne $partials){$partials.Count}else{0});rows=@($rows);blockers=@($errors);created_utc=[DateTime]::UtcNow.ToString("o")}
$outDir=Join-Path $RepoRoot "proofs\receipts\device_storage03_post_copy_verifier";EnsureDir $outDir;$outPath=Join-Path $outDir ("storage03_post_copy_verifier_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")+".json");Write-Lf $outPath ($outReceipt|ConvertTo-Json -Depth 100 -Compress)
Write-Output ("DEVICE_STORAGE03_POST_COPY_VERIFIER_PATH: "+$outPath);Write-Output ($outReceipt|ConvertTo-Json -Depth 100 -Compress);if($ok){Write-Output "LD_DEVICE_STORAGE03_POST_COPY_VERIFIER_OK"}else{Write-Output "LD_DEVICE_STORAGE03_POST_COPY_VERIFIER_BLOCKED"}
