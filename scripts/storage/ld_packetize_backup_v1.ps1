param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$BackupManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ImagePath = (Resolve-Path -LiteralPath $ImagePath).Path
$BackupManifestPath = (Resolve-Path -LiteralPath $BackupManifestPath).Path

$Lib = Join-Path $RepoRoot "scripts\storage\_lib_ld_packet_v1.ps1"
if(-not (Test-Path -LiteralPath $Lib -PathType Leaf)){
  Die "MISSING_DEP" $Lib
}
. $Lib

if(-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)){
  Die "IMAGE_MISSING" $ImagePath
}
if(-not (Test-Path -LiteralPath $BackupManifestPath -PathType Leaf)){
  Die "MANIFEST_MISSING" $BackupManifestPath
}

$backupManifest = Get-Content -LiteralPath $BackupManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$PacketRoot = Join-Path $RepoRoot ("proofs\packets\backup_packet_" + $stamp)
LDPACKET-EnsureDir $PacketRoot

$payloadDir = Join-Path $PacketRoot "payload"
LDPACKET-EnsureDir $payloadDir

$imgName = Split-Path -Leaf $ImagePath
$manName = Split-Path -Leaf $BackupManifestPath

$packetImagePath = Join-Path $payloadDir $imgName
$packetBackupManifestPath = Join-Path $payloadDir $manName

Copy-Item -LiteralPath $ImagePath -Destination $packetImagePath -Force
Copy-Item -LiteralPath $BackupManifestPath -Destination $packetBackupManifestPath -Force

$manifestNoId = [ordered]@{
  schema = "packet.manifest.v1"
  packet_type = "legacy_doctor.backup.packet.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  payload = @(
    [ordered]@{
      relpath = ("payload\" + $imgName)
      sha256 = (LDPACKET-HexSha256File $packetImagePath)
      kind = "disk_image"
    },
    [ordered]@{
      relpath = ("payload\" + $manName)
      sha256 = (LDPACKET-HexSha256File $packetBackupManifestPath)
      kind = "backup_manifest"
    }
  )
}

$packetId = LDPACKET-BuildPacketId -ManifestWithoutPacketId $manifestNoId

$manifestPath = Join-Path $PacketRoot "manifest.json"
$packetIdPath = Join-Path $PacketRoot "packet_id.txt"

LDPACKET-WriteUtf8NoBomLf $manifestPath (LDPACKET-ToCanonJson $manifestNoId)
LDPACKET-WriteUtf8NoBomLf $packetIdPath $packetId
LDPACKET-WriteSha256Sums -PacketRoot $PacketRoot

Write-Host ("PACKET_ROOT: " + $PacketRoot) -ForegroundColor Green
Write-Host ("PACKET_ID: " + $packetId) -ForegroundColor Green
Write-Output "LD_PACKETIZE_BACKUP_OK"