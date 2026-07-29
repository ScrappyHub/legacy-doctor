param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Require([bool]$Condition,[string]$Code,[string]$Detail){
  if(-not $Condition){
    Die $Code $Detail
  }
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_GATE_MISSING" $Path
  }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }
}

function Get-LatestLine([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }
  $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
  Require ($lines.Count -gt 0) "EMPTY_FILE" $Path
  return $lines[-1]
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$ProbeLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_device_probe_v1.ps1"
$HealthLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_health_v1.ps1"
$InspectScript = Join-Path $RepoRoot "scripts\storage\ld_inspect_device_v1.ps1"
$InspectSchema = Join-Path $RepoRoot "schemas\ld.device.inspect.receipt.v1.json"
$HealthSchema = Join-Path $RepoRoot "schemas\ld.device.health.receipt.v1.json"
$LedgerPath = Join-Path $RepoRoot "proofs\receipts\device_inspect.ndjson"

foreach($p in @($ProbeLib,$HealthLib,$InspectScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

foreach($p in @($InspectSchema,$HealthSchema)){
  Require (Test-Path -LiteralPath $p -PathType Leaf) "MISSING_SCHEMA" $p
  Write-Host ("SCHEMA_OK: " + $p) -ForegroundColor DarkGray
}

$disk = Get-Disk | Sort-Object Number | Select-Object -First 1
Require ($null -ne $disk) "NO_DISKS" "Get-Disk returned no rows"

$beforeCount = 0
if(Test-Path -LiteralPath $LedgerPath -PathType Leaf){
  $beforeCount = @((Get-Content -LiteralPath $LedgerPath -Encoding UTF8)).Count
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $InspectScript -RepoRoot $RepoRoot -DiskNumber ([int]$disk.Number) 2>&1

foreach($x in @(@($out))){
  [Console]::Out.WriteLine($x)
}

$joined = (@(@($out)) -join "`n")
Require ($joined -match "LD_INSPECT_DEVICE_OK") "INSPECT_RUN_FAILED" "missing LD_INSPECT_DEVICE_OK"

$afterCount = @((Get-Content -LiteralPath $LedgerPath -Encoding UTF8)).Count
Require ($afterCount -ge ($beforeCount + 2)) "LEDGER_APPEND_FAIL" ("before=" + $beforeCount + " after=" + $afterCount)

$lines = @(Get-Content -LiteralPath $LedgerPath -Encoding UTF8)
$health = $lines[-1] | ConvertFrom-Json
$inspect = $lines[-2] | ConvertFrom-Json

Require ($inspect.schema -eq "ld.device.inspect.receipt.v1") "INSPECT_SCHEMA_BAD" ([string]$inspect.schema)
Require ($inspect.event_type -eq "ld.device.inspect.receipt.v1") "INSPECT_EVENT_BAD" ([string]$inspect.event_type)
Require ($inspect.disk_number -eq [int]$disk.Number) "INSPECT_DISK_BAD" ([string]$inspect.disk_number)
Require (-not [string]::IsNullOrWhiteSpace([string]$inspect.device_id)) "INSPECT_DEVICE_ID_BAD" ""
Require ($inspect.partitions.Count -ge 0) "INSPECT_PARTITIONS_BAD" ""
Require ($inspect.volumes.Count -ge 0) "INSPECT_VOLUMES_BAD" ""
Require (-not [string]::IsNullOrWhiteSpace([string]$inspect.preservation_recommendation)) "INSPECT_RECOMMENDATION_BAD" ""

Require ($health.schema -eq "ld.device.health.receipt.v1") "HEALTH_SCHEMA_BAD" ([string]$health.schema)
Require ($health.event_type -eq "ld.device.health.receipt.v1") "HEALTH_EVENT_BAD" ([string]$health.event_type)
Require ($health.disk_number -eq [int]$disk.Number) "HEALTH_DISK_BAD" ([string]$health.disk_number)
Require (-not [string]::IsNullOrWhiteSpace([string]$health.health_summary)) "HEALTH_SUMMARY_BAD" ""
Require ($health.signals.Count -ge 1) "HEALTH_SIGNALS_BAD" ""
Require (-not [string]::IsNullOrWhiteSpace([string]$health.preservation_recommendation)) "HEALTH_RECOMMENDATION_BAD" ""

Write-Host "PASS: inspect receipt structure" -ForegroundColor Green
Write-Host "PASS: health receipt structure" -ForegroundColor Green
Write-Host "SELFTEST_LD_INSPECT_DEVICE_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"