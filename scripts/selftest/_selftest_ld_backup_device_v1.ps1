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

$AcquireLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_acquire_v1.ps1"
$BackupScript = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"
$BackupSchema = Join-Path $RepoRoot "schemas\ld.device.backup.receipt.v1.json"
$LedgerPath = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"
$ScratchDir = Join-Path $RepoRoot "proofs\acquire\selftest_inputs"

foreach($p in @($AcquireLib,$BackupScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

Require (Test-Path -LiteralPath $BackupSchema -PathType Leaf) "MISSING_SCHEMA" $BackupSchema
Write-Host ("SCHEMA_OK: " + $BackupSchema) -ForegroundColor DarkGray

if(-not (Test-Path -LiteralPath $ScratchDir -PathType Container)){
  New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null
}

$SourcePath = Join-Path $ScratchDir "synthetic_source.bin"

$bytes = New-Object byte[] 1048576
for($i=0; $i -lt $bytes.Length; $i++){
  $bytes[$i] = [byte]($i % 251)
}
[IO.File]::WriteAllBytes($SourcePath,$bytes)

$expectedSourceHash = HexSha256File $SourcePath
$beforeCount = 0
if(Test-Path -LiteralPath $LedgerPath -PathType Leaf){
  $beforeCount = @((Get-Content -LiteralPath $LedgerPath -Encoding UTF8)).Count
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BackupScript -RepoRoot $RepoRoot -SourcePath $SourcePath -Mode raw_image -ChunkSizeBytes 262144 2>&1

foreach($x in @(@($out))){
  [Console]::Out.WriteLine($x)
}

$joined = (@(@($out)) -join "`n")
Require ($joined -match "LD_BACKUP_DEVICE_OK") "BACKUP_RUN_FAILED" "missing LD_BACKUP_DEVICE_OK"

$afterCount = @((Get-Content -LiteralPath $LedgerPath -Encoding UTF8)).Count
Require ($afterCount -ge ($beforeCount + 1)) "LEDGER_APPEND_FAIL" ("before=" + $beforeCount + " after=" + $afterCount)

$last = (Get-Content -LiteralPath $LedgerPath -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json)

Require ($last.schema -eq "ld.device.backup.receipt.v1") "BACKUP_SCHEMA_BAD" ([string]$last.schema)
Require ($last.source_kind -eq "image_file") "SOURCE_KIND_BAD" ([string]$last.source_kind)
Require ($last.mode -eq "raw_image") "MODE_BAD" ([string]$last.mode)
Require (Test-Path -LiteralPath ([string]$last.image_path) -PathType Leaf) "IMAGE_PATH_MISSING" ([string]$last.image_path)
Require (Test-Path -LiteralPath ([string]$last.manifest_path) -PathType Leaf) "MANIFEST_PATH_MISSING" ([string]$last.manifest_path)
Require ([int]$last.chunk_size_bytes -eq 262144) "CHUNK_SIZE_BAD" ([string]$last.chunk_size_bytes)

$imageHash = HexSha256File ([string]$last.image_path)
Require ($imageHash -eq $expectedSourceHash) "IMAGE_HASH_MISMATCH" ("actual=" + $imageHash + " expected=" + $expectedSourceHash)
Require ([string]$last.image_sha256 -eq $expectedSourceHash) "RECEIPT_IMAGE_HASH_BAD" ([string]$last.image_sha256)

$manifest = Get-Content -LiteralPath ([string]$last.manifest_path) -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($manifest.schema -eq "ld.device.backup.manifest.v1") "MANIFEST_SCHEMA_BAD" ([string]$manifest.schema)
Require ([int]$manifest.chunk_count -eq 4) "CHUNK_COUNT_BAD" ([string]$manifest.chunk_count)
Require ([string]$manifest.image_sha256 -eq $expectedSourceHash) "MANIFEST_IMAGE_HASH_BAD" ([string]$manifest.image_sha256)

Write-Host "PASS: backup receipt structure" -ForegroundColor Green
Write-Host "PASS: image hash matches source" -ForegroundColor Green
Write-Host "PASS: chunked manifest structure" -ForegroundColor Green
Write-Host "SELFTEST_LD_BACKUP_DEVICE_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"