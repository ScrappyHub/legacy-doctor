param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }

function Expect-Rejection([scriptblock]$Action,[string]$ExpectedCode){
  $caught = ""
  try {
    & $Action
  } catch {
    $caught = [string]$_.Exception.Message
  }

  if([string]::IsNullOrWhiteSpace($caught)){ Die "EXPECTED_REJECTION_MISSING" $ExpectedCode }
  if(-not $caught.Contains($ExpectedCode)){ Die "WRONG_REJECTION" ($ExpectedCode + ":" + $caught) }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$libraryPath = Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1"
if(-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)){ Die "RECEIPT_LIBRARY_MISSING" $libraryPath }
. $libraryPath

$schemaName = "ld.device.inventory.receipt.v1"
$schemaDirectory = Join-Path $RepoRoot "schemas"
$valid = [ordered]@{
  schema = $schemaName
  event_type = $schemaName
  ok = $false
  availability = "unavailable"
  error_code = "SELFTEST_UNAVAILABLE"
  error = "deterministic fixture"
  repo_root = $RepoRoot
  disk_count = 0
  disks = @()
  visible_volume_count = 0
  visible_volumes = @()
  created_utc = "2026-01-01T00:00:00.0000000Z"
}
$validJson = $valid | ConvertTo-Json -Depth 10 -Compress

$parsed = LDREC-ReadReceiptFromOutput -Output @("diagnostic",$validJson,"SUCCESS_TOKEN") -ExpectedSchema $schemaName -SchemaDirectory $schemaDirectory
if(([string]$parsed.error_code) -ne "SELFTEST_UNAVAILABLE"){ Die "VALID_RECEIPT_NOT_RETURNED" ([string]$parsed.error_code) }

$missingRequired = [ordered]@{}
foreach($key in $valid.Keys){ if($key -ne "error"){ $missingRequired[$key] = $valid[$key] } }
Expect-Rejection -ExpectedCode "RECEIPT_REQUIRED_PROPERTY_MISSING" -Action {
  LDREC-ReadReceiptFromOutput -Output @(($missingRequired | ConvertTo-Json -Depth 10 -Compress)) -ExpectedSchema $schemaName -SchemaDirectory $schemaDirectory
}

$wrongEvent = [ordered]@{}
foreach($key in $valid.Keys){ $wrongEvent[$key] = $valid[$key] }
$wrongEvent.event_type = "ld.device.other.receipt.v1"
Expect-Rejection -ExpectedCode "RECEIPT_PROPERTY_CONST_MISMATCH" -Action {
  LDREC-ReadReceiptFromOutput -Output @(($wrongEvent | ConvertTo-Json -Depth 10 -Compress)) -ExpectedSchema $schemaName -SchemaDirectory $schemaDirectory
}

$undeclared = [ordered]@{}
foreach($key in $valid.Keys){ $undeclared[$key] = $valid[$key] }
$undeclared.untrusted_claim = $true
Expect-Rejection -ExpectedCode "RECEIPT_UNDECLARED_PROPERTY" -Action {
  LDREC-ReadReceiptFromOutput -Output @(($undeclared | ConvertTo-Json -Depth 10 -Compress)) -ExpectedSchema $schemaName -SchemaDirectory $schemaDirectory
}

Expect-Rejection -ExpectedCode "RECEIPT_OUTPUT_AMBIGUOUS" -Action {
  LDREC-ReadReceiptFromOutput -Output @($validJson,$validJson) -ExpectedSchema $schemaName -SchemaDirectory $schemaDirectory
}

Expect-Rejection -ExpectedCode "RECEIPT_JSON_INVALID" -Action {
  LDREC-ReadReceiptFromOutput -Output @('{"schema":"ld.device.inventory.receipt.v1"') -ExpectedSchema $schemaName -SchemaDirectory $schemaDirectory
}

Write-Output "LD_RECEIPT_CONSUMER_NEGATIVE_CASES_OK"
Write-Output "FULL_GREEN"
