param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$Code,[string]$Detail){throw($Code+":"+$Detail)}
function Require([bool]$Condition,[string]$Code,[string]$Detail){if(-not$Condition){Die $Code $Detail}}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1")
. (Join-Path $RepoRoot "scripts\storage\_lib_ld_drive_letter_plan_v1.ps1")
$dataDisk=[ordered]@{is_offline=$false;is_boot=$false;is_system=$false}
$dataPartition=[ordered]@{is_boot=$false;is_system=$false;is_hidden=$false;drive_letter="";partition_type="Basic";size_bytes=[UInt64]1073741824}
$ntfsVolume=[ordered]@{file_system="NTFS";drive_type="Fixed";label="ARCHIVE"}
$eligible=@(LDLTR-EvaluateCandidate -Disk $dataDisk -Partition $dataPartition -Volume $ntfsVolume)
Require ($eligible.Count-eq 0) "SAFE_DATA_VOLUME_BLOCKED" ($eligible-join",")
$letter=LDLTR-ChooseLetter -UsedLetters @("C","D","E","G","P","S") -ReservedLetters @("A","B","C")
Require ($letter-eq"F") "LETTER_CHOICE_NOT_DETERMINISTIC" $letter
$systemDisk=[ordered]@{is_offline=$false;is_boot=$true;is_system=$true}
$systemPartition=[ordered]@{is_boot=$true;is_system=$true;is_hidden=$true;drive_letter="";partition_type="System";size_bytes=[UInt64]104857600}
$system=@(LDLTR-EvaluateCandidate -Disk $systemDisk -Partition $systemPartition -Volume $ntfsVolume)
Require ($system-contains"BOOT_DISK_EXCLUDED") "BOOT_DISK_GATE_MISSING" ""
Require ($system-contains"SYSTEM_PARTITION_EXCLUDED") "SYSTEM_PARTITION_GATE_MISSING" ""
Require ($system-contains"HIDDEN_PARTITION_EXCLUDED") "HIDDEN_PARTITION_GATE_MISSING" ""
Require ($system-contains"PROTECTED_PARTITION_TYPE") "PROTECTED_TYPE_GATE_MISSING" ""
$raw=@(LDLTR-EvaluateCandidate -Disk $dataDisk -Partition $dataPartition -Volume ([ordered]@{file_system="RAW";drive_type="Fixed"}))
Require ($raw-contains"FILESYSTEM_UNKNOWN_OR_RAW") "RAW_VOLUME_GATE_MISSING" ""
$existing=[ordered]@{is_boot=$false;is_system=$false;is_hidden=$false;drive_letter="E";partition_type="Basic";size_bytes=[UInt64]1073741824}
$present=@(LDLTR-EvaluateCandidate -Disk $dataDisk -Partition $existing -Volume $ntfsVolume)
Require ($present-contains"DRIVE_LETTER_ALREADY_PRESENT") "EXISTING_LETTER_GATE_MISSING" ""

$planner=Join-Path $RepoRoot "scripts\storage\ld_drive_letter_plan_v1.ps1";$output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $planner -RepoRoot $RepoRoot
if($LASTEXITCODE-ne 0){Die "PLANNER_EXIT_NONZERO" ([string]$LASTEXITCODE)}
$receipt=LDREC-ReadReceiptFromOutput -Output $output -ExpectedSchema "ld.device.drive_letter_plan.receipt.v1" -SchemaDirectory (Join-Path $RepoRoot "schemas")
Require (-not[bool]$receipt.assigns_drive_letter) "PLANNER_ASSIGNS_LETTERS" ""
Require (-not[bool]$receipt.execution_supported) "PLANNER_EXECUTION_ENABLED" ""
Write-Output "PASS: deterministic free-letter selection works for an eligible data volume"
Write-Output "PASS: boot, system, hidden, protected, raw, and already-lettered partitions are excluded"
Write-Output "PASS: runtime planner emits a closed read-only receipt"
Write-Output "SELFTEST_LD_DRIVE_LETTER_PLAN_OK"

