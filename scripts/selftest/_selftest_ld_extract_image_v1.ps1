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

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,(Utf8NoBom))
}

function HexSha256File([string]$Path){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [IO.File]::OpenRead($Path)
    try {
      $hash = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }
  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$ExtractLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_extract_v1.ps1"
$ExtractScript = Join-Path $RepoRoot "scripts\storage\ld_extract_image_v1.ps1"
$SchemaPath = Join-Path $RepoRoot "schemas\ld.device.extract.receipt.v1.json"
$AcquireScript = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"
$RangesDir = Join-Path $RepoRoot "proofs\extract\selftest_ranges"

foreach($p in @($ExtractLib,$ExtractScript,$AcquireScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

Require (Test-Path -LiteralPath $SchemaPath -PathType Leaf) "MISSING_SCHEMA" $SchemaPath
Write-Host ("SCHEMA_OK: " + $SchemaPath) -ForegroundColor DarkGray

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

# Build fresh image to extract from
$srcPath = Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin"
$acqOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AcquireScript -RepoRoot $RepoRoot -SourcePath $srcPath -Mode raw_image -ChunkSizeBytes 262144 2>&1
$acqJoined = (@(@($acqOut)) -join "`n")
foreach($x in @(@($acqOut))){
  [Console]::Out.WriteLine($x)
}
Require ($acqJoined -match "LD_BACKUP_DEVICE_OK") "ACQUIRE_SETUP_FAIL" ""

$backupLedger = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"
$lastBackup = Get-Content -LiteralPath $backupLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
$imagePath = [string]$lastBackup.image_path

# Positive: full copy
$fullOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ExtractScript -RepoRoot $RepoRoot -ImagePath $imagePath -Mode full_copy 2>&1
$fullJoined = (@(@($fullOut)) -join "`n")
foreach($x in @(@($fullOut))){
  [Console]::Out.WriteLine($x)
}
Require ($fullJoined -match "LD_EXTRACT_IMAGE_OK") "FULL_COPY_FAIL" ""

$extractLedger = Join-Path $RepoRoot "proofs\receipts\device_extract.ndjson"
$lastExtract = Get-Content -LiteralPath $extractLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
Require ([string]$lastExtract.mode -eq "full_copy") "FULL_COPY_MODE_BAD" ([string]$lastExtract.mode)

$fullManifest = Get-Content -LiteralPath ([string]$lastExtract.manifest_path) -Raw -Encoding UTF8 | ConvertFrom-Json
Require ([int]$fullManifest.output_count -eq 1) "FULL_COPY_COUNT_BAD" ([string]$fullManifest.output_count)

$copied = [string]$fullManifest.outputs[0].output_path
Require ((HexSha256File $copied) -eq (HexSha256File $imagePath)) "FULL_COPY_HASH_MISMATCH" ""

# Positive: byte ranges
if(-not (Test-Path -LiteralPath $RangesDir -PathType Container)){
  New-Item -ItemType Directory -Force -Path $RangesDir | Out-Null
}
$rangesJson = Join-Path $RangesDir "ranges.json"
Write-Utf8NoBomLf $rangesJson '{"ranges":[{"name":"head","offset":0,"size_bytes":64},{"name":"mid","offset":100,"size_bytes":32},{"name":"tail","offset":1048500,"size_bytes":76}]}'

$rangeOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ExtractScript -RepoRoot $RepoRoot -ImagePath $imagePath -Mode byte_ranges -RangesJsonPath $rangesJson 2>&1
$rangeJoined = (@(@($rangeOut)) -join "`n")
foreach($x in @(@($rangeOut))){
  [Console]::Out.WriteLine($x)
}
Require ($rangeJoined -match "LD_EXTRACT_IMAGE_OK") "RANGE_EXTRACT_FAIL" ""

$lastExtract2 = Get-Content -LiteralPath $extractLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
Require ([string]$lastExtract2.mode -eq "byte_ranges") "RANGE_MODE_BAD" ([string]$lastExtract2.mode)

$rangeManifest = Get-Content -LiteralPath ([string]$lastExtract2.manifest_path) -Raw -Encoding UTF8 | ConvertFrom-Json
Require ([int]$rangeManifest.output_count -eq 3) "RANGE_COUNT_BAD" ([string]$rangeManifest.output_count)

# Negative: missing ranges json for byte_ranges
$negOut = $null
$negJoined = ""

try {
  $negOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ExtractScript -RepoRoot $RepoRoot -ImagePath $imagePath -Mode byte_ranges 2>&1
  $negJoined = (@(@($negOut)) -join "`n")
}
catch {
  $negJoined = $_.Exception.Message
}

if($negOut){
  foreach($x in @(@($negOut))){
    [Console]::Out.WriteLine($x)
  }
}

Require ($negJoined -match "RANGES_JSON_REQUIRED") "NEGATIVE_MISSING_RANGES_NOT_CAUGHT" ""

Write-Host "PASS: full copy extract" -ForegroundColor Green
Write-Host "PASS: byte range extract
Write-Host "CHECK: negative capture enforcement" -ForegroundColor DarkGray
PASS: negative missing ranges" -ForegroundColor Green
Write-Host "SELFTEST_LD_EXTRACT_IMAGE_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
