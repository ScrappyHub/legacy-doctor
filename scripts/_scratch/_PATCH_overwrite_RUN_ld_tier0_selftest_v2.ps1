param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-Gate([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  [ScriptBlock]::Create($raw) | Out-Null
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\_RUN_ld_tier0_selftest_v1.ps1"

$body = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("PARSE_GATE_MISSING: " + $Path)
  }
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  [ScriptBlock]::Create($raw) | Out-Null
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$Backup = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"
$Verify = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"

foreach($p in @($Backup,$Verify)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

Write-Host "RUN: backup selftest acquisition" -ForegroundColor Cyan

$src = Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin"
if(-not (Test-Path -LiteralPath $src -PathType Leaf)){
  Die ("LD_SELFTEST_FAIL:SYNTHETIC_SOURCE_MISSING " + $src)
}

$out1 = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Backup `
  -RepoRoot $RepoRoot `
  -SourcePath $src `
  -Mode raw_image `
  -ChunkSizeBytes 262144 2>&1

foreach($x in @(@($out1))){
  [Console]::Out.WriteLine($x)
}

if($LASTEXITCODE -ne 0){
  Die ("LD_SELFTEST_FAIL:BACKUP_FAILED exit=" + $LASTEXITCODE)
}

$joined1 = (@(@($out1)) -join "`n")
if($joined1 -notmatch "LD_BACKUP_DEVICE_OK"){
  Die "LD_SELFTEST_FAIL:BACKUP_TOKEN_MISSING"
}

$ledger = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"
if(-not (Test-Path -LiteralPath $ledger -PathType Leaf)){
  Die ("LD_SELFTEST_FAIL:BACKUP_LEDGER_MISSING " + $ledger)
}

$last = Get-Content -LiteralPath $ledger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
$img = [string]$last.image_path
$man = [string]$last.manifest_path

if(-not (Test-Path -LiteralPath $img -PathType Leaf)){
  Die ("LD_SELFTEST_FAIL:IMAGE_MISSING " + $img)
}
if(-not (Test-Path -LiteralPath $man -PathType Leaf)){
  Die ("LD_SELFTEST_FAIL:MANIFEST_MISSING " + $man)
}

Write-Host "RUN: verify image" -ForegroundColor Cyan

$out2 = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Verify `
  -RepoRoot $RepoRoot `
  -ImagePath $img `
  -ManifestPath $man 2>&1

foreach($x in @(@($out2))){
  [Console]::Out.WriteLine($x)
}

if($LASTEXITCODE -ne 0){
  Die ("LD_SELFTEST_FAIL:VERIFY_FAILED exit=" + $LASTEXITCODE)
}

$joined2 = (@(@($out2)) -join "`n")
if($joined2 -notmatch "LD_VERIFY_IMAGE_OK"){
  Die "LD_SELFTEST_FAIL:VERIFY_TOKEN_MISSING"
}

Write-Host "LD_TIER0_SELFTEST_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
'@

Write-Utf8NoBomLf $Target $body
Parse-Gate $Target
Write-Host "PATCH_OK: RUN_LD_TIER0_SELFTEST_REWRITTEN" -ForegroundColor Green