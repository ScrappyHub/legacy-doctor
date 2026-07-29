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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PacketLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_packet_v1.ps1"
$PacketScript = Join-Path $RepoRoot "scripts\storage\ld_packetize_artifacts_v1.ps1"
$BackupScript = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"

foreach($p in @($PacketLib,$PacketScript,$BackupScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$srcPath = Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin"

$acqOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BackupScript -RepoRoot $RepoRoot -SourcePath $srcPath -Mode raw_image -ChunkSizeBytes 262144 2>&1
$acqJoined = (@(@($acqOut)) -join "`n")
foreach($x in @(@($acqOut))){
  [Console]::Out.WriteLine($x)
}
Require ($acqJoined -match "LD_BACKUP_DEVICE_OK") "ACQUIRE_SETUP_FAIL" ""

$backupLedger = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"
$lastBackup = Get-Content -LiteralPath $backupLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
$imagePath = [string]$lastBackup.image_path
$manifestPath = [string]$lastBackup.manifest_path

$pktOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PacketScript -RepoRoot $RepoRoot -ImagePath $imagePath -ManifestPath $manifestPath 2>&1
$pktJoined = (@(@($pktOut)) -join "`n")
foreach($x in @(@($pktOut))){
  [Console]::Out.WriteLine($x)
}
Require ($pktJoined -match "LD_PACKETIZE_ARTIFACTS_OK") "PACKETIZE_FAIL" ""

$packetRootLine = @(@($pktOut) | Where-Object { $_ -match '^PACKET_ROOT: ' }) | Select-Object -Last 1
$packetIdLine = @(@($pktOut) | Where-Object { $_ -match '^PACKET_ID: ' }) | Select-Object -Last 1

Require (-not [string]::IsNullOrWhiteSpace($packetRootLine)) "PACKET_ROOT_LINE_MISSING" ""
Require (-not [string]::IsNullOrWhiteSpace($packetIdLine)) "PACKET_ID_LINE_MISSING" ""

$packetRoot = $packetRootLine.Substring("PACKET_ROOT: ".Length)
$packetId = $packetIdLine.Substring("PACKET_ID: ".Length)

Require (Test-Path -LiteralPath (Join-Path $packetRoot "manifest.json") -PathType Leaf) "PACKET_MANIFEST_MISSING" ""
Require (Test-Path -LiteralPath (Join-Path $packetRoot "packet_id.txt") -PathType Leaf) "PACKET_ID_FILE_MISSING" ""
Require (Test-Path -LiteralPath (Join-Path $packetRoot "sha256sums.txt") -PathType Leaf) "PACKET_SHA256SUMS_MISSING" ""
Require (Test-Path -LiteralPath (Join-Path $packetRoot "payload\image.img") -PathType Leaf) "PACKET_IMAGE_MISSING" ""
Require (Test-Path -LiteralPath (Join-Path $packetRoot "payload\acquire_manifest.json") -PathType Leaf) "PACKET_ACQUIRE_MANIFEST_MISSING" ""

$packetIdFile = (Get-Content -LiteralPath (Join-Path $packetRoot "packet_id.txt") -Raw -Encoding UTF8).Trim()
Require ($packetIdFile -eq $packetId) "PACKET_ID_MISMATCH" ""

Write-Host "PASS: packet root structure" -ForegroundColor Green
Write-Host "PASS: packet id persistence" -ForegroundColor Green
Write-Host "SELFTEST_LD_PACKETIZE_ARTIFACTS_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"