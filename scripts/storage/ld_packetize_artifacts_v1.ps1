param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$ManifestPath,
  [string]$VerifyReceiptPath = "",
  [string]$ExtractReceiptPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ImagePath = (Resolve-Path -LiteralPath $ImagePath).Path
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path

$PacketLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_packet_v1.ps1"
if(-not (Test-Path -LiteralPath $PacketLib -PathType Leaf)){
  Die "MISSING_DEP" $PacketLib
}
. $PacketLib

$PacketRootBase = Join-Path $RepoRoot "proofs\packets"
LDPACKET-EnsureDir $PacketRootBase

$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$PacketRoot = Join-Path $PacketRootBase ("packet_" + $stamp)
LDPACKET-EnsureDir $PacketRoot

$payloadRelPaths = @()

$imgRel = "payload\image" + [IO.Path]::GetExtension($ImagePath)
$manRel = "payload\acquire_manifest.json"

LDPACKET-CopyIntoPacket -SourcePath $ImagePath -PacketRoot $PacketRoot -RelPath $imgRel | Out-Null
LDPACKET-CopyIntoPacket -SourcePath $ManifestPath -PacketRoot $PacketRoot -RelPath $manRel | Out-Null

$payloadRelPaths += $imgRel
$payloadRelPaths += $manRel

if(-not [string]::IsNullOrWhiteSpace($VerifyReceiptPath)){
  $VerifyReceiptPath = (Resolve-Path -LiteralPath $VerifyReceiptPath).Path
  $vrRel = "payload\verify_receipt.ndjson"
  LDPACKET-CopyIntoPacket -SourcePath $VerifyReceiptPath -PacketRoot $PacketRoot -RelPath $vrRel | Out-Null
  $payloadRelPaths += $vrRel
}

if(-not [string]::IsNullOrWhiteSpace($ExtractReceiptPath)){
  $ExtractReceiptPath = (Resolve-Path -LiteralPath $ExtractReceiptPath).Path
  $erRel = "payload\extract_receipt.ndjson"
  LDPACKET-CopyIntoPacket -SourcePath $ExtractReceiptPath -PacketRoot $PacketRoot -RelPath $erRel | Out-Null
  $payloadRelPaths += $erRel
}

$manifestObj = [ordered]@{
  schema = "ld.packet.manifest.v1"
  packet_type = "legacy_doctor.artifact_packet.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  items = @()
}

foreach($rel in @($payloadRelPaths | Sort-Object)){
  $full = Join-Path $PacketRoot $rel
  $manifestObj.items += ,([ordered]@{
    relpath = $rel
    size_bytes = [UInt64](Get-Item -LiteralPath $full).Length
    sha256 = (LDPACKET-HexSha256File $full)
  })
}

$manifestBytes = LDPACKET-CanonBytes $manifestObj
$packetId = LDPACKET-HexSha256Bytes $manifestBytes

$manifestPathOut = Join-Path $PacketRoot "manifest.json"
[IO.File]::WriteAllBytes($manifestPathOut, $manifestBytes)

LDPACKET-WriteUtf8NoBomLf (Join-Path $PacketRoot "packet_id.txt") $packetId

$shaInputs = @($payloadRelPaths) + @("manifest.json", "packet_id.txt")
LDPACKET-WriteSha256Sums -PacketRoot $PacketRoot -RelPaths $shaInputs

Write-Host ("PACKET_ROOT: " + $PacketRoot) -ForegroundColor Green
Write-Host ("PACKET_ID: " + $packetId) -ForegroundColor Green
Write-Output "LD_PACKETIZE_ARTIFACTS_OK"