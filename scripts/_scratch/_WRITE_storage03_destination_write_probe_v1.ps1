param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  if($null -eq $Text){ Die "TEXT_MISSING" $Path }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_MISSING" $Path
  }

  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ":" + $e.Message)
  }

  Write-Host ("PARSE_OK: " + $Path) -ForegroundColor Green
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$ProbeScript = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DestinationPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Sha256HexBytes([byte[]]$Bytes){
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function SafeStr([object]$Value){
  if($null -eq $Value){ return "" }
  return [string]$Value
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if([string]::IsNullOrWhiteSpace($DestinationPath)){
  $DestinationPath = $RepoRoot
}

$destinationInput = $DestinationPath
$destinationExists = Test-Path -LiteralPath $DestinationPath -PathType Container

$destinationResolved = ""
if($destinationExists){
  $destinationResolved = (Resolve-Path -LiteralPath $DestinationPath).Path
} else {
  try {
    $destinationResolved = [IO.Path]::GetFullPath($DestinationPath)
  } catch {
    $destinationResolved = $DestinationPath
  }
}

$tempPath = ""
$tempCreated = $false
$tempReadBack = $false
$tempHashOk = $false
$tempDeleted = $false
$writeOk = $false
$errorText = ""

$payloadText = "LEGACY_DOCTOR_DESTINATION_WRITE_PROBE_V1`n"
$payloadBytes = [Text.UTF8Encoding]::new($false).GetBytes($payloadText)
$expectedHash = Sha256HexBytes $payloadBytes
$actualHash = ""

if($destinationExists){
  $name = ".ld_destination_write_probe_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + "_" + ([Guid]::NewGuid().ToString("N")) + ".tmp"
  $tempPath = Join-Path $destinationResolved $name

  $fs = $null
  try {
    $fs = [IO.File]::Open($tempPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $fs.Write($payloadBytes,0,$payloadBytes.Length)
    $fs.Flush($true)
    $fs.Dispose()
    $fs = $null

    $tempCreated = Test-Path -LiteralPath $tempPath -PathType Leaf

    $readBytes = [IO.File]::ReadAllBytes($tempPath)
    $tempReadBack = $true
    $actualHash = Sha256HexBytes $readBytes
    $tempHashOk = ($actualHash -eq $expectedHash)
    $writeOk = ($tempCreated -and $tempReadBack -and $tempHashOk)
  } catch {
    $errorText = $_.Exception.Message
  } finally {
    if($null -ne $fs){ $fs.Dispose() }

    try {
      if(Test-Path -LiteralPath $tempPath -PathType Leaf){
        Remove-Item -LiteralPath $tempPath -Force
      }
    } catch {
      if([string]::IsNullOrWhiteSpace($errorText)){
        $errorText = $_.Exception.Message
      }
    }

    $tempDeleted = (-not (Test-Path -LiteralPath $tempPath -PathType Leaf))
  }
} else {
  $errorText = "DESTINATION_MISSING"
}

$receipt = [ordered]@{
  schema = "ld.device.destination_write_probe.receipt.v1"
  event_type = "ld.device.destination_write_probe.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "destination_write_probe"
  destructive = $false
  write_test = $true
  performs_copy = $false
  destination_path_input = $destinationInput
  destination_path_resolved = $destinationResolved
  destination_exists = [bool]$destinationExists
  probe_file_path = $tempPath
  probe_payload_bytes = [int]$payloadBytes.Length
  expected_sha256 = $expectedHash
  actual_sha256 = $actualHash
  temp_created = [bool]$tempCreated
  temp_read_back = [bool]$tempReadBack
  temp_hash_ok = [bool]$tempHashOk
  temp_deleted = [bool]$tempDeleted
  write_probe_ok = [bool]$writeOk
  error = SafeStr $errorText
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_destination_write_probe"
EnsureDir $outDir
$outPath = Join-Path $outDir ("destination_write_probe_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 80 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_DESTINATION_WRITE_PROBE_PATH: " + $outPath)
Write-Output ("DEVICE_DESTINATION_WRITE_PROBE_OK: " + [string]$writeOk)
Write-Output $json
Write-Output "LD_DEVICE_DESTINATION_WRITE_PROBE_OK"
'@

$Schema = '{"$schema":"https://json-schema.org/draft/2020-12/schema","title":"Legacy Doctor Device Destination Write Probe Receipt v1","type":"object","required":["schema","event_type","ok","repo_root","mode","destructive","write_test","performs_copy","destination_path_input","destination_path_resolved","destination_exists","probe_file_path","probe_payload_bytes","expected_sha256","actual_sha256","temp_created","temp_read_back","temp_hash_ok","temp_deleted","write_probe_ok","error","created_utc"],"properties":{"schema":{"const":"ld.device.destination_write_probe.receipt.v1"},"event_type":{"const":"ld.device.destination_write_probe.receipt.v1"},"ok":{"type":"boolean"},"repo_root":{"type":"string"},"mode":{"const":"destination_write_probe"},"destructive":{"const":false},"write_test":{"const":true},"performs_copy":{"const":false},"destination_path_input":{"type":"string"},"destination_path_resolved":{"type":"string"},"destination_exists":{"type":"boolean"},"probe_file_path":{"type":"string"},"probe_payload_bytes":{"type":"integer"},"expected_sha256":{"type":"string"},"actual_sha256":{"type":"string"},"temp_created":{"type":"boolean"},"temp_read_back":{"type":"boolean"},"temp_hash_ok":{"type":"boolean"},"temp_deleted":{"type":"boolean"},"write_probe_ok":{"type":"boolean"},"error":{"type":"string"},"created_utc":{"type":"string"}}}'

$Selftest = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_destination_write_probe_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -DestinationPath $RepoRoot
if($LASTEXITCODE -ne 0){ Die "DESTINATION_WRITE_PROBE_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_DESTINATION_WRITE_PROBE_OK"){
  Die "DESTINATION_WRITE_PROBE_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"write_test":true'){
  Die "WRITE_TEST_TRUE_MISSING" ""
}

if($text -notmatch '"performs_copy":false'){
  Die "PERFORMS_COPY_FALSE_MISSING" ""
}

if($text -notmatch '"temp_hash_ok":true'){
  Die "TEMP_HASH_OK_MISSING" ""
}

if($text -notmatch '"temp_deleted":true'){
  Die "TEMP_DELETED_TRUE_MISSING" ""
}

if($text -notmatch '"write_probe_ok":true'){
  Die "WRITE_PROBE_OK_MISSING" ""
}

Write-Output $text
Write-Output "PASS: destination write probe emitted"
Write-Output "PASS: temp file hash verified"
Write-Output "PASS: temp file cleanup verified"
Write-Output "SELFTEST_LD_STORAGE03_DESTINATION_WRITE_PROBE_OK"
'@

$Runner = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DestinationPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_MISSING" $Path
  }

  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ":" + $e.Message)
  }

  Write-Output ("PARSE_OK: " + $Path)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$files = @(
  (Join-Path $RepoRoot "scripts\storage\ld_destination_write_probe_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_destination_write_probe_v1.ps1")
)

foreach($f in @($files)){
  Parse-GateFile $f
}

$schema = Join-Path $RepoRoot "schemas\ld.device.destination_write_probe.receipt.v1.json"
if(-not (Test-Path -LiteralPath $schema -PathType Leaf)){
  Die "SCHEMA_MISSING" $schema
}

Write-Output ("SCHEMA_OK: " + $schema)

$selftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_destination_write_probe_v1.ps1"
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $selftest -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "SELFTEST_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$outText = ($out -join "`n")
Write-Output $outText

if($outText -notmatch "SELFTEST_LD_STORAGE03_DESTINATION_WRITE_PROBE_OK"){
  Die "SELFTEST_TOKEN_MISSING" ""
}

Write-Output "LEGACY_DOCTOR_STORAGE03_DESTINATION_WRITE_PROBE_GREEN"
'@

$Docs = @'
# LD-STORAGE-03H Destination Write Probe v1

Status: first checkpoint.

This lane performs a tiny explicit destination write probe.

It:
- requires an existing destination directory
- creates one temporary probe file
- writes a fixed payload
- flushes the file
- reads the payload back
- verifies SHA-256
- deletes the temporary file
- records cleanup success

It does not:
- copy backup files
- image disks
- format disks
- modify source volumes
- create backup sets

This is the first explicit bounded write lane and is limited to destination temp-probe validation only.

Next checkpoints:
- backup dry-run enumerator
- destination selector plus write-probe join
- copy executor later
'@

Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\storage\ld_destination_write_probe_v1.ps1") $ProbeScript
Write-Utf8NoBomLf (Join-Path $RepoRoot "schemas\ld.device.destination_write_probe.receipt.v1.json") $Schema
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_destination_write_probe_v1.ps1") $Selftest
Write-Utf8NoBomLf (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_storage03_destination_write_probe_v1.ps1") $Runner
Write-Utf8NoBomLf (Join-Path $RepoRoot "docs\WBS\LD_STORAGE_03H_DESTINATION_WRITE_PROBE_v1.md") $Docs

$toParse = @(
  (Join-Path $RepoRoot "scripts\storage\ld_destination_write_probe_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_destination_write_probe_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_storage03_destination_write_probe_v1.ps1")
)

foreach($p in @($toParse)){
  Parse-GateFile $p
}

Write-Host "LD_STORAGE03_DESTINATION_WRITE_PROBE_FILES_READY" -ForegroundColor Green