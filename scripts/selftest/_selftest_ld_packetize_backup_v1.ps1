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
$PacketizeScript = Join-Path $RepoRoot "scripts\storage\ld_packetize_backup_v1.ps1"
$BackupScript = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"

foreach($p in @($PacketLib,$PacketizeScript,$BackupScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

# build fresh backup
$srcPath = Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin"
$acqOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BackupScript -RepoRoot $RepoRoot -SourcePath $srcPath -Mode raw_image -ChunkSizeBytes 262144 2>&1
$acqJoined = (@(@($acqOut)) -join "`n")
foreach($x in @(@($acqOut))){
  [Console]::Out.WriteLine($x)
}
Require ($acqJoined -match "LD_BACKUP_DEVICE_OK") "BACKUP_SETUP_FAIL" ""

$backupLedger = Join-Path $RepoRoot "proofs\receipts\device_backup.ndjson"
$lastBackup = Get-Content -LiteralPath $backupLedger -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
$imagePath = [string]$lastBackup.image_path
$manifestPath = [string]$lastBackup.manifest_path

# packetize
$pktOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PacketizeScript -RepoRoot $RepoRoot -ImagePath $imagePath -BackupManifestPath $manifestPath 2>&1
$pktJoined = (@(@($pktOut)) -join "`n")
foreach($x in @(@($pktOut))){
  [Console]::Out.WriteLine($x)
}
Require ($pktJoined -match "LD_PACKETIZE_BACKUP_OK") "PACKETIZE_FAIL" ""

$packetRootLine = (@(@($pktOut)) | Where-Object { $_ -like "PACKET_ROOT:*" } | Select-Object -Last 1)
Require (-not [string]::IsNullOrWhiteSpace([string]$packetRootLine)) "PACKET_ROOT_MISSING" ""
$packetRoot = ([string]$packetRootLine).Substring("PACKET_ROOT: ".Length)

$manifest = Join-Path $packetRoot "manifest.json"
$packetId = Join-Path $packetRoot "packet_id.txt"
$sha = Join-Path $packetRoot "sha256sums.txt"
$payloadDir = Join-Path $packetRoot "payload"

Require (Test-Path -LiteralPath $manifest -PathType Leaf) "PACKET_MANIFEST_MISSING" $manifest
Require (Test-Path -LiteralPath $packetId -PathType Leaf) "PACKET_ID_MISSING" $packetId
Require (Test-Path -LiteralPath $sha -PathType Leaf) "SHA256SUMS_MISSING" $sha
Require (Test-Path -LiteralPath $payloadDir -PathType Container) "PAYLOAD_DIR_MISSING" $payloadDir

$PacketIdValue = (Get-Content -LiteralPath $packetId -Raw -Encoding UTF8).Trim()
Require ($pid -match '^[a-f0-9]{64}$') "PACKET_ID_BAD" $pid

$shaText = Get-Content -LiteralPath $sha -Raw -Encoding UTF8
Require ($shaText -match 'manifest\.json') "SHA256SUMS_MANIFEST_MISSING" ""
Require ($shaText -match 'packet_id\.txt') "SHA256SUMS_PACKETID_MISSING" ""
Require ($shaText -match 'payload\\') "SHA256SUMS_PAYLOAD_MISSING" ""

Write-Host "PASS: packet root structure" -ForegroundColor Green
Write-Host "PASS: packet id shape" -ForegroundColor Green
Write-Host "PASS: sha256sums emitted" -ForegroundColor Green
Write-Host "SELFTEST_LD_PACKETIZE_BACKUP_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
