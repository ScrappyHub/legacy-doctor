param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$AcquisitionManifestPath,
  [Parameter(Mandatory=$true)][string]$VerifyReceiptPath,
  [Parameter(Mandatory=$true)][string]$ExtractReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ImagePath = (Resolve-Path -LiteralPath $ImagePath).Path
$AcquisitionManifestPath = (Resolve-Path -LiteralPath $AcquisitionManifestPath).Path
$VerifyReceiptPath = (Resolve-Path -LiteralPath $VerifyReceiptPath).Path
$ExtractReceiptPath = (Resolve-Path -LiteralPath $ExtractReceiptPath).Path

$PacketLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_packet_v1.ps1"
if(-not (Test-Path -LiteralPath $PacketLib -PathType Leaf)){
  Die "MISSING_DEP" $PacketLib
}
. $PacketLib

$OutRoot = Join-Path $RepoRoot "proofs\packets"
LDPACKET-EnsureDir $OutRoot

$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$PacketRoot = Join-Path $OutRoot ("packet_" + $stamp)
$PayloadRoot = Join-Path $PacketRoot "payload"
LDPACKET-EnsureDir $PayloadRoot

$ImgDst = Join-Path $PayloadRoot "image.img"
$AcqDst = Join-Path $PayloadRoot "acquisition.manifest.json"
$VerDst = Join-Path $PayloadRoot "verify.receipt.json"
$ExtDst = Join-Path $PayloadRoot "extract.receipt.json"

Copy-Item -LiteralPath $ImagePath -Destination $ImgDst -Force
Copy-Item -LiteralPath $AcquisitionManifestPath -Destination $AcqDst -Force
Copy-Item -LiteralPath $VerifyReceiptPath -Destination $VerDst -Force
Copy-Item -LiteralPath $ExtractReceiptPath -Destination $ExtDst -Force

$acqManifest = Get-Content -LiteralPath $AcquisitionManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$deviceId = [string]$acqManifest.device_id
if([string]::IsNullOrWhiteSpace($deviceId)){
  Die "DEVICE_ID_MISSING" $AcquisitionManifestPath
}

$manifestNoId = LDPACKET-BuildManifestWithoutId `
  -RepoRoot $RepoRoot `
  -PacketRoot $PacketRoot `
  -DeviceId $deviceId `
  -ImagePath $ImagePath `
  -AcqManifestPath $AcquisitionManifestPath `
  -VerifyReceiptPath $VerifyReceiptPath `
  -ExtractReceiptPath $ExtractReceiptPath

$manifestPath = Join-Path $PacketRoot "manifest.json"
LDPACKET-WriteCanonJson $manifestPath $manifestNoId

$packetId = LDPACKET-HexSha256Bytes (LDPACKET-CanonBytes $manifestNoId)
LDPACKET-WriteUtf8NoBomLf (Join-Path $PacketRoot "packet_id.txt") $packetId

$rows = LDPACKET-GetRelativeFileRows $PacketRoot
LDPACKET-WriteSha256Sums -Root $PacketRoot -Rows $rows

Write-Host ("PACKET_ROOT: " + $PacketRoot) -ForegroundColor Green
Write-Host ("PACKET_ID: " + $packetId) -ForegroundColor Green
Write-Output "LD_PACKET_ACQUISITION_OK"